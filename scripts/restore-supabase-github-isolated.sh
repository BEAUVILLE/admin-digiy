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
[[ -f "$script_dir/restore-local-auth-audit-ip.sql" &&
   ! -L "$script_dir/restore-local-auth-audit-ip.sql" ]] || fail "ISOLATED_AUTH_AUDIT_COMPAT_MISSING"
[[ -f "$script_dir/restore-local-storage-multipart.sql" &&
   ! -L "$script_dir/restore-local-storage-multipart.sql" ]] || fail "ISOLATED_STORAGE_MULTIPART_SQL_MISSING"
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
# New backup archives carry REVOKE/GRANT for three RESTO owner RPCs.
# Older archives remain recoverable for DATA, but not as permission proofs.
resto_acl_snapshot=NO
if grep -q '^resto_owner_rpc_acl=verified_v1$' "$backup_dir/backup-status.txt"; then
  [[ -s "$backup_dir/resto-owner-rpc-acl.sql" &&
     ! -L "$backup_dir/resto-owner-rpc-acl.sql" ]] ||
    fail "ISOLATED_RESTO_OWNER_RPC_ACL_MISSING"
  [[ "$(grep -c '^REVOKE ALL ON FUNCTION public.digiy_resa_resto_' "$backup_dir/resto-owner-rpc-acl.sql")" == 3 &&
     "$(grep -c '^GRANT EXECUTE ON FUNCTION public.digiy_resa_resto_' "$backup_dir/resto-owner-rpc-acl.sql")" == 3 ]] ||
     fail "ISOLATED_RESTO_OWNER_RPC_ACL_INVALID"
  resto_acl_snapshot=YES
elif [[ -e "$backup_dir/resto-owner-rpc-acl.sql" ]]; then
  fail "ISOLATED_RESTO_OWNER_RPC_ACL_STATUS_MISMATCH"
fi

# Capture V9 function + pilot-control ACL in new archives. Historical archives
# can still restore data, but can never pass a V9 security certification.
resa_v9_acl_snapshot=NO
if grep -q '^resa_v9_acl=verified_v1$' "$backup_dir/backup-status.txt"; then
  [[ -s "$backup_dir/resa-v9-acl.sql" &&
     ! -L "$backup_dir/resa-v9-acl.sql" ]] || fail "ISOLATED_RESA_V9_ACL_MISSING"
  [[ "$(grep -c '^REVOKE ALL ON FUNCTION public.digiy_resa_universal_' "$backup_dir/resa-v9-acl.sql")" == 5 &&
     "$(grep -c '^GRANT EXECUTE ON FUNCTION public.digiy_resa_universal_' "$backup_dir/resa-v9-acl.sql")" == 5 &&
     "$(grep -c '^REVOKE ALL ON TABLE public.digiy_resa_universal_launch_controls ' "$backup_dir/resa-v9-acl.sql")" == 1 &&
     "$(grep -c '^GRANT ALL ON TABLE public.digiy_resa_universal_launch_controls ' "$backup_dir/resa-v9-acl.sql")" == 1 ]] ||
      fail "ISOLATED_RESA_V9_ACL_INVALID"
  resa_v9_acl_snapshot=YES
elif [[ -e "$backup_dir/resa-v9-acl.sql" ]]; then
  fail "ISOLATED_RESA_V9_ACL_STATUS_MISMATCH"
fi

echo "ISOLATED_ARCHIVE_INTEGRITY_OK: chiffre, checksums et fichiers SQL vérifiés."

# Supabase runs PostgreSQL 17. Disposable container has NO NETWORK, NO
# production URI, NO production DB password, and no persistent volume.
# Any SQL restores ONLY inside this container. DB output is suppressed.
local_password="$(openssl rand -hex 32)"
docker run --rm -d --network none --name "$container" \
  -e POSTGRES_PASSWORD="$local_password" \
  -v "$backup_dir:/restore:ro" \
  -v "$script_dir/restore-local-auth-jwt.sql:/digiy-local-auth-jwt.sql:ro" \
  -v "$script_dir/restore-local-auth-audit-ip.sql:/digiy-local-auth-audit-ip.sql:ro" \
  -v "$script_dir/restore-local-storage-multipart.sql:/digiy-local-storage-multipart.sql:ro" \
  supabase/postgres:17.6.1.173 \
  postgres -c config_file=/etc/postgresql/postgresql.conf \
  >"$tmpdir/docker-private.log" 2>&1 || fail "ISOLATED_POSTGRES_CONTAINER_START_FAILED"

ready=NO
for attempt in $(seq 1 75); do
  if [[ "$(docker exec "$container" psql -U postgres -d postgres -X -w -Atq -c 'SELECT 1' 2>/dev/null)" == "1" ]]; then
    ready=YES
    break
  fi
  sleep 2
