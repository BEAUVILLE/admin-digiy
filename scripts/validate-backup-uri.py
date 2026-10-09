#!/usr/bin/env python3
"""Validate a private Supabase Postgres connection URI without printing secrets.

Never print SUPABASE_DB_URL, username, hostname, URL fragments, or credentials.
No network access, no database reads, no migration, no filesystem output.
"""
import os
import sys
from urllib.parse import unquote, urlsplit

PROJECT_REF = "wesqmwjjtsefyjnluosj"


def diagnostic(uri: str) -> str | None:
    """Return safe code-only diagnostics; never interpolate input URI."""
    if not uri:
        return "BACKUP_URI_MISSING"
    if uri != uri.strip():
        return "BACKUP_URI_OUTER_WHITESPACE"
    if any(ch.isspace() for ch in uri):
        return "BACKUP_URI_WHITESPACE_OR_COMMAND_PASTED"
    if "[" in uri or "]" in uri or "YOUR-PASSWORD" in uri.upper():
        return "BACKUP_URI_TEMPLATE_NOT_FILLED"
    if uri.startswith(("psql ", "postgres ")):
        return "BACKUP_URI_COMMAND_INSTEAD_OF_URI"
    try:
        u = urlsplit(uri)
        if u.scheme not in ("postgresql", "postgres"):
            return "BACKUP_URI_WRONG_SCHEME"
        if u.fragment or u.query:
            return "BACKUP_URI_UNEXPECTED_QUERY_OR_FRAGMENT"
        # .port and .hostname can raise ValueError for malformed URI.
        host = u.hostname
        port = u.port
        username = u.username
        password = u.password
        if not host or not port or not username or not password:
            return "BACKUP_URI_INCOMPLETE"
        if not (host.endswith(".supabase.co") or host.endswith(".supabase.com")):
            return "BACKUP_URI_UNEXPECTED_HOST"
        # Either a direct db.<ref>.supabase.co or a session pooler with
        # postgres.<ref> as username. Do not accept unrelated projects.
        if PROJECT_REF not in host and PROJECT_REF not in username:
            return "BACKUP_URI_WRONG_PROJECT"
        if not u.path or u.path != "/postgres":
            return "BACKUP_URI_DATABASE_PATH"
        if unquote(username).strip() != username:
            return "BACKUP_URI_USERNAME_ENCODING"
        if any(ch in password for ch in "?#/[]"):
            return "BACKUP_URI_PASSWORD_NEEDS_URL_ENCODING"
    except (ValueError, AttributeError):
        return "BACKUP_URI_MALFORMED"
    return None


if __name__ == "__main__":
    error = diagnostic(os.environ.get("SUPABASE_DB_URL", ""))
    if error:
        print(f"::error::{error}: format secret invalide. Correction réservée à l’administrateur GitHub. Ne jamais afficher ni partager la valeur.")
        sys.exit(78)
    print("BACKUP_URI_SYNTAX_OK: structure validée sans révéler l'adresse; connexion réelle pas encore testée.")
