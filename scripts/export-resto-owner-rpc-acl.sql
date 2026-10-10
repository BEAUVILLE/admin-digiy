-- Export ONLY the three audited RESTO owner RPC execution ACLs.
-- Read-only catalog export: stdout becomes encrypted archive member.
-- Schema/permissions drift is FATAL; no client rows or credentials.
BEGIN TRANSACTION READ ONLY;
DO $guard$
DECLARE v_count integer; v_bad integer;
BEGIN
 SELECT count(*),
        count(*) FILTER (
          WHERE p.prosecdef IS DISTINCT FROM true
             OR has_function_privilege('anon',p.oid,'EXECUTE')
             OR NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
             OR NOT has_function_privilege('service_role',p.oid,'EXECUTE')
        )
 INTO v_count,v_bad
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND
 (p.proname,pg_get_function_identity_arguments(p.oid)) IN (
  ('digiy_resa_resto_claim_site_by_email_v1','p_slug text'),
  ('digiy_resa_resto_owner_refresh_no_shows_v1','p_site_id uuid'),
  ('digiy_resa_resto_owner_set_booking_status_v1','p_booking_id uuid, p_status text')
 );
 IF v_count<>3 OR v_bad<>0 THEN
  RAISE EXCEPTION 'RESTO_OWNER_RPC_ACL_SOURCE_DRIFT';
 END IF;
END $guard$;
-- An explicit post-restore REVOKE is required: default PUBLIC execute may
-- otherwise be inherited even if the source database revoked it.
SELECT '-- RESTO owner RPC execution ACL snapshot; generated from verified live catalog'
UNION ALL
SELECT format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon, authenticated, service_role;%sGRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated, service_role;',
 p.proname,pg_get_function_identity_arguments(p.oid),E'\n',
 p.proname,pg_get_function_identity_arguments(p.oid))
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND
(p.proname,pg_get_function_identity_arguments(p.oid)) IN (
 ('digiy_resa_resto_claim_site_by_email_v1','p_slug text'),
 ('digiy_resa_resto_owner_refresh_no_shows_v1','p_site_id uuid'),
 ('digiy_resa_resto_owner_set_booking_status_v1','p_booking_id uuid, p_status text')
)
ORDER BY 1;
COMMIT;
