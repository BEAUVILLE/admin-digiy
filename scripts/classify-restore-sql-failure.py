#!/usr/bin/env python3
"""Classify private psql errors using only the private ephemeral error log.

Only disclose static stage, SQLSTATE, numeric SQL line and validated SQL
identifiers in PostgreSQL's error message. Never print SQL or user data.
"""
import re
import sys

MARKERS = {
    "DIGIY_RESTORE_STAGE_ROLES": "roles",
    "DIGIY_RESTORE_STAGE_SCHEMA": "schema",
    "DIGIY_RESTORE_STAGE_DATA": "data",
}
LOCATION = re.compile(
    r"^psql:(/restore/(?:roles|schema|data)\.sql|/digiy-local-auth-jwt\.sql|/digiy-local-auth-audit-ip\.sql):([1-9][0-9]{0,8}):\s*ERROR:\s*(.*)$"
)
SQLSTATE = re.compile(r"^([0-9A-Z]{5}):\s*(.*)$")
BARE_STATE = re.compile(r"^([0-9A-Z]{5})$")
FUNCTION = re.compile(
    r"^function\s+([a-z_][a-z_0-9]*(?:\.[a-z_][a-z_0-9]*)?)\s*\(",
    re.IGNORECASE,
)
IDENT = r"([a-z_][a-z_0-9]{0,62})"
COPY_COLUMN_RELATION = re.compile(
    r'^column "' + IDENT + r'" of relation "' + IDENT + r'" does not exist',
    re.IGNORECASE
)
# Expose only a strictly validated, PostgreSQL-quoted missing relation name.
# No SQL content, values or arbitrary file paths are read or printed.
MISSING_RELATION = re.compile(
    r'^relation "((?:(?:auth|storage|public|supabase_migrations)\.)?[a-z_][a-z_0-9]{0,62})" does not exist(?:$|\s)',
    re.IGNORECASE
)


def classify(path):
    stage, code, sql_line = "unknown", "unknown", "unknown"
    symbol, column, relation = "unknown", "unknown", "unknown"
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
                        else "auth-audit-compat" if source_path == "/digiy-local-auth-audit-ip.sql"
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
                        missing = COPY_COLUMN_RELATION.match(detail)
                        if missing:
                            column, relation = (part.lower() for part in missing.groups())
                    elif stage == "data" and code == "42P01":
                        missing = MISSING_RELATION.match(detail)
                        if missing:
                            relation = missing.group(1).lower()
    except OSError:
        pass
    return stage, code, sql_line, symbol, column, relation


if __name__ == "__main__":
    stage, code, sql_line, symbol, column, relation = classify(
        sys.argv[1] if len(sys.argv) == 2 else "/nonexistent"
    )
    print(
        f"::error::ISOLATED_RESTORE_SQL_STAGE={stage} SQLSTATE={code}"
        f" SQL_LINE={sql_line} MISSING_SYMBOL={symbol}"
        f" MISSING_COLUMN={column} RELATION={relation}"
    )