done
[[ "$ready" == "YES" ]] || fail "ISOLATED_POSTGRES_NOT_READY"
echo "ISOLATED_POSTGRES_READY: PostgreSQL local sans réseau."

# The PostgreSQL image alone includes only five Auth tables, versus 27 in
# the cloud snapshot. Apply the pinned OFFICIAL GoTrue migrations, never
# placeholder tables. The migrator shares the network namespace of the
# "--network none" Postgres container: localhost only; zero external routes.
# Runtime passwords stay in an owner-only ephemeral env file, never stdout.
auth_migration_env="$tmpdir/auth-migrate-private.env"
auth_jwt_secret="$(openssl rand -hex 32)"
{
  printf 'DATABASE_URL=postgres://supabase_admin:%s@127.0.0.1:5432/postgres?sslmode=disable\n' "$local_password"
  printf 'DB_NAMESPACE=auth\nGOTRUE_DB_DRIVER=postgres\n'
  printf 'GOTRUE_JWT_SECRET=%s\n' "$auth_jwt_secret"
  printf 'API_EXTERNAL_URL=http://localhost:9999\nGOTRUE_SITE_URL=http://localhost:9999\n'
} >"$auth_migration_env"
unset auth_jwt_secret
if ! docker run --rm --network "container:$container" \
  --env-file "$auth_migration_env" \
  supabase/gotrue:v2.197.0 auth migrate \
  >"$tmpdir/auth-migrations-private.log" 2>&1; then
  fail "ISOLATED_AUTH_MIGRATIONS_FAILED"
fi
rm -f -- "$auth_migration_env"
echo "ISOLATED_AUTH_MIGRATIONS_OK: official GoTrue 2.197.0 schema, local only."

# No real rows or credentials displayed; compare only aggregate schema counts.
auth_table_count="$(docker exec "$container" psql -U postgres -d postgres \
  -X -w -Atq -v ON_ERROR_STOP=1 -c "
  SELECT count(*) FROM pg_class c JOIN pg_namespace n
    ON n.oid=c.relnamespace
  WHERE n.nspname='auth' AND c.relkind IN ('r','p');"
  2>"$tmpdir/auth-catalog-private.log")" || fail "ISOLATED_AUTH_CATALOG_QUERY_FAILED"
[[ "$auth_table_count" == "27" ]] || fail "ISOLATED_AUTH_CATALOG_TABLES_MISMATCH"
echo "ISOLATED_AUTH_CATALOG_OK: 27 Auth tables in networkless database."

# Bring internal Storage schema up to the same official release, inside the
# Postgres container's isolated loopback namespace only. No remote credentials.
storage_migration_env="$tmpdir/storage-migrate-private.env"
storage_jwt_secret="$(openssl rand -hex 32)"
{
  printf 'DATABASE_URL=postgresql://supabase_admin:%s@127.0.0.1:5432/postgres?sslmode=disable\n' "$local_password"
  printf 'DB_INSTALL_ROLES=false\nDB_SUPER_USER=postgres\n'
  printf 'AUTH_JWT_SECRET=%s\n' "$storage_jwt_secret"
} >"$storage_migration_env"
unset storage_jwt_secret local_password
if ! docker run --rm --network "container:$container" \
  --env-file "$storage_migration_env" \
  supabase/storage-api:v1.80.2 node dist/scripts/migrate-call.js \
  >"$tmpdir/storage-migrations-private.log" 2>&1; then
  fail "ISOLATED_STORAGE_MIGRATIONS_FAILED"
fi
rm -f -- "$storage_migration_env"
echo "ISOLATED_STORAGE_MIGRATIONS_OK: official Storage 1.80.2 schema, local only."

# The Storage image's runnable migrations do not install the older S3
# multipart tables, although the cloud dump requires them. Apply the exact
# official 0021,0022,0025,0057 migrations bundled read-only and verify types.
if ! docker exec "$container" psql -U supabase_admin -d postgres -X -w \
  --single-transaction --variable ON_ERROR_STOP=1 \
  --variable VERBOSITY=verbose --variable SHOW_CONTEXT=never \
  --file /digiy-local-storage-multipart.sql \
  >"$tmpdir/storage-compat-private.log" 2>&1; then
  fail "ISOLATED_STORAGE_MULTIPART_COMPAT_FAILED"
fi
echo "ISOLATED_STORAGE_MULTIPART_COMPAT_OK: official S3 multipart tables installed locally."

storage_catalog_count="$(docker exec "$container" psql -U postgres -d postgres \
  -X -w -Atq -v ON_ERROR_STOP=1 -c "
SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='storage' AND c.relkind IN ('r','p')
  AND c.relname = ANY(ARRAY[
   'buckets','buckets_analytics','buckets_vectors','migrations','objects',
   's3_multipart_uploads','s3_multipart_uploads_parts','vector_indexes']);"
  2>"$tmpdir/storage-catalog-private.log")" || fail "ISOLATED_STORAGE_CATALOG_QUERY_FAILED"
