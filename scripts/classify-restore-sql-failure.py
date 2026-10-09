#!/usr/bin/env python3
"""Classify private psql errors; never expose SQL or row values.

Only disclose static stage, SQLSTATE, numeric SQL line and a strictly validated
unquoted function identifier. The private log is deleted by the restore trap.
"""
import re
import sys

MARKERS = {
    "DIGIY_RESTORE_STAGE_ROLES": "roles",
    "DIGIY_RESTORE_STAGE_SCHEMA": "schema",
    "DIGIY_RESTORE_STAGE_DATA": "data",
}
LOCATION = re.compile(
    r"^psql:/restore/(roles|schema|data)\.sql:([1-9][0-9]{0,8}):\s*ERROR:\s*(.*)$"
)
SQLSTATE = re.compile(r"^([0-9A-Z]{5}):\s*(.*)$")
BARE_STATE = re.compile(r"^([0-9A-Z]{5})$")
FUNCTION = re.compile(
    r"^function\s+([a-z_][a-z_0-9]*(?:\.[a-z_][a-z_0-9]*)?)\s*\(",
    re.IGNORECASE,
)


def classify(path):
    stage, code, sql_line, symbol = "unknown", "unknown", "unknown", "unknown"
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as stream:
            for line in stream:
                marker = line.strip()
                if marker in MARKERS:
                    stage = MARKERS[marker]
                location = LOCATION.match(line)
                if location and code == "unknown":
                    stage, sql_line, remainder = location.groups()
                    verbose_state = SQLSTATE.match(remainder)
                    if verbose_state:
                        code, detail = verbose_state.groups()
                    elif BARE_STATE.fullmatch(remainder):
                        code, detail = remainder, ""
                    else:
                        detail = remainder
                    fn = FUNCTION.match(detail)
                    if fn:
                        candidate = fn.group(1)
                        if len(candidate) <= 128:
                            symbol = candidate.lower()
                    elif detail.startswith("operator does not exist"):
                        symbol = "operator"
    except OSError:
        pass
    return stage, code, sql_line, symbol


if __name__ == "__main__":
    stage, code, sql_line, symbol = classify(
        sys.argv[1] if len(sys.argv) == 2 else "/nonexistent"
    )
    print(
        f"::error::ISOLATED_RESTORE_SQL_STAGE={stage} SQLSTATE={code}"
        f" SQL_LINE={sql_line} MISSING_SYMBOL={symbol}"
    )
