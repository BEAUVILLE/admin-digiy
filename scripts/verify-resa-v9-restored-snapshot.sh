#!/usr/bin/env bash
# RÉSA UNIVERSAL V9: opt-in aggregate validation of an *offline* restored dump.
# Called only by restore-supabase-github-isolated.sh AFTER network-isolated SQL restore.
# No client rows, Auth JWT, personal information, cloud URL or credentials printed.
set -Eeuo pipefail
set +x
umask 077
fail() { echo "RESA_V9_ISOLATED_PROOF_REFUSED: $1" >&2; exit 78; }
[[ "$#" == 3 ]] || fail "ARGUMENTS"
container="$1"
expected="$2"
log_root="$3"
[[ "$expected" =~ ^[0-9]+(\|[0-9]+){8}$ ]] || fail "EXPECTED_COUNTS_INVALID"
[[ -d "$log_root" && ! -L "$log_root" ]] || fail "PRIVATE_LOG_DIRECTORY_INVALID"
command -v docker >/dev/null 2>&1 || fail "DOCKER_REQUIRED"
# Exact business state of pilot Saly at time of the V9 backup; no synthetic rows.
snapshot="$(docker exec "$container" psql -U postgres -d postgres -X -w -Atq \
  -v ON_ERROR_STOP=1 -c "
SELECT
 (SELECT count(*) FROM public.digiy_resa_bookings WHERE client_request_id IS NULL)::text || '|' ||
 (SELECT count(*) FROM public.digiy_resa_bookings WHERE client_request_id IS NOT NULL)::text || '|' ||
 (SELECT count(*) FROM public.digiy_resa_profiles
     WHERE slug='sortie-peche-jb-baptiste-760a00ad')::text || '|' ||
 (SELECT count(*) FROM public.digiy_resa_universal_launch_controls
     WHERE slug='sortie-peche-jb-baptiste-760a00ad')::text || '|' ||
 (SELECT count(*) FROM public.digiy_resa_universal_launch_controls WHERE enabled)::text || '|' ||
 (SELECT count(*) FROM public.digiy_resa_services
     WHERE slug='sortie-peche-jb-baptiste-760a00ad')::text || '|' ||
 (SELECT count(*) FROM public.digiy_resa_slots
     WHERE slug='sortie-peche-jb-baptiste-760a00ad')::text || '|' ||
 (SELECT count(*) FROM public.digiy_resa_profiles r
      JOIN public.digiy_explore_places e ON e.slug=r.slug
      WHERE r.slug='sortie-peche-jb-baptiste-760a00ad'
        AND r.auth_user_id IS NOT NULL AND r.auth_user_id=e.auth_user_id
        AND r.time_zone='Africa/Dakar'
        AND r.is_active=true AND r.is_published=false)::text || '|' ||
 (SELECT count(*) FROM public.digiy_resa_profiles WHERE is_active AND is_published)::text;
" 2>"$log_root/resa-v9-count-private.log")" || fail "SNAPSHOT_QUERY_FAILED"
if [[ "$snapshot" != "$expected" ]]; then
  if [[ "$snapshot" =~ ^[0-9]+(\|[0-9]+){8}$ ]]; then
    echo "RESA_V9_ISOLATED_SNAPSHOT_MISMATCH: actual=$snapshot expected=$expected" >&2
  fi
  fail "SNAPSHOT_COUNTS_MISMATCH"
fi
echo "RESA_V9_ISOLATED_DATA_OK: historical|new|pilot|gate|enabled|services|slots|owner_link|published=$snapshot."
# A normal schema dump may not preserve revocations of default PUBLIC EXECUTE.
# Therefore a successful SQL restore is *not* evidence of secure RPC grants.
acl="$(docker exec "$container" psql -U postgres -d postgres -X -w -Atq \
  -v ON_ERROR_STOP=1 -c "
SELECT
 has_function_privilege('anon',
   'public.digiy_resa_universal_request_v0(text,uuid,uuid,text,text,uuid)', 'EXECUTE')::text || '|' ||
 has_function_privilege('authenticated',
   'public.digiy_resa_universal_request_v0(text,uuid,uuid,text,text,uuid)', 'EXECUTE')::text || '|' ||
 has_function_privilege('anon',
   'public.digiy_resa_universal_owner_manage_v2(uuid,text,text)', 'EXECUTE')::text || '|' ||
 has_function_privilege('authenticated',
   'public.digiy_resa_universal_owner_manage_v2(uuid,text,text)', 'EXECUTE')::text || '|' ||
 has_function_privilege('anon',
   'public.digiy_resa_universal_pilot_gate_v1(text)', 'EXECUTE')::text || '|' ||
 has_function_privilege('anon',
   'public.digiy_resa_universal_public_options_v1(text,date)', 'EXECUTE')::text || '|' ||
 has_function_privilege('anon',
   'public.digiy_resa_universal_request_v1(text,uuid,uuid,text,text,uuid)', 'EXECUTE')::text || '|' ||
 has_table_privilege('authenticated',
   'public.digiy_resa_universal_launch_controls', 'UPDATE')::text || '|' ||
 EXISTS(SELECT 1 FROM pg_constraint
  WHERE conrelid='public.digiy_resa_bookings'::regclass
    AND conname='digiy_resa_universal_no_overlap_v0')::text || '|' ||
 (position('NEW.client_request_id IS NOT NULL' IN
    pg_get_functiondef('public.trg_digiy_resa_push_to_pay()'::regprocedure))>0)::text || '|' ||
 (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname IN (
     'digiy_resa_universal_request_v0',
     'digiy_resa_universal_request_v1',
     'digiy_resa_universal_owner_manage_v2',
     'digiy_resa_universal_pilot_gate_v1',
     'digiy_resa_universal_public_options_v1'
    ))::text;
" 2>"$log_root/resa-v9-acl-private.log")" || fail "ACL_QUERY_FAILED"
[[ "$acl" == 'false|false|false|true|true|true|true|false|true|true|5' ]] ||
  fail "ACL_NOT_RESTORED_OR_V9_SCHEMA_INCOMPLETE"
echo "RESA_V9_ISOLATED_ACL_OK: anon(V0)=0 anon(V5)=0; public gate/V2/V8 available; historical PAY protected."
echo "RESA_V9_ISOLATED_RESTORE_PROOF_OK: pilot disabled, historical data and targeted permissions restored; not a real Auth owner login."
