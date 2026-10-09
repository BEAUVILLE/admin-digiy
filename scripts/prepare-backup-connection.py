#!/usr/bin/env python3
"""Use an existing GitHub secret without revealing it or resetting a password.

Normally SUPABASE_DB_URL is a full Postgres URI. For a narrowly supported legacy
configuration, it may contain only the existing DB password; construct the
official session-pooler URI in runner memory and pass it to later workflow steps.

Never print any secrets or add workflow outputs. A one-time add-mask workflow
command protects the newly derived URI from GitHub Actions logging.
"""
import os
import re
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


def candidate_from_unencoded_pooler_uri(raw: str) -> str | None:
    """Repair only the exact DIGIY CORE pooler URI with unsafe password chars.

    Strict prefix and suffix matching keep other projects, hosts, and query
    parameters out of this repair path. Existing valid %-escapes are retained,
    while unescaped reserved characters and bare % signs are encoded.
    """
    prefix = f"postgresql://postgres.{REF}:"
    suffix = f"@{HOST}:5432/postgres"
    if not (raw.startswith(prefix) and raw.endswith(suffix)):
        return None
    password = raw[len(prefix):-len(suffix)]
    if not (8 <= len(password) <= 256):
        return None
    if any(ch.isspace() or ord(ch) < 33 or ord(ch) > 126 for ch in password):
        return None
    if "YOUR-PASSWORD" in password.upper() or "[200~" in password or "://" in password:
        return None
    # Keep already URL-encoded %HH escapes; encode a bare percent sign.
    percent_safe = re.sub(r"%(?![0-9a-fA-F]{2})", "%25", password)
    normalized = prefix + quote(percent_safe, safe="%") + suffix
    if normalized == raw or diagnostic(normalized) is not None:
        return None
    return normalized


def prepare(raw: str, github_env_file: str, output=sys.stdout) -> str:
    # Repair only known-good DIGIY CORE pooler syntax (outer whitespace or
    # URL-reserved characters pasted inside the password). Never print raw.
    repaired_uri = None
    repair_label = None
    clean_raw = raw.strip()
    if clean_raw != raw and diagnostic(clean_raw) is None:
        repaired_uri = clean_raw
        repair_label = "BACKUP_URI_OUTER_WHITESPACE_FIXED"
    elif diagnostic(clean_raw) is not None:
        repaired_uri = candidate_from_unencoded_pooler_uri(clean_raw)
        if repaired_uri is not None:
            repair_label = "BACKUP_URI_PASSWORD_URL_ENCODED"
    if repaired_uri is not None:
        raw = repaired_uri
    result = diagnostic(raw)
    if result is None:
        if not github_env_file:
            output.write("::error::BACKUP_ENV_UNAVAILABLE: runner GitHub attendu.\n")
            return "error"
        # Newly derived full URI must be masked before leaving this step.
        if repaired_uri is not None:
            output.write(f"::add-mask::{raw}\n")
            output.flush()
        with open(github_env_file, "a", encoding="utf-8") as file:
            file.write(f"SUPABASE_DB_URL={raw}\n")
        if repair_label is not None:
            output.write(f"{repair_label}: adresse normalisée en mémoire; connexion non encore testée.\n")
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
