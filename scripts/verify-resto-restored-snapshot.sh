#!/usr/bin/env bash
# DIGIY RESTO — aggregate, read-only proof against an ALREADY restored
# ephemeral/no-network PostgreSQL Docker container.
# Never accepts a DB URL, password, service key, or production target.
# Compatible with the Mac's Bash 3.2.
set -Eeuo pipefail
set +x
umask 077

refuse() { printf 'RESTO_ISOLATED_PROOF_REFUSED: %s\n' "$1" >&2; exit 78; }
[[ "$#" -eq 3 ]] || refuse "EXPECTED_CONTAINER_BASELINE_PRIVATE_LOGDIR"
container="$1"
expected="$2"
private_dir="$3"
[[ -n "$container" && "$container" =~ ^digiy-restore-[a-zA-Z0-9_-]+$ ]] ||
  refuse "ISOLATED_CONTAINER_NAME_INVALID"
[[ -d "$private_dir" && ! -L "$private_dir" ]] ||
  refuse "PRIVATE_LOG_DIR_INVALID"
command -v docker >/dev/null 2>&1 || refuse "DOCKER_REQUIRED"
# No ranges, commands or user-supplied SQL are ever interpolated into the query.
# The baseline MUST come from a separate, live READ-ONLY observation of the
# same snapshot. For 2026-10-09T09:13:01Z it is 4|2|2|7|10|8|0|0|2.
case "$expected" in
  *[!0-9\|]*|'') refuse "EXPECTED_AGGREGATES_INVALID" ;;
esac
IFS='|' read -r es ea eo ez et ew eb el eold extra <<< "$expected"
[[ -n "$es" && -n "$ea" && -n "$eo" && -n "$ez" &&
   -n "$et" && -n "$ew" && -n "$eb" && -n "$el" &&
   -n "$eold" && -z "${extra:-}" &&
   "$expected" == "$es|$ea|$eo|$ez|$et|$ew|$eb|$el|$eold" ]] ||
  refuse "EXPECTED_AGGREGATES_FORMAT_INVALID"

sql="SELECT concat_ws('|',
 (SELECT count(*) FROM public.digiy_resa_resto_sites),
 (SELECT count(*) FROM public.digiy_resa_resto_sites WHERE is_active IS TRUE),
 (SELECT count(*) FROM public.digiy_resa_resto_sites WHERE owner_id IS NOT NULL),
 (SELECT count(*) FROM public.digiy_resa_resto_zones),
 (SELECT count(*) FROM public.digiy_resa_resto_tables),
 (SELECT count(*) FROM public.digiy_resa_resto_service_windows),
 (SELECT count(*) FROM public.digiy_resa_resto_bookings),
 (SELECT count(*) FROM public.digiy_resa_resto_booking_tables),
 (SELECT count(*) FROM public.resa_resto_reservations),
 (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname IN
    ('digiy_resa_resto_sites','digiy_resa_resto_zones',
     'digiy_resa_resto_tables','digiy_resa_resto_service_windows',
     'digiy_resa_resto_bookings','digiy_resa_resto_booking_tables')
     AND c.relrowsecurity IS TRUE),
 (
 (to_regprocedure('public.digiy_resa_resto_claim_site_by_email_v1(text)')
     IS NOT NULL)::int +
 (to_regprocedure('public.digiy_resa_resto_owner_refresh_no_shows_v1(uuid)')
     IS NOT NULL)::int +
 (to_regprocedure('public.digiy_resa_resto_owner_set_booking_status_v1(uuid,text)')
     IS NOT NULL)::int +
 (to_regprocedure('public.digiy_resa_resto_public_book_v1(text,date,time,integer,text,text,text)')
     IS NOT NULL)::int +
 (to_regprocedure('public.digiy_resa_resto_public_availability_v1(text,date,integer,text)')
     IS NOT NULL)::int
 ),
 (
 (has_function_privilege('anon',to_regprocedure(
    'public.digiy_resa_resto_public_book_v1(text,date,time,integer,text,text,text)'),'EXECUTE') IS TRUE)::int +
 (has_function_privilege('anon',to_regprocedure(
    'public.digiy_resa_resto_public_availability_v1(text,date,integer,text)'),'EXECUTE') IS TRUE)::int
 ),
 (
 (SELECT count(*) FROM public.digiy_resa_resto_zones z
  LEFT JOIN public.digiy_resa_resto_sites s ON s.id=z.site_id WHERE s.id IS NULL)+
 (SELECT count(*) FROM public.digiy_resa_resto_tables t
  LEFT JOIN public.digiy_resa_resto_zones z ON z.id=t.zone_id WHERE z.id IS NULL)+
 (SELECT count(*) FROM public.digiy_resa_resto_service_windows w
  LEFT JOIN public.digiy_resa_resto_sites s ON s.id=w.site_id WHERE s.id IS NULL)+
 (SELECT count(*) FROM public.digiy_resa_resto_bookings b
  LEFT JOIN public.digiy_resa_resto_sites s ON s.id=b.site_id WHERE s.id IS NULL)+
 (SELECT count(*) FROM public.digiy_resa_resto_booking_tables x
  LEFT JOIN public.digiy_resa_resto_bookings b ON b.id=x.booking_id
  WHERE b.id IS NULL)+
 (SELECT count(*) FROM public.digiy_resa_resto_booking_tables x
  LEFT JOIN public.digiy_resa_resto_tables t ON t.id=x.table_id
  WHERE t.id IS NULL)
 ),
 (
 (has_function_privilege('anon',to_regprocedure(
    'public.digiy_resa_resto_claim_site_by_email_v1(text)'),'EXECUTE') IS TRUE)::int +
 (has_function_privilege('anon',to_regprocedure(
    'public.digiy_resa_resto_owner_refresh_no_shows_v1(uuid)'),'EXECUTE') IS TRUE)::int +
 (has_function_privilege('anon',to_regprocedure(
    'public.digiy_resa_resto_owner_set_booking_status_v1(uuid,text)'),'EXECUTE') IS TRUE)::int
 ));"

