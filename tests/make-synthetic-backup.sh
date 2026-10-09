#!/usr/bin/env bash
# Test fixture only: synthetic 81 calendar rows; zero DIGIY CORE data/secrets.
set -Eeuo pipefail
umask 077
[[ -n "${RUNNER_TEMP:-}" ]] || { echo "SYNTHETIC_RUNNER_TEMP_MISSING" >&2; exit 78; }
[[ "${BACKUP_PASSPHRASE:-}" == "synthetic-ci-only-not-a-real-secret" ]] || {
  echo "SYNTHETIC_PASSPHRASE_MISMATCH" >&2; exit 78;
}
source_dir="$RUNNER_TEMP/synthetic-artifact"
workspace="$(mktemp -d "$RUNNER_TEMP/fixture.XXXXXXXX")"
trap 'rm -rf -- "$workspace"' EXIT
fixture="$workspace/digiy-supabase-2026-10-09T00-00-00Z"
mkdir -p "$fixture" "$source_dir"

cat > "$fixture/roles.sql" <<'SQL'
CREATE ROLE digiy_synthetic_restore_fixture NOLOGIN;
SQL
cat > "$fixture/schema.sql" <<'SQL'
CREATE TABLE public.digiy_loc_master_unit_calendar (
  id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  status text NOT NULL CHECK (status IN ('occupied', 'closed'))
);
CREATE TABLE public.digiy_loc_master_reservations (
  id uuid PRIMARY KEY
);
CREATE FUNCTION public.digiy_loc_master_save_reservation_v1()
RETURNS integer LANGUAGE SQL AS 'SELECT 1';
-- This intentionally requires Supabase Auth's standard helper while parsing schema.
-- Without the isolated auth.jwt() bootstrap, PostgreSQL returns SQLSTATE 42883.
CREATE TABLE public.digiy_synthetic_auth_jwt_probe (
  id integer PRIMARY KEY,
  jwt_subject text DEFAULT (auth.jwt() ->> 'sub')
);
SQL
{
  printf 'COPY public.digiy_loc_master_unit_calendar (status) FROM stdin;\n'
  for i in $(seq 1 81); do
    if (( i % 2 == 0 )); then printf 'closed\n'; else printf 'occupied\n'; fi
  done
  printf '\\.\n'
} > "$fixture/data.sql"
# All values below are SYNTHETIC. This COPY fails if the local Auth image
# lacks its newer audit ip_address column; it must never be silently skipped.
cat >> "$fixture/data.sql" <<'SQL'
COPY auth.audit_log_entries (id, ip_address) FROM stdin;
00000000-0000-0000-0000-000000000001	192.0.2.25
\.
SQL
printf 'storage_backup=metadata_only\nmigration_history=absent\n' > "$fixture/backup-status.txt"
printf 'Synthetic CI fixture only; NOT from DIGIY CORE.\n' > "$fixture/README.txt"
(
  cd "$fixture"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)
archive="$source_dir/digiy-supabase-2026-10-09T00-00-00Z.tar.gz.enc"
tar -C "$workspace" -czf "$workspace/fixture.tar.gz" "$(basename "$fixture")"
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 250000 \
  -in "$workspace/fixture.tar.gz" -out "$archive" -pass env:BACKUP_PASSPHRASE
# Mirror the real backup workflow, which writes an ABSOLUTE runner path in
# the external SHA256 sidecar. The restore verifier must never follow it.
sha256sum "$archive" > "$archive.sha256"
echo "SYNTHETIC_ARCHIVE_READY: uniquement fausses données."
