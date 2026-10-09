-- LOCAL DISPOSABLE RESTORE ONLY. Never deploy this SQL to Supabase production.
-- DIGIY CORE source catalogue verified (2026-10-09), read-only:
-- auth.audit_log_entries.ip_address: varchar(64) NOT NULL DEFAULT ''.
-- Never skip or alter rows from the encrypted backup's data.sql.
ALTER TABLE auth.audit_log_entries
  ADD COLUMN IF NOT EXISTS ip_address varchar(64) NOT NULL DEFAULT '';

DO $digiy_audit_check$
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
        format('%L::character varying', ''),
        format('%L::character varying(64)', '')
      )
  ) THEN
    RAISE EXCEPTION 'DIGIY_LOCAL_AUTH_AUDIT_COLUMN_CONTRACT_MISMATCH';
  END IF;
END;
$digiy_audit_check$;
