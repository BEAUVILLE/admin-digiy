-- LOCAL DISPOSABLE RESTORE ONLY. Do not deploy to Supabase production.
-- Read-only source catalogue check (DIGIY CORE 2026-10-09):
-- auth.audit_log_entries.ip_address = varchar(64) NOT NULL DEFAULT ''.
-- The pinned Docker image lacks this newer Auth column. Preserve every COPY.
-- Executed as supabase_admin inside --network none, never with remote DB URLs.
ALTER TABLE auth.audit_log_entries
  ADD COLUMN IF NOT EXISTS ip_address varchar(64) NOT NULL DEFAULT '';

DO $digiy_auth_audit_contract$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
     WHERE n.nspname = 'auth'
       AND c.relname = 'audit_log_entries'
       AND a.attname = 'ip_address'
       AND a.attnum > 0
       AND NOT a.attisdropped
       AND a.atttypid = 'pg_catalog.varchar'::regtype
       AND a.atttypmod = 68
       AND a.attnotnull
       AND pg_get_expr(d.adbin, d.adrelid) IN (
         ''''::character varying',
         ''''::character varying(64)'
       )
  ) THEN
    RAISE EXCEPTION 'DIGIY_LOCAL_AUTH_AUDIT_COLUMN_CONTRACT_MISMATCH';
  END IF;
END
$digiy_auth_audit_contract$;
