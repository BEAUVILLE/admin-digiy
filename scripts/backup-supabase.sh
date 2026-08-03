#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

required=(SUPABASE_DB_URL BACKUP_PASSPHRASE)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Variable requise absente : ${name}" >&2
    exit 78
  fi
done

for command in pg_dump pg_restore psql openssl sha256sum tar gzip; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Commande absente : ${command}" >&2
    exit 69
  fi
done

STAMP="$(date -u +'%Y-%m-%dT%H-%M-%SZ')"
BACKUP_ROOT="${BACKUP_ROOT:-$PWD/.backup-work}"
WORK_DIR="${BACKUP_ROOT}/digiy-supabase-${STAMP}"
OUTPUT_DIR="${BACKUP_OUTPUT_DIR:-$PWD/backup-output}"
ARCHIVE_BASE="digiy-supabase-${STAMP}"
PLAIN_ARCHIVE="${OUTPUT_DIR}/${ARCHIVE_BASE}.tar.gz"
ENCRYPTED_ARCHIVE="${PLAIN_ARCHIVE}.enc"
ENCRYPTED_CHECKSUM="${ENCRYPTED_ARCHIVE}.sha256"

cleanup() {
  rm -rf "$WORK_DIR"
  rm -f "$PLAIN_ARCHIVE"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

printf '%s\n' "DIGIYLYFE — sauvegarde Supabase" > "$WORK_DIR/README.txt"
printf 'Créée en UTC : %s\n' "$STAMP" >> "$WORK_DIR/README.txt"
printf '%s\n' "Format : PostgreSQL custom + schéma SQL + inventaires + stockage optionnel" >> "$WORK_DIR/README.txt"
printf '%s\n' "Restauration : utiliser scripts/verify-supabase-backup.sh puis scripts/restore-supabase-test.sh" >> "$WORK_DIR/README.txt"

# Le dump custom est la source principale de restauration.
pg_dump "$SUPABASE_DB_URL" \
  --format=custom \
  --compress=9 \
  --no-owner \
  --no-privileges \
  --file="$WORK_DIR/database.full.dump"

# Le schéma lisible facilite l'audit humain et le diagnostic.
pg_dump "$SUPABASE_DB_URL" \
  --schema-only \
  --no-owner \
  --no-privileges \
  --file="$WORK_DIR/database.schema.sql"

# Inventaire vérifiable sans révéler le contenu des lignes.
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -At -F $'\t' <<'SQL' > "$WORK_DIR/table-row-estimates.tsv"
SELECT
  schemaname,
  relname,
  COALESCE(n_live_tup, 0)::bigint
FROM pg_stat_user_tables
ORDER BY schemaname, relname;
SQL

psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -At -F $'\t' <<'SQL' > "$WORK_DIR/storage-object-manifest.tsv"
SELECT bucket_id, name
FROM storage.objects
ORDER BY bucket_id, name;
SQL

# Les octets Storage sont exportés seulement quand les deux secrets existent.
STORAGE_STATUS="metadata_only"
if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  STORAGE_STATUS="full_objects"
  mkdir -p "$WORK_DIR/storage"

  python3 - "$WORK_DIR/storage-object-manifest.tsv" "$WORK_DIR/storage" <<'PY'
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

manifest = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2]).resolve()
base_url = os.environ["SUPABASE_URL"].rstrip("/")
service_key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

failures = []
downloaded = 0

for raw_line in manifest.read_text(encoding="utf-8").splitlines():
    if not raw_line.strip():
        continue
    try:
        bucket, object_name = raw_line.split("\t", 1)
    except ValueError:
        failures.append(f"manifest_invalide:{raw_line}")
        continue

    bucket_safe = bucket.replace("/", "_").replace("\\", "_")
    relative = pathlib.PurePosixPath(object_name)
    if relative.is_absolute() or ".." in relative.parts:
        failures.append(f"chemin_refuse:{bucket}/{object_name}")
        continue

    target = destination / bucket_safe
    for part in relative.parts:
        target = target / part
    target = target.resolve()
    if destination not in target.parents:
        failures.append(f"sortie_refusee:{bucket}/{object_name}")
        continue

    target.parent.mkdir(parents=True, exist_ok=True)
    encoded_bucket = urllib.parse.quote(bucket, safe="")
    encoded_name = urllib.parse.quote(object_name, safe="/")
    url = f"{base_url}/storage/v1/object/authenticated/{encoded_bucket}/{encoded_name}"
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {service_key}",
            "apikey": service_key,
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            with target.open("wb") as output:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    output.write(chunk)
        downloaded += 1
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        failures.append(f"telechargement_echoue:{bucket}/{object_name}:{exc}")

(destination / "EXPORT-RESULT.txt").write_text(
    f"objets_telecharges={downloaded}\nobjets_echoues={len(failures)}\n"
    + "\n".join(failures),
    encoding="utf-8",
)

if failures:
    print("Des objets Storage n'ont pas pu être exportés :", file=sys.stderr)
    for failure in failures:
        print(f"- {failure}", file=sys.stderr)
    sys.exit(3)
PY
fi

printf 'storage_backup=%s\n' "$STORAGE_STATUS" > "$WORK_DIR/backup-status.txt"
printf 'database_backup=full_custom_dump\n' >> "$WORK_DIR/backup-status.txt"

(
  cd "$WORK_DIR"
  sha256sum database.full.dump database.schema.sql table-row-estimates.tsv storage-object-manifest.tsv > SHA256SUMS
  if [[ -d storage ]]; then
    find storage -type f -print0 | sort -z | xargs -0 sha256sum >> SHA256SUMS
  fi
)

# Validation structurelle avant chiffrement.
pg_restore --list "$WORK_DIR/database.full.dump" >/dev/null

# Archive puis chiffrement fort. Aucun dump en clair n'est conservé en sortie.
tar -C "$BACKUP_ROOT" -czf "$PLAIN_ARCHIVE" "$(basename "$WORK_DIR")"
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 250000 \
  -in "$PLAIN_ARCHIVE" \
  -out "$ENCRYPTED_ARCHIVE" \
  -pass env:BACKUP_PASSPHRASE
sha256sum "$ENCRYPTED_ARCHIVE" > "$ENCRYPTED_CHECKSUM"

# Test immédiat du mot de passe et de l'intégrité de l'enveloppe chiffrée.
openssl enc -d -aes-256-cbc -pbkdf2 -iter 250000 \
  -in "$ENCRYPTED_ARCHIVE" \
  -pass env:BACKUP_PASSPHRASE \
  | gzip -t

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "backup_file=$ENCRYPTED_ARCHIVE"
    echo "checksum_file=$ENCRYPTED_CHECKSUM"
    echo "artifact_name=$ARCHIVE_BASE"
    echo "storage_status=$STORAGE_STATUS"
  } >> "$GITHUB_OUTPUT"
fi

printf 'Sauvegarde chiffrée créée : %s\n' "$ENCRYPTED_ARCHIVE"
printf 'Somme de contrôle : %s\n' "$ENCRYPTED_CHECKSUM"
printf 'Storage : %s\n' "$STORAGE_STATUS"
