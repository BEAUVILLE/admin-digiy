#!/usr/bin/env python3
"""Classify a private psql restore failure without exposing SQL or row values.

Read only the ephemeral local log. Emit predefined phase, SQLSTATE and numeric
line from a known /restore/*.sql path. Never print SQL, paths or error details.
"""
import re
import sys

MARKERS = {
    "DIGIY_RESTORE_STAGE_ROLES": "roles",
    "DIGIY_RESTORE_STAGE_SCHEMA": "schema",
    "DIGIY_RESTORE_STAGE_DATA": "data",
}
SQLSTATE = re.compile(r"\bERROR:\s*([0-9A-Z]{5})(?![0-9A-Z])")
LOCATION = re.compile(
    r"^psql:/restore/(roles|schema|data)\.sql:([1-9][0-9]{0,8}):\s*ERROR:\s*([0-9A-Z]{5})(?![0-9A-Z])"
)


def classify(path):
    stage, code, sql_line = "unknown", "unknown", "unknown"
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as stream:
            for line in stream:
                marker = line.strip()
                if marker in MARKERS:
                    stage = MARKERS[marker]
                if code == "unknown":
                    location = LOCATION.search(line)
                    if location:
                        stage, sql_line, code = location.groups()
                    else:
                        match = SQLSTATE.search(line)
                        if match:
                            code = match.group(1)
    except OSError:
        pass
    return stage, code, sql_line


if __name__ == "__main__":
    stage, code, sql_line = classify(
        sys.argv[1] if len(sys.argv) == 2 else "/nonexistent"
    )
    print(f"::error::ISOLATED_RESTORE_SQL_STAGE={stage} SQLSTATE={code} SQL_LINE={sql_line}")