[[ "$storage_catalog_count" == "8" ]] || fail "ISOLATED_STORAGE_CATALOG_TABLES_MISMATCH"
echo "ISOLATED_STORAGE_CATALOG_OK: all 8 cloud Storage tables available locally."



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

# Align the local Docker Auth audit table with the live source's checked column
# contract (varchar(64) NOT NULL DEFAULT ''). Do not modify or skip backup rows.
# The pinned Supabase image lacks this column, but DIGIY CORE has it.
if ! docker exec "$container" psql -U supabase_admin -d postgres -X -w \
  --single-transaction --variable ON_ERROR_STOP=1 \
  --variable VERBOSITY=verbose --variable SHOW_CONTEXT=never \
  --file /digiy-local-auth-audit-ip.sql \
  >"$tmpdir/audit-compat-private.log" 2>&1; then
  python3 "$script_dir/classify-restore-sql-failure.py" \
    "$tmpdir/audit-compat-private.log" >&2
  fail "ISOLATED_AUTH_AUDIT_COMPAT_FAILED"
fi
echo "ISOLATED_AUTH_AUDIT_COMPAT_OK: Auth audit column matched locally; no rows skipped."


# Supabase CLI filters internal Auth schema/functions from its dump. The needed
# Auth helper and audit-column compatibility were installed above, in Docker.
# Data restore stays atomic: roles -> schema -> disable triggers -> data.
# Keep ALL original SQL output in a runner-local file deleted by trap.
# Never connect to a remotely supplied address.
# Verbose PostgreSQL errors are held ONLY in a private log deleted by trap.
# The classifier emits a vetted function identifier, never raw SQL or values.
# The official Auth migrations own internal tables as supabase_admin.
# Restore with the disposable DB's local schema owner; NEVER a remote URI.
resto_acl_restore_args=()
if [[ "$resto_acl_snapshot" == YES ]]; then
  resto_acl_restore_args=(--file /restore/resto-owner-rpc-acl.sql)
fi
resa_v9_acl_restore_args=()
if [[ "$resa_v9_acl_snapshot" == YES ]]; then
  resa_v9_acl_restore_args=(--file /restore/resa-v9-acl.sql)
fi
if ! docker exec "$container" psql -U supabase_admin -d postgres -X -w \
  --single-transaction --variable ON_ERROR_STOP=1 \
  --variable VERBOSITY=verbose --variable SHOW_CONTEXT=never \
  --command '\echo DIGIY_RESTORE_STAGE_ROLES' \
  --file /restore/roles.sql \
  --command '\echo DIGIY_RESTORE_STAGE_SCHEMA' \
  --file /restore/schema.sql \
  --command '\echo DIGIY_RESTORE_STAGE_DATA' \
  --command 'SET session_replication_role = replica' \
  --file /restore/data.sql \
  "${resto_acl_restore_args[@]}" \
  "${resa_v9_acl_restore_args[@]}" \
  >"$tmpdir/sql-private.log" 2>&1; then
  python3 "$script_dir/classify-restore-sql-failure.py" "$tmpdir/sql-private.log" >&2
  fail "ISOLATED_RESTORE_SQL_FAILED"
fi
echo "ISOLATED_RESTORE_SQL_OK: rôles, schéma et données exécutés dans le conteneur."

if [[ "$resto_acl_snapshot" == YES ]]; then
  acl_proof="$(docker exec "$container" psql -U postgres -d postgres -X -w -Atq \
    -v ON_ERROR_STOP=1 -c "
SELECT count(*) FILTER(WHERE has_function_privilege('anon',p.oid,'EXECUTE'))::text
 || '|' || count(*)::text
 || '|' || count(*) FILTER(WHERE has_function_privilege('authenticated',p.oid,'EXECUTE'))::text
 || '|' || count(*) FILTER(WHERE has_function_privilege('service_role',p.oid,'EXECUTE'))::text
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND (p.proname,pg_get_function_identity_arguments(p.oid)) IN (
 ('digiy_resa_resto_claim_site_by_email_v1','p_slug text'),
 ('digiy_resa_resto_owner_refresh_no_shows_v1','p_site_id uuid'),
 ('digiy_resa_resto_owner_set_booking_status_v1','p_booking_id uuid, p_status text')
);" 2>"$tmpdir/resto-owner-acl-check-private.log")" ||
    fail "ISOLATED_RESTO_OWNER_RPC_ACL_QUERY_FAILED"
  [[ "$acl_proof" == '0|3|3|3' ]] ||
    fail "ISOLATED_RESTO_OWNER_RPC_ACL_RESTORED_UNSAFE"
  echo "ISOLATED_RESTO_OWNER_RPC_ACL_OK: anon=0/3 authenticated=3/3 service_role=3/3."
