#!/usr/bin/env bash
# DIGIY CORE: restore a previously encrypted GitHub artifact into an ephemeral,
# network-isolated Docker Postgres container. NEVER accepts any target DB URL.
set -Eeuo pipefail
set +x
umask 077

fail() { printf '::error::%s\n' "$1" >&2; exit 78; }

[[ "${CONFIRM_ISOLATED_RESTORE:-}" == "YES" ]] || fail "ISOLATED_RESTORE_NOT_CONFIRMED"
[[ -z "${SUPABASE_DB_URL:-}" && -z "${RESTORE_DB_URL:-}" ]] || fail "REMOTE_DB_URL_FORBIDDEN"
[[ -n "${BACKUP_PASSPHRASE:-}" ]] || fail "BACKUP_PASSPHRASE_MISSING"
[[ -d "${SOURCE_ARTIFACT_DIR:-/nonexistent}" ]] || fail "SOURCE_ARTIFACT_MISSING"
for cmd in docker openssl tar gzip python3; do
  command -v "$cmd" >/dev/null 2>&1 || fail "ISOLATED_RESTORE_TOOL_MISSING"
done

# Linux runners ship sha256sum; macOS normally ships shasum.
# Both tools verify the same standard GNU SHA256 manifest format.
if command -v sha256sum >/dev/null 2>&1; then
  check_sha256_manifest() { sha256sum -c "$1"; }
elif command -v shasum >/dev/null 2>&1; then
  check_sha256_manifest() { shasum -a 256 -c "$1"; }
else
  fail "ISOLATED_SHA256_TOOL_MISSING"
fi

source_dir="${SOURCE_ARTIFACT_DIR}"
# macOS ships Bash 3.2 and BSD find; neither mapfile nor GNU -maxdepth is portable.
# Bash 3.2-safe nullglob matches only direct children of the private directory.
shopt -s nullglob
encrypted_files=( "$source_dir"/digiy-supabase-*.tar.gz.enc )
shopt -u nullglob
[[ "${#encrypted_files[@]}" -eq 1 ]] || fail "ISOLATED_RESTORE_ARCHIVE_COUNT"
archive="${encrypted_files[0]}"
checksum="${archive}.sha256"
[[ -f "$archive" && ! -L "$archive" && -s "$archive" &&
    -f "$checksum" && ! -L "$checksum" && -s "$checksum" ]] || fail "ISOLATED_RESTORE_ARCHIVE_OR_CHECKSUM_MISSING"

# Operators on macOS need decrypted temporary files in a Docker Desktop
# shared, encrypted home location; GitHub defaults to its private runner temp.
restore_work_root="${RESTORE_WORK_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
[[ -d "$restore_work_root" && ! -L "$restore_work_root" ]] || fail "ISOLATED_PRIVATE_WORK_ROOT_INVALID"
tmpdir="$(mktemp -d "$restore_work_root/digiy-restore.XXXXXXXX")"
container="digiy-restore-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  rm -rf -- "$tmpdir"
}
trap cleanup EXIT

# Never print the digest, recovered credentials, restored SQL, or object values.
# GitHub backup SHA256 manifest contains the ORIGINAL runner's absolute
# path. Never read that path; hash the ciphertext downloaded by the operator.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$script_dir/restore-local-auth-jwt.sql" &&
   ! -L "$script_dir/restore-local-auth-jwt.sql" ]] || fail "ISOLATED_AUTH_JWT_BOOTSTRAP_MISSING"
python3 "$script_dir/extract-encrypted-backup-zip.py" --verify-only "$archive" "$checksum" \
  >/dev/null 2>&1 || fail "ISOLATED_RESTORE_ENCRYPTED_CHECKSUM_FAILED"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 250000 \
  -in "$archive" -out "$tmpdir/private.tar.gz" -pass env:BACKUP_PASSPHRASE \
  >"$tmpdir/decrypt-private.log" 2>&1 || fail "ISOLATED_RESTORE_DECRYPT_FAILED"
gzip -t "$tmpdir/private.tar.gz" >"$tmpdir/gzip-private.log" 2>&1 || fail "ISOLATED_RESTORE_GZIP_INVALID"

# Refuse traversal, symlinks and device files in the private archive.
python3 - "$tmpdir/private.tar.gz" <<'PY' || fail "ISOLATED_RESTORE_UNSAFE_TAR"
import pathlib, sys, tarfile
with tarfile.open(sys.argv[1], "r:gz") as archive:
    for member in archive:
        parts = pathlib.PurePosixPath(member.name)
        if (parts.is_absolute() or ".." in parts.parts
            or not parts.parts or not parts.parts[0].startswith("digiy-supabase-")
            or member.issym() or member.islnk() or member.isdev()):
            raise SystemExit(1)
PY

mkdir -p "$tmpdir/extracted"
# Only portable BSD/GNU tar flags. Extraction is non-root in a 0700 temp
# folder; the archive was already checked for traversal, links and devices.
tar -xzf "$tmpdir/private.tar.gz" \
  -C "$tmpdir/extracted" >"$tmpdir/tar-private.log" 2>&1 || fail "ISOLATED_RESTORE_UNPACK_FAILED"
shopt -s nullglob
backup_dirs=( "$tmpdir/extracted"/digiy-supabase-* )
shopt -u nullglob
[[ "${#backup_dirs[@]}" -eq 1 && -d "${backup_dirs[0]:-}" &&
    ! -L "${backup_dirs[0]:-}" ]] || fail "ISOLATED_RESTORE_LAYOUT_INVALID"
backup_dir="${backup_dirs[0]}"
for f in roles.sql schema.sql data.sql SHA256SUMS backup-status.txt; do
  [[ -s "$backup_dir/$f" ]] || fail "ISOLATED_RESTORE_REQUIRED_FILE_MISSING"