result="$(docker exec "$container" psql -U postgres -d postgres -X -w -Atq \
 -v ON_ERROR_STOP=1 -c "$sql" \
 2>"$private_dir/resto-proof-private.log")" || refuse "READ_ONLY_SQL_FAILED"
[[ "$result" =~ ^[0-9|]+$ ]] || refuse "AGGREGATE_OUTPUT_INVALID"
IFS='|' read -r sites active owners zones tables windows bookings links legacy rls rpc public orphan owner_anon extra <<< "$result"
[[ -z "${extra:-}" && -n "$owner_anon" ]] || refuse "AGGREGATE_OUTPUT_SHAPE_INVALID"
observed="$sites|$active|$owners|$zones|$tables|$windows|$bookings|$links|$legacy"
if [[ "$observed" != "$expected" ]]; then
 printf 'RESTO_ISOLATED_PROOF_COUNTS_MISMATCH: observed=%s expected=%s\n' "$observed" "$expected" >&2
 refuse "ARCHIVE_DATA_BASELINE_MISMATCH"
fi
[[ "$rls" == 6 ]] || refuse "RLS_INCOMPLETE"
[[ "$rpc" == 5 ]] || refuse "RESTAURANT_RPC_MISSING"
[[ "$public" == 2 ]] || refuse "PUBLIC_BOOKING_RPC_UNAVAILABLE"
[[ "$orphan" == 0 ]] || refuse "BROKEN_RESTAURANT_REFERENCES"
[[ "$owner_anon" =~ ^[0-3]$ ]] || refuse "OWNER_ACL_COUNTER_INVALID"
printf 'RESTO_ISOLATED_RESTORE_PROOF_OK: sites=%s active=%s owner_bound=%s zones=%s tables=%s windows=%s bookings=%s links=%s legacy=%s\n' \
 "$sites" "$active" "$owners" "$zones" "$tables" "$windows" "$bookings" "$links" "$legacy"
printf 'RESTO_ISOLATED_RLS_OK: 6/6; RESTO_ISOLATED_RPC_OK: 5/5; RESTO_ISOLATED_PUBLIC_RPC_OK: 2/2; RESTO_ISOLATED_ORPHANS_OK: 0\n'
printf 'RESTO_ARCHIVED_OWNER_RPC_ANON_EXECUTE: %s/3 (historical snapshot only; re-audit live grants)\n' "$owner_anon"