else
  echo "ISOLATED_RESTO_OWNER_RPC_ACL_NOT_CAPTURED: legacy archive; permissions incompletes."
fi
# Probe only the no-session behavior; this does NOT prove authenticated owners.
jwt_probe="$(docker exec "$container" psql -U postgres -d postgres -X -w -Atq \
  -v ON_ERROR_STOP=1 -c "SELECT auth.jwt() IS NULL;" \
  2>"$tmpdir/jwt-private.log")" || fail "ISOLATED_AUTH_JWT_PROBE_FAILED"
[[ "$jwt_probe" == "t" ]] || fail "ISOLATED_AUTH_JWT_PROBE_INVALID"
echo "ISOLATED_AUTH_JWT_HELPER_OK: helper present in local container (not an Auth login test)."


# Source snapshot baseline is supplied by the operator from a freshly
# verified live, read-only aggregate. Default=81 for historical fixtures.
# Fresh archives require an EXPLICIT expected count; never self-learn from the
# restored data and never weaken the count check to >=81.
expected_blocked="${DIGIY_EXPECTED_MASTER_BLOCKED_DAYS:-81}"
if ! [[ "$expected_blocked" =~ ^[1-9][0-9]*$ ]] ||
   [[ "${#expected_blocked}" -gt 6 ]] ||
   [[ "$expected_blocked" -lt 81 ]] ||
   [[ "$expected_blocked" -gt 999999 ]]; then
  fail "ISOLATED_EXPECTED_BLOCKED_DAYS_INVALID"
fi

# Return ONLY aggregate integers: never output private client rows or SQL.
result="$(docker exec "$container" psql -U postgres -d postgres -X -w -Atq \
  -v ON_ERROR_STOP=1 -c "
SELECT (SELECT count(*) FROM public.digiy_loc_master_unit_calendar),
       (SELECT count(*) FROM public.digiy_loc_master_unit_calendar
         WHERE status IN ('occupied','closed')),
       (SELECT count(*) FROM public.digiy_loc_master_reservations),
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname='digiy_loc_master_save_reservation_v1');
" 2>"$tmpdir/count-private.log")" || fail "ISOLATED_RESTORE_AGGREGATE_QUERY_FAILED"
if [[ "$result" != "$expected_blocked|$expected_blocked|0|1" ]]; then
  if [[ "$result" =~ ^[0-9]+[|][0-9]+[|][0-9]+[|][0-9]+$ ]]; then
    echo "::error::ISOLATED_RESTORE_AGGREGATE_MISMATCH: calendar|blocked|reservations|rpc=$result expected=$expected_blocked|$expected_blocked|0|1" >&2
  fi
  fail "ISOLATED_RESTORE_EXPECTED_MASTER_COUNTS_NOT_MET"
fi
echo "ISOLATED_RESTORE_PROOF_OK: $expected_blocked/$expected_blocked jours bloqués, 0 réservation MASTER, RPC principale présente."
# RESTO archive snapshot proof is opt-in because older synthetic fixtures and
# non-RESTO backups do not contain the restaurant schema. No extra credentials
# or network connections; run only inside the already-isolated Docker container.
if [[ -n "${DIGIY_EXPECTED_RESTO_COUNTS:-}" ]]; then
  [[ -f "$script_dir/verify-resto-restored-snapshot.sh" ]] ||
    fail "RESTO_ISOLATED_PROOF_SCRIPT_MISSING"
  bash "$script_dir/verify-resto-restored-snapshot.sh" \
    "$container" "$DIGIY_EXPECTED_RESTO_COUNTS" "$tmpdir" ||
    fail "RESTO_ISOLATED_RESTORE_PROOF_FAILED"
fi
# Optional V9 pilot proof, only with explicit operator-supplied archived
# aggregate values. Never assume V9 exists in old snapshots or claim it
# survived secure restoration just because SQL succeeded.
if [[ -n "${DIGIY_EXPECTED_RESA_V9_COUNTS:-}" ]]; then
  [[ "$resa_v9_acl_snapshot" == YES ]] || fail "ISOLATED_RESA_V9_ACL_SNAPSHOT_REQUIRED_NEW_BACKUP"
  [[ -f "$script_dir/verify-resa-v9-restored-snapshot.sh" ]] ||
    fail "RESA_V9_ISOLATED_PROOF_SCRIPT_MISSING"
  bash "$script_dir/verify-resa-v9-restored-snapshot.sh" \
    "$container" "$DIGIY_EXPECTED_RESA_V9_COUNTS" "$tmpdir" ||
    fail "RESA_V9_ISOLATED_RESTORE_PROOF_FAILED"
fi
echo "ISOLATED_RESTORE_PRODUCTION_UNTOUCHED: aucune cible distante accessible depuis le conteneur."