done
( cd "$backup_dir" && check_sha256_manifest SHA256SUMS >/dev/null 2>&1 ) || fail "ISOLATED_RESTORE_INTERNAL_CHECKSUM_FAILED"
echo "ISOLATED_ARCHIVE_INTEGRITY_OK: chiffre, checksums et fichiers SQL vérifiés."

# Supabase runs PostgreSQL 17. Disposable container has NO NETWORK, NO
# production URI, NO production DB password, and no persistent volume.
# Any SQL restores ONLY inside this container. DB output is suppressed.
local_password="$(openssl rand -hex 32)"
docker run --rm -d --network none --name "$container" \
  -e POSTGRES_PASSWORD="$local_password" \
  -v "$backup_dir:/restore:ro" \
  -v "$script_dir/restore-local-auth-jwt.sql:/digiy-local-auth-jwt.sql:ro" \
  supabase/postgres:17.6.1.173 \
  postgres -c config_file=/etc/postgresql/postgresql.conf \
  >"$tmpdir/docker-private.log" 2>&1 || fail "ISOLATED_POSTGRES_CONTAINER_START_FAILED"
unset local_password

ready=NO
for attempt in $(seq 1 75); do
  if docker exec "$container" pg_isready -U postgres -d postgres >/dev/null 2>&1; then
    ready=YES
    break
  fi
  sleep 2
done
[[ "$ready" == "YES" ]] || fail "ISOLATED_POSTGRES_NOT_READY"
echo "ISOLATED_POSTGRES_READY: PostgreSQL local sans réseau."

# The official auth schema is owned by supabase_admin, not by postgres.
# Invoke the official auth.jwt() migration ONLY inside the networkless
# disposable database as the local schema owner; no production credentials.
if ! docker exec "$container" psql -U supabase_admin -d postgres -X -w \
  --single-transaction --variable ON_ERROR_STOP=1 \
  --variable VERBOSITY=verbose --variable SHOW_CONTEXT=never \
  --file /digiy-local-auth-jwt.sql \
  >"$tmpdir/auth-bootstrap-private.log" 2>&1; then
  python3 "$script_dir/classify-restore-sql-failure.py" \
    "$tmpdir/auth-bootstrap-private.log" >&2
  fail "ISOLATED_AUTH_JWT_BOOTSTRAP_FAILED"
fi
echo "ISOLATED_AUTH_JWT_BOOTSTRAP_OK: official Auth helper installed locally."


# Supabase CLI filters internal Auth schema/functions from its dump. The only
# required Auth helper was installed by its schema owner above, inside Docker.
# Data restore stays atomic: roles -> schema -> disable triggers -> data.
# Keep ALL original SQL output in a runner-local file deleted by trap.
# Never connect to a remotely supplied address.
# Verbose PostgreSQL errors are held ONLY in a private log deleted by trap.
# The classifier emits a vetted function identifier, never raw SQL or values.
if ! docker exec "$container" psql -U postgres -d postgres -X -w \
  --single-transaction --variable ON_ERROR_STOP=1 \
  --variable VERBOSITY=verbose --variable SHOW_CONTEXT=never \
  --command '\echo DIGIY_RESTORE_STAGE_ROLES' \
  --file /restore/roles.sql \
  --command '\echo DIGIY_RESTORE_STAGE_SCHEMA' \
  --file /restore/schema.sql \
  --command '\echo DIGIY_RESTORE_STAGE_DATA' \
  --command 'SET session_replication_role = replica' \
  --file /restore/data.sql \
  >"$tmpdir/sql-private.log" 2>&1; then
  python3 "$script_dir/classify-restore-sql-failure.py" "$tmpdir/sql-private.log" >&2
  fail "ISOLATED_RESTORE_SQL_FAILED"
fi
echo "ISOLATED_RESTORE_SQL_OK: rôles, schéma et données exécutés dans le conteneur."
# Probe only the no-session behavior; this does NOT prove authenticated owners.
jwt_probe="$(docker exec "$container" psql -U postgres -d postgres -X -w -Atq \
  -v ON_ERROR_STOP=1 -c "SELECT auth.jwt() IS NULL;" \
  2>"$tmpdir/jwt-private.log")" || fail "ISOLATED_AUTH_JWT_PROBE_FAILED"
[[ "$jwt_probe" == "t" ]] || fail "ISOLATED_AUTH_JWT_PROBE_INVALID"
echo "ISOLATED_AUTH_JWT_HELPER_OK: helper present in local container (not an Auth login test)."


# Source snapshot (2026-10-09 01:46 UTC): 81 legacy blocked rows and 0
# reservations. Return only aggregate integers, no customer records.
result="$(docker exec "$container" psql -U postgres -d postgres -X -w -Atq \
  -v ON_ERROR_STOP=1 -c "
SELECT (SELECT count(*) FROM public.digiy_loc_master_unit_calendar),
       (SELECT count(*) FROM public.digiy_loc_master_unit_calendar
         WHERE status IN ('occupied','closed')),
       (SELECT count(*) FROM public.digiy_loc_master_reservations),
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname='digiy_loc_master_save_reservation_v1');
" 2>"$tmpdir/count-private.log")" || fail "ISOLATED_RESTORE_AGGREGATE_QUERY_FAILED"
[[ "$result" == "81|81|0|1" ]] || fail "ISOLATED_RESTORE_EXPECTED_MASTER_COUNTS_NOT_MET"
echo "ISOLATED_RESTORE_PROOF_OK: 81/81 jours historiques bloqués, 0 réservation MASTER, RPC principale présente."
echo "ISOLATED_RESTORE_PRODUCTION_UNTOUCHED: aucune cible distante accessible depuis le conteneur."
