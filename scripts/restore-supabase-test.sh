#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

BACKUP_FILE="${1:-}"
CHECKSUM_FILE="${2:-${BACKUP_FILE}.sha256}"

if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
  echo "Usage : RESTORE_DB_URL=... BACKUP_PASSPHRASE=... CONFIRM_RESTORE_TEST=YES $0 sauvegarde.tar.gz.enc" >&2
  exit 64
fi

if [[ "${CONFIRM_RESTORE_TEST:-}" != "YES" ]]; then
  echo "Protection active : définir CONFIRM_RESTORE_TEST=YES pour autoriser la restauration de test." >&2
  exit 77
fi

if [[ -z "${RESTORE_DB_URL:-}" || -z "${BACKUP_PASSPHRASE:-}" ]]; then
  echo "RESTORE_DB_URL et BACKUP_PASSPHRASE sont requises." >&2
  exit 78
fi

for command in openssl sha256sum tar pg_restore psql; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Commande absente : ${command}" >&2
    exit 69
  }
done

if [[ "$RESTORE_DB_URL" == "${SUPABASE_DB_URL:-__production_non_definie__}" ]]; then
  echo "Refus absolu : la cible de restauration correspond à la base de production." >&2
  exit 73
fi

if [[ -f "$CHECKSUM_FILE" ]]; then
  (
    cd "$(dirname "$BACKUP_FILE")"
    sha256sum -c "$(basename "$CHECKSUM_FILE")"
  )
fi

USER_TABLE_COUNT="$(psql "$RESTORE_DB_URL" -X -v ON_ERROR_STOP=1 -At <<'SQL'
SELECT count(*)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg_toast%';
SQL
)"

if [[ "${USER_TABLE_COUNT:-0}" != "0" && "${ALLOW_NONEMPTY_TARGET:-NO}" != "YES" ]]; then
  echo "Refus : la base de test contient déjà ${USER_TABLE_COUNT} table(s). Utiliser une base vide." >&2
  exit 73
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

PLAIN_ARCHIVE="$TMP_DIR/backup.tar.gz"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 250000 \
  -in "$BACKUP_FILE" \
  -out "$PLAIN_ARCHIVE" \
  -pass env:BACKUP_PASSPHRASE

tar -xzf "$PLAIN_ARCHIVE" -C "$TMP_DIR"
BACKUP_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'digiy-supabase-*' | head -n1)"

if [[ -z "$BACKUP_DIR" || ! -f "$BACKUP_DIR/database.full.dump" ]]; then
  echo "Dump PostgreSQL introuvable dans l'archive." >&2
  exit 65
fi

(
  cd "$BACKUP_DIR"
  sha256sum -c SHA256SUMS
)

pg_restore \
  --dbname="$RESTORE_DB_URL" \
  --no-owner \
  --no-privileges \
  --exit-on-error \
  "$BACKUP_DIR/database.full.dump"

RESTORED_TABLE_COUNT="$(psql "$RESTORE_DB_URL" -X -v ON_ERROR_STOP=1 -At <<'SQL'
SELECT count(*)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg_toast%';
SQL
)"

RESTORED_FUNCTION_COUNT="$(psql "$RESTORE_DB_URL" -X -v ON_ERROR_STOP=1 -At <<'SQL'
SELECT count(*)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema');
SQL
)"

printf 'Restauration de test réussie.\n'
printf 'Tables restaurées : %s\n' "$RESTORED_TABLE_COUNT"
printf 'Fonctions présentes : %s\n' "$RESTORED_FUNCTION_COUNT"
printf '%s\n' "La base de production n'a pas été modifiée."
