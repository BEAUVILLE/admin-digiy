#!/usr/bin/env python3
"""Use an existing GitHub secret without revealing it or resetting a password.

Normally SUPABASE_DB_URL is a full Postgres URI. For a narrowly supported legacy
configuration, it may contain only the existing DB password; construct the
official session-pooler URI in runner memory and pass it to later workflow steps.

Never print any secrets or add workflow outputs. A one-time add-mask workflow
command protects the newly derived URI from GitHub Actions logging.
"""
import os
import sys
from urllib.parse import quote
from importlib.machinery import SourceFileLoader
from pathlib import Path

diagnostic = SourceFileLoader(
    "backup_uri_validator",
    str(Path(__file__).with_name("validate-backup-uri.py")),
).load_module().diagnostic

REF = "wesqmwjjtsefyjnluosj"
HOST = "aws-1-eu-north-1.pooler.supabase.com"


def candidate_from_legacy_password(raw: str) -> str | None:
    # An opaque, single-line credential is the *only* acceptable fallback.
    # In particular, NEVER try HTTPS URLs, shell commands, template values,
    # JWT / API keys, or values that look like different connection strings.
    if not (8 <= len(raw) <= 256) or raw != raw.strip():
        return None
    if any(ch.isspace() or ord(ch) < 32 or ord(ch) > 126 for ch in raw):
        return None
    if "://" in raw or raw.startswith(("psql", "postgres", "sb_", "eyJ", "$")):
        return None
    if "[YOUR-PASSWORD]" in raw or "[200~" in raw or "\x1b" in raw:
        return None
    if raw.count(".") >= 2 and len(raw) > 48:  # likely JWT or API key
        return None
    encoded = quote(raw, safe="")
    return f"postgresql://postgres.{REF}:{encoded}@{HOST}:5432/postgres"


def prepare(raw: str, github_env_file: str, output=sys.stdout) -> str:
    # Copy/paste into GitHub Actions secrets sometimes adds a leading/trailing
    # newline or space. Normalize *only* when the trimmed value is already a
    # valid PostgreSQL URI for our project. Do not change password-only values.
    trimmed_uri = False
    if raw != raw.strip() and diagnostic(raw.strip()) is None:
        raw = raw.strip()
        trimmed_uri = True
    result = diagnostic(raw)
    if result is None:
        if not github_env_file:
            output.write("::error::BACKUP_ENV_UNAVAILABLE: runner GitHub attendu.\n")
            return "error"
        # If the URI was trimmed, GitHub's secret masker may only know the
        # original whitespace-padded value. Mask the normalized URI BEFORE
        # handing it to subsequent steps. Never print it otherwise.
        if trimmed_uri:
            output.write(f"::add-mask::{raw}\n")
            output.flush()
        with open(github_env_file, "a", encoding="utf-8") as file:
            file.write(f"SUPABASE_DB_URL={raw}\n")
        if trimmed_uri:
            output.write("BACKUP_URI_OUTER_WHITESPACE_FIXED: espaces externes supprimés; connexion non encore testée.\n")
        else:
            output.write("BACKUP_URI_SYNTAX_OK: URI présente; connexion non encore testée.\n")
        return "existing_uri"
    if result != "BACKUP_URI_WRONG_SCHEME":
        output.write(f"::error::{result}: configuration GitHub invalide; aucun secret divulgué.\n")
        return "error"

    candidate = candidate_from_legacy_password(raw)
    if candidate is None or diagnostic(candidate) is not None:
        output.write("::error::BACKUP_URI_WRONG_SCHEME: ni URI ni mot de passe hérité admissible. Intervention administrateur requise.\n")
        return "error"
    if not github_env_file:
        output.write("::error::BACKUP_ENV_UNAVAILABLE: runner GitHub attendu.\n")
        return "error"

    # GitHub Actions explicitly recommends masking any dynamically derived
    # secret BEFORE passing it to later workflow steps. Never echo otherwise.
    output.write(f"::add-mask::{candidate}\n")
    output.flush()
    with open(github_env_file, "a", encoding="utf-8") as file:
        file.write(f"SUPABASE_DB_URL={candidate}\n")
    output.write("BACKUP_URI_LEGACY_PASSWORD_CANDIDATE: format reconstruit en mémoire; authentification encore à confirmer.\n")
    return "legacy_password_candidate"


if __name__ == "__main__":
    state = prepare(os.environ.get("BACKUP_SOURCE_SECRET", ""), os.environ.get("GITHUB_ENV", ""))
    if state == "error":
        sys.exit(78)
