-- DIGIY CORE isolated restore only. Never deploy this file to Supabase production.
-- This reproduces only the official Supabase Auth auth.jwt() helper when absent.
-- Source: supabase/auth migrations/20220531120530_add_auth_jwt_function.up.sql
-- Runs inside the disposable --network none container, before schema.sql.
CREATE SCHEMA IF NOT EXISTS auth;

DO $digiy_local_restore$
BEGIN
  IF to_regprocedure('auth.jwt()') IS NULL THEN
    EXECUTE $function$
      CREATE FUNCTION auth.jwt()
      RETURNS jsonb
      LANGUAGE sql STABLE
      AS $auth_body$
        SELECT COALESCE(
          NULLIF(current_setting('request.jwt.claim', true), ''),
          NULLIF(current_setting('request.jwt.claims', true), '')
        )::jsonb
      $auth_body$;
    $function$;
  END IF;

  IF (
    SELECT pg_get_function_result(p.oid) <> 'jsonb'
        OR p.provolatile <> 's'
        OR p.prosecdef
    FROM pg_proc p
    WHERE p.oid = to_regprocedure('auth.jwt()')
  ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'DIGIY_LOCAL_AUTH_JWT_CONTRACT_MISMATCH';
  END IF;
END
$digiy_local_restore$;
