#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

BACKUP_FILE="${1:-}"
CHECKSUM_FILE="${2:-${BACKUP_FILE}.sha256}"

if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
  echo "Usage : BACKUP_PASSPHRASE=... $0 sauvegarde.tar.gz.enc [sauvegarde.tar.gz.enc.sha256]" >&2
  exit 64
fi

if [[ -z "${BACKUP_PASSPHRASE:-}" ]]; then
  echo "BACKUP_PASSPHRASE est requise." >&2
  exit 78
fi

for command in openssl sha256sum tar gzip; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Commande absente : ${command}" >&2
    exit 69
  }
done

if [[ -f "$CHECKSUM_FILE" ]]; then
  (
    cd "$(dirname "$BACKUP_FILE")"
    sha256sum -c "$(basename "$CHECKSUM_FILE")"
  )
else
  echo "Avertissement : fichier SHA256 externe absent." >&2
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
  echo "Structure de sauvegarde non reconnue." >&2
  exit 65
fi

for file in roles.sql schema.sql data.sql SHA256SUMS backup-status.txt; do
  if [[ ! -s "$BACKUP_DIR/$file" ]]; then
    echo "Fichier obligatoire absent ou vide : ${file}" >&2
    exit 65
  fi
done

(
  cd "$BACKUP_DIR"
  sha256sum -c SHA256SUMS
)

ROLE_LINES="$(grep -Ec '^(CREATE|ALTER|GRANT|REVOKE|COMMENT)' "$BACKUP_DIR/roles.sql" || true)"
SCHEMA_LINES="$(grep -Ec '^(CREATE|ALTER|GRANT|REVOKE|COMMENT)' "$BACKUP_DIR/schema.sql" || true)"
DATA_COPY_LINES="$(grep -Ec '^COPY ' "$BACKUP_DIR/data.sql" || true)"

if [[ "$SCHEMA_LINES" == "0" ]]; then
  echo "Le schéma SQL ne contient aucune instruction structurante reconnue." >&2
  exit 65
fi

cat <<EOF
Sauvegarde vérifiée avec succès.
Dossier : $(basename "$BACKUP_DIR")
Instructions rôles détectées : ${ROLE_LINES}
Instructions schéma détectées : ${SCHEMA_LINES}
Blocs COPY détectés : ${DATA_COPY_LINES}
État :
EOF
cat "$BACKUP_DIR/backup-status.txt"
