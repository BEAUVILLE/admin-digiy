#!/usr/bin/env python3
"""Redacted classification of local isolated PostgreSQL restore failures.

This helper reads only ephemeral private files and emits predefined metadata:
phase, SQLSTATE, line number, validated SQL identifier and (only for data COPY
errors) validated column and table identifiers. No SQL source or data values.
"""
import itertools
import re
import sys

MARKERS = {
    "DIGIY_RESTORE_STAGE_ROLES": "roles",
    "DIGIY_RESTORE_STAGE_SCHEMA": "schema",
    "DIGIY_RESTORE_STAGE_DATA": "data",
}
LOCATION = re.compile(
    r"^psql:(/restore/(?:roles|schema|data)\.sql|/digiy-local-auth-jwt\.sql):([1-9][0-9]{0,8}):\s*ERROR:\s*(.*)$"
)
SQLSTATE = re.compile(r"^([0-9A-Z]{5}):\s*(.*)$")
BARE_STATE = re.compile(r"^([0-9A-Z]{5})$")
FUNCTION = re.compile(
    r"^function\s+([a-z_][a-z_0-9]*(?:\.[a-z_][a-z_0-9]*)?)\s*\(",
    re.IGNORECASE,
)
IDENT = r"([a-z_][a-z_0-9]{0,62})"
MISSING_COLUMN_RELATION = re.compile(
    r'^column "' + IDENT + r'" of relation "' + IDENT + r'" does not exist',
    re.IGNORECASE,
)
MISSING_COLUMN = re.compile(
    r'^column "' + IDENT + r'" does not exist', re.IGNORECASE
)
COPY_TARGET = re.compile(
    r"^COPY\s+(auth|storage|public|supabase_migrations)\."
    + IDENT + r"\s+\(", re.IGNORECASE
)


def copy_target(data_file, line_number):
    """Read the failing SQL line, return only a validated schema.table identifier."""
    try:
        number = int(line_number)
        if number < 1 or number > 1_000_000 or not data_file:
            return "unknown"
        with open(data_file, "r", encoding="utf-8", errors="replace") as handle:
            line = next(itertools.islice(handle, number - 1, number), "")
        match = COPY_TARGET.match(line)
        if match:
            return match.group(1).lower() + "." + match.group(2).lower()
    except (OSError, ValueError):
        pass
    return "unknown"


def classify(path, data_file=None):
    stage, code, sql_line = "unknown", "unknown", "unknown"
    symbol, column, target = "unknown", "unknown", "unknown"
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as stream:
            for line in stream:
                marker = line.strip()
                if marker in MARKERS:
                    stage = MARKERS[marker]
                location = LOCATION.match(line)
                if location and code == "unknown":
                    source_path, sql_line, remainder = location.groups()
                    stage = (
                        "auth-bootstrap" if source_path == "/digiy-local-auth-jwt.sql"
                        else source_path.split("/")[-1].removesuffix(".sql")
                    )
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
                    if stage == "data" and code == "42703":
                        match = MISSING_COLUMN_RELATION.match(detail)
                        if match:
                            column = match.group(1).lower()
                        else:
                            match = MISSING_COLUMN.match(detail)
                            if match:
                                column = match.group(1).lower()
                        target = copy_target(data_file, sql_line)
    except OSError:
        pass
    return stage, code, sql_line, symbol, column, target


if __name__ == "__main__":
    stage, code, sql_line, symbol, column, target = classify(
        sys.argv[1] if len(sys.argv) >= 2 else "/nonexistent",
        sys.argv[2] if len(sys.argv) >= 3 else None,
    )
    print(
        f"::error::ISOLATED_RESTORE_SQL_STAGE={stage} SQLSTATE={code}"
        f" SQL_LINE={sql_line} MISSING_SYMBOL={symbol}"
        f" MISSING_COLUMN={column} COPY_TARGET={target}"
    )
