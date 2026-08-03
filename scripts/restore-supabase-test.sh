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

for command in openssl sha256sum tar gzip psql; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Commande absente : ${command}" >&2
    exit 69
  }
done

if [[ "$RESTORE_DB_URL" == "${SUPABASE_DB_URL:-__production_non_definie__}" ]]; then
  echo "Refus absolu : la cible de restauration correspond à la base de production." >&2
  exit 73
fi

if [[ -n "${PRODUCTION_PROJECT_REF:-}" && -n "${RESTORE_TARGET_PROJECT_REF:-}" && "$PRODUCTION_PROJECT_REF" == "$RESTORE_TARGET_PROJECT_REF" ]]; then
  echo "Refus absolu : le project-ref de restauration est celui de la production." >&2
  exit 73
fi

if [[ -f "$CHECKSUM_FILE" ]]; then
  (
    cd "$(dirname "$BACKUP_FILE")"
    sha256sum -c "$(basename "$CHECKSUM_FILE")"
  )
fi

# Une nouvelle cible Supabase contient des tables système. On refuse seulement
# une cible qui contient déjà des tables applicatives dans public.
PUBLIC_TABLE_COUNT="$(psql "$RESTORE_DB_URL" -X -v ON_ERROR_STOP=1 -At <<'SQL'
SELECT count(*)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND n.nspname = 'public';
SQL
)"

if [[ "${PUBLIC_TABLE_COUNT:-0}" != "0" && "${ALLOW_NONEMPTY_TARGET:-NO}" != "YES" ]]; then
  echo "Refus : la base de test contient déjà ${PUBLIC_TABLE_COUNT} table(s) dans public." >&2
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

gzip -t "$PLAIN_ARCHIVE"
tar -xzf "$PLAIN_ARCHIVE" -C "$TMP_DIR"
BACKUP_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'digiy-supabase-*' | head -n1)"

if [[ -z "$BACKUP_DIR" ]]; then
  echo "Structure de sauvegarde introuvable." >&2
  exit 65
fi

for file in roles.sql schema.sql data.sql SHA256SUMS; do
  if [[ ! -s "$BACKUP_DIR/$file" ]]; then
    echo "Fichier de restauration absent ou vide : ${file}" >&2
    exit 65
  fi
done

(
  cd "$BACKUP_DIR"
  sha256sum -c SHA256SUMS
)

# Ordre recommandé par Supabase : rôles, schéma, désactivation temporaire
# des triggers, puis données COPY, le tout dans une seule transaction.
psql \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file "$BACKUP_DIR/roles.sql" \
  --file "$BACKUP_DIR/schema.sql" \
  --command 'SET session_replication_role = replica' \
  --file "$BACKUP_DIR/data.sql" \
  --dbname "$RESTORE_DB_URL"

if [[ "${RESTORE_MIGRATION_HISTORY:-NO}" == "YES" && -s "$BACKUP_DIR/history_schema.sql" && -s "$BACKUP_DIR/history_data.sql" ]]; then
  psql \
    --single-transaction \
    --variable ON_ERROR_STOP=1 \
    --file "$BACKUP_DIR/history_schema.sql" \
    --file "$BACKUP_DIR/history_data.sql" \
    --dbname "$RESTORE_DB_URL"
fi

RESTORED_TABLE_COUNT="$(psql "$RESTORE_DB_URL" -X -v ON_ERROR_STOP=1 -At <<'SQL'
SELECT count(*)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND n.nspname = 'public';
SQL
)"

RESTORED_FUNCTION_COUNT="$(psql "$RESTORE_DB_URL" -X -v ON_ERROR_STOP=1 -At <<'SQL'
SELECT count(*)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public';
SQL
)"

printf 'Restauration de test réussie.\n'
printf 'Tables public restaurées : %s\n' "$RESTORED_TABLE_COUNT"
printf 'Fonctions public présentes : %s\n' "$RESTORED_FUNCTION_COUNT"
printf '%s\n' "La base de production n'a pas été modifiée."
printf '%s\n' "Les objets Storage sont vérifiés séparément avant leur réimportation."
