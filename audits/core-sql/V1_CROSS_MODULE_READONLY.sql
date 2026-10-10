-- DIGIY CORE V1 — cross-module SQL audit, READ ONLY.
-- Never use this file as a migration; it contains SELECT statements only.
-- Run with an authorized audit connection. No customer PII returned.
-- Project: digiy-core. Recorded baseline 2026-10-10 UTC.

-- 1. Inventory by module; counts include historical/legacy rows.
SELECT 'explore_places' AS object, count(*)::bigint AS total FROM public.digiy_explore_places
UNION ALL SELECT 'explore_calendar', count(*) FROM public.digiy_explore_calendar
UNION ALL SELECT 'resa_profiles', count(*) FROM public.digiy_resa_profiles
UNION ALL SELECT 'resa_services', count(*) FROM public.digiy_resa_services
UNION ALL SELECT 'resa_slots', count(*) FROM public.digiy_resa_slots
UNION ALL SELECT 'resa_bookings', count(*) FROM public.digiy_resa_bookings
UNION ALL SELECT 'resa_pilot_controls', count(*) FROM public.digiy_resa_universal_launch_controls
UNION ALL SELECT 'loc_private_trust_feedback', count(*) FROM digiy_trust_private.voluntary_feedback;

-- 2. Classify old and new records. A historical record is NOT automatically corrupt.
SELECT 'resa_services_without_current_profile' AS check_name, count(*)::bigint AS affected
FROM public.digiy_resa_services s LEFT JOIN public.digiy_resa_profiles p ON p.slug=s.slug
WHERE p.slug IS NULL
UNION ALL SELECT 'resa_bookings_without_current_profile', count(*)
FROM public.digiy_resa_bookings b LEFT JOIN public.digiy_resa_profiles p ON p.slug=b.slug
WHERE p.slug IS NULL
UNION ALL SELECT 'bookings_without_matching_current_service', count(*)
FROM public.digiy_resa_bookings b LEFT JOIN public.digiy_resa_services s ON s.id=b.service_id
WHERE b.service_id IS NOT NULL AND (s.id IS NULL OR s.slug<>b.slug)
UNION ALL SELECT 'explore_resa_auth_owner_mismatch', count(*)
FROM public.digiy_resa_profiles p JOIN public.digiy_explore_places e ON p.slug=e.slug
WHERE p.auth_user_id IS NOT NULL AND e.auth_user_id IS NOT NULL
  AND p.auth_user_id<>e.auth_user_id
UNION ALL SELECT 'resa_slots_without_profile', count(*)
FROM public.digiy_resa_slots s LEFT JOIN public.digiy_resa_profiles p ON p.slug=s.slug
WHERE p.slug IS NULL
UNION ALL SELECT 'active_services_on_unpublished_profile', count(*)
FROM public.digiy_resa_services s JOIN public.digiy_resa_profiles p ON p.slug=s.slug
WHERE s.is_active IS TRUE AND p.is_published IS NOT TRUE
UNION ALL SELECT 'active_historical_services_without_modern_profile', count(*)
FROM public.digiy_resa_services s LEFT JOIN public.digiy_resa_profiles p ON p.slug=s.slug
WHERE s.is_active IS TRUE AND p.slug IS NULL;

-- 3. Safe RÉSA V9 classification: legacy request IDs are NULL by design.
SELECT count(*)::bigint AS total_bookings,
       count(*) FILTER (WHERE client_request_id IS NULL) AS historical_bookings,
       count(*) FILTER (WHERE client_request_id IS NOT NULL) AS universal_bookings
FROM public.digiy_resa_bookings;

-- 4. Target pilot: identity correspondence, safe gate and no invented booking.
SELECT e.slug, (e.auth_user_id=p.auth_user_id AND p.auth_user_id IS NOT NULL) AS same_auth_owner,
       e.is_published AS explore_published, p.is_published AS resa_published,
       coalesce(g.enabled,false) AS pilot_enabled,
       (SELECT count(*) FROM public.digiy_resa_services s WHERE s.slug=e.slug) AS services,
       (SELECT count(*) FROM public.digiy_resa_slots sl WHERE sl.slug=e.slug) AS slots,
       (SELECT count(*) FROM public.digiy_resa_bookings b WHERE b.slug=e.slug) AS bookings
FROM public.digiy_explore_places e
JOIN public.digiy_resa_profiles p ON p.slug=e.slug
LEFT JOIN public.digiy_resa_universal_launch_controls g ON g.slug=p.slug
WHERE e.slug='sortie-peche-jb-baptiste-760a00ad';

-- 5. Physical FKs: a missing FK in legacy data needs impact analysis, not automatic DDL.
SELECT co.conrelid::regclass::text AS source_table, co.conname,
       pg_get_constraintdef(co.oid,true) AS definition
FROM pg_constraint co
WHERE co.contype='f'
  AND co.conrelid IN (
    'public.digiy_explore_calendar'::regclass,
    'public.digiy_resa_services'::regclass,
    'public.digiy_resa_slots'::regclass,
    'public.digiy_resa_bookings'::regclass,
    'digiy_trust_private.voluntary_feedback'::regclass)
ORDER BY source_table,co.conname;

-- 6. Private LOC TRUST storage: no grant implied by the existence of a table.
SELECT c.relrowsecurity AS rls_enabled,c.relforcerowsecurity AS force_rls,
       (SELECT count(*) FROM pg_policies WHERE schemaname='digiy_trust_private'
        AND tablename='voluntary_feedback') AS policy_count,
       to_regrole('digiy_trust_server') IS NOT NULL AS server_role_exists
FROM pg_class c WHERE c.oid='digiy_trust_private.voluntary_feedback'::regclass;

-- 7. Check public-data gate; this read-only function does not authorize publication.
SELECT public.digiy_resa_universal_pilot_gate_v1('sortie-peche-jb-baptiste-760a00ad')
  AS current_pilot_gate;
