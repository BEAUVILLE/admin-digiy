-- P0 HOLD: APPLY ONLY AFTER patched backend has been deployed and verified.
-- Do not run while /api/admin/login still calls admin_login using the anon key.
-- Expected source: BEAUVILLE/admin-digiy backend · TS, service_role call.
-- Existing admin PIN and admin_login function body are left untouched.
BEGIN;
REVOKE EXECUTE ON FUNCTION public.admin_login(text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_login(text, text, text)
  TO service_role;
COMMIT;
-- Post-check (read-only):
-- SELECT has_function_privilege('anon', 'public.admin_login(text,text,text)', 'EXECUTE') AS anon_exec,
--        has_function_privilege('authenticated', 'public.admin_login(text,text,text)', 'EXECUTE') AS auth_exec,
--        has_function_privilege('service_role', 'public.admin_login(text,text,text)', 'EXECUTE') AS service_exec;
-- Expected: false / false / true.
-- Emergency rollback ONLY IF VERIFIED NECESSARY: GRANT EXECUTE ON FUNCTION public.admin_login(text,text,text) TO anon;
