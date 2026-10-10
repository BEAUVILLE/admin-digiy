-- RÉSA V9: capture EXPLICIT execution privileges lost by some CLI dumps.
-- Query source catalog READ ONLY; abort on drift. Emits executable SQL
-- for the OFFLINE container only, never applies changes to production.
BEGIN TRANSACTION READ ONLY;
DO $guard$
DECLARE v_count int; v_bad int;
BEGIN
 WITH expect(proname,args,anon_ok,auth_ok) AS (VALUES
 ('digiy_resa_universal_request_v0','p_slug text, p_slot_id uuid, p_service_id uuid, p_client_name text, p_client_phone text, p_request_id uuid',false,false),
 ('digiy_resa_universal_request_v1','p_slug text, p_slot_id uuid, p_service_id uuid, p_client_name text, p_client_phone text, p_request_id uuid',true,true),
 ('digiy_resa_universal_owner_manage_v2','p_booking_id uuid, p_action text, p_note_text text',false,true),
 ('digiy_resa_universal_pilot_gate_v1','p_slug text',true,true),
 ('digiy_resa_universal_public_options_v1','p_slug text, p_start_date date',true,true)
 ), matched AS (
 SELECT e.*,p.oid,p.prosecdef FROM expect e
 LEFT JOIN pg_proc p ON p.proname=e.proname AND pg_get_function_identity_arguments(p.oid)=e.args
  AND p.pronamespace='public'::regnamespace
 )
 SELECT count(*),count(*) FILTER(WHERE oid IS NULL OR prosecdef IS NOT TRUE
    OR has_function_privilege('anon',oid,'EXECUTE') IS DISTINCT FROM anon_ok
    OR has_function_privilege('authenticated',oid,'EXECUTE') IS DISTINCT FROM auth_ok
    OR has_function_privilege('service_role',oid,'EXECUTE') IS NOT TRUE)
 INTO v_count,v_bad FROM matched;
 IF v_count<>5 OR v_bad<>0 THEN RAISE EXCEPTION 'RESA_V9_SOURCE_ACL_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.digiy_resa_universal_launch_controls'::regclass
     AND relrowsecurity=true) THEN RAISE EXCEPTION 'RESA_V9_LAUNCH_RLS_MISSING'; END IF;
 IF (SELECT count(*) FROM pg_policies WHERE schemaname='public'
     AND tablename='digiy_resa_universal_launch_controls')<>0
    OR has_any_column_privilege('anon','public.digiy_resa_universal_launch_controls','UPDATE')
    OR has_any_column_privilege('authenticated','public.digiy_resa_universal_launch_controls','UPDATE')
    OR has_table_privilege('anon','public.digiy_resa_universal_launch_controls','SELECT')
    OR has_table_privilege('authenticated','public.digiy_resa_universal_launch_controls','SELECT')
    OR NOT has_table_privilege('service_role','public.digiy_resa_universal_launch_controls','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
 THEN RAISE EXCEPTION 'RESA_V9_LAUNCH_ACL_DRIFT'; END IF;
END $guard$;
SELECT '-- RÉSA V9: live-validated roles and launch table ACL snapshot'
UNION ALL
SELECT format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon, authenticated, service_role;%sGRANT EXECUTE ON FUNCTION public.%I(%s) TO %s;',
 p.proname,pg_get_function_identity_arguments(p.oid),E'\n',
 p.proname,pg_get_function_identity_arguments(p.oid),
 CASE p.proname
  WHEN 'digiy_resa_universal_request_v0' THEN 'service_role'
  WHEN 'digiy_resa_universal_owner_manage_v2' THEN 'authenticated, service_role'
  ELSE 'anon, authenticated, service_role'
 END)
FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
WHERE n.nspname='public' AND p.proname IN (
 'digiy_resa_universal_request_v0',
 'digiy_resa_universal_request_v1',
 'digiy_resa_universal_owner_manage_v2',
 'digiy_resa_universal_pilot_gate_v1',
 'digiy_resa_universal_public_options_v1')
UNION ALL
SELECT 'REVOKE ALL ON TABLE public.digiy_resa_universal_launch_controls FROM PUBLIC, anon, authenticated, service_role;'
UNION ALL
SELECT 'GRANT ALL ON TABLE public.digiy_resa_universal_launch_controls TO service_role;'
ORDER BY 1;
COMMIT;
