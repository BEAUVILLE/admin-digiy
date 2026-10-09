#!/usr/bin/env python3
"""Classify a private psql restore failure without exposing SQL or row values.

Accept ONLY the local ephemeral PostgreSQL log. Output constants and one SQLSTATE,
never SQL statements, error details, relation names, or private customer data.
"""
import re
import sys

MARKERS = {
    "DIGIY_RESTORE_STAGE_ROLES": "roles",
    "DIGIY_RESTORE_STAGE_SCHEMA": "schema",
    "DIGIY_RESTORE_STAGE_DATA": "data",
}
SQLSTATE = re.compile(r"\bERROR:\s*([0-9A-Z]{5})(?![0-9A-Z])")


def classify(path):
    stage, code = "unknown", "unknown"
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as stream:
            for line in stream:
                marker = line.strip()
                if marker in MARKERS:
                    stage = MARKERS[marker]
                if code == "unknown":
                    match = SQLSTATE.search(line)
                    if match:
                        code = match.group(1)
    except OSError:
        pass
    return stage, code


if __name__ == "__main__":
    stage, code = classify(sys.argv[1] if len(sys.argv) == 2 else "/nonexistent")
    print(f"::error::ISOLATED_RESTORE_SQL_STAGE={stage} SQLSTATE={code}")
