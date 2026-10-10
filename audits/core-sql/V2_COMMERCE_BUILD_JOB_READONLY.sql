-- DIGIY CORE V2 — COMMERCE / BUILD / JOB preflight, 100% READ ONLY.
-- No PII, no CV, no order line items, no mutations.
-- Do not infer same professional from matching slugs or phone numbers.

SELECT 'commerce_sites' AS object,count(*)::bigint AS total FROM public.digiy_commerce_sites
UNION ALL SELECT 'commerce_products',count(*) FROM public.digiy_commerce_products
UNION ALL SELECT 'commerce_orders',count(*) FROM public.digiy_commerce_orders
UNION ALL SELECT 'build_artisans_legacy',count(*) FROM public.digiy_build_artisans
UNION ALL SELECT 'build_pros_modern',count(*) FROM public.digiy_build_pros
UNION ALL SELECT 'build_requests',count(*) FROM public.digiy_build_requests
UNION ALL SELECT 'build_jobs',count(*) FROM public.digiy_build_jobs
UNION ALL SELECT 'job_owner_workspaces',count(*) FROM public.digiy_jobs_owner_workspaces
UNION ALL SELECT 'job_offers',count(*) FROM public.digiy_jobs_offers_pro
UNION ALL SELECT 'job_missions',count(*) FROM public.digiy_jobs_missions_pro;

SELECT 'commerce_products_without_site' AS check_name,count(*)::bigint AS total
FROM public.digiy_commerce_products p
LEFT JOIN public.digiy_commerce_sites s ON s.slug=p.site_slug WHERE s.id IS NULL
UNION ALL SELECT 'commerce_orders_without_site',count(*)
FROM public.digiy_commerce_orders o
LEFT JOIN public.digiy_commerce_sites s ON s.slug=o.site_slug WHERE s.id IS NULL
UNION ALL SELECT 'job_offers_without_current_workspace',count(*)
FROM public.digiy_jobs_offers_pro o
LEFT JOIN public.digiy_jobs_owner_workspaces w ON w.workspace_slug=o.workspace_slug
WHERE w.workspace_slug IS NULL
UNION ALL SELECT 'legacy_build_artisans_owner_id_uuid_like',count(*)
FROM public.digiy_build_artisans a WHERE a.owner_id
 ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

SELECT c.oid::regclass::text AS object,c.relrowsecurity AS rls_enabled,
 c.relforcerowsecurity AS force_rls,
 has_table_privilege('anon',c.oid,'SELECT') AS anon_select,
 has_table_privilege('authenticated',c.oid,'UPDATE') AS authenticated_update
FROM pg_class c
WHERE c.oid IN (
 'public.digiy_commerce_sites'::regclass,
 'public.digiy_commerce_products'::regclass,
 'public.digiy_commerce_orders'::regclass,
 'public.digiy_build_artisans'::regclass,
 'public.digiy_build_pros'::regclass,
 'public.digiy_jobs_owner_workspaces'::regclass,
 'public.digiy_jobs_offers_pro'::regclass
) ORDER BY 1;

SELECT schemaname,tablename,policyname,permissive,roles::text AS roles,cmd
FROM pg_policies
WHERE schemaname='public' AND tablename IN (
'digiy_commerce_sites','digiy_commerce_products','digiy_commerce_orders',
'digiy_build_artisans','digiy_build_pros','digiy_build_requests',
'digiy_jobs_owner_workspaces','digiy_jobs_offers_pro'
) ORDER BY tablename,policyname;
