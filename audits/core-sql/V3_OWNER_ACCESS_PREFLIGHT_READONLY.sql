-- DIGIY CORE V3 · Accessibilité réelle propriétaire (COMMERCE / BUILD / JOBS)
-- Lecture seule. Ne retourne ni email, numéro, UUID propriétaire ni dossier client.
-- Fiches publiques ≠ comptes authentifiés. Ne pas rattacher par nom, téléphone ou slug.
-- Exécuter avec un rôle d'audit autorisé à lire auth.users ; ne pas exposer au navigateur.

WITH owner_rows AS (
  SELECT 'COMMERCE'::text AS module, s.slug, s.is_active, s.is_published,
         s.auth_user_id AS owner_uid, (u.id IS NOT NULL) AS auth_exists,
         (u.email_confirmed_at IS NOT NULL) AS email_confirmed
  FROM public.digiy_commerce_sites s
  LEFT JOIN auth.users u ON u.id=s.auth_user_id
  UNION ALL
  SELECT 'BUILD', p.slug, p.is_active, p.is_published,
         p.owner_id, (u.id IS NOT NULL), (u.email_confirmed_at IS NOT NULL)
  FROM public.digiy_build_public_profiles p
  LEFT JOIN auth.users u ON u.id=p.owner_id
  UNION ALL
  SELECT 'JOBS', w.workspace_slug, w.is_active, false,
         w.auth_user_id, (u.id IS NOT NULL), (u.email_confirmed_at IS NOT NULL)
  FROM public.digiy_jobs_owner_workspaces w
  LEFT JOIN auth.users u ON u.id=w.auth_user_id
)
SELECT module,
       count(*) AS total,
       count(*) FILTER (WHERE owner_uid IS NULL) AS owner_non_attribue,
       count(*) FILTER (WHERE owner_uid IS NOT NULL AND NOT auth_exists) AS owner_auth_absent,
       count(*) FILTER (WHERE auth_exists AND NOT email_confirmed) AS email_non_confirme,
       count(*) FILTER (WHERE is_active AND is_published) AS fiches_publiques,
       count(*) FILTER (WHERE is_active AND is_published AND (owner_uid IS NULL OR NOT auth_exists)) AS fiches_publiques_sans_acces_pro,
       count(*) FILTER (WHERE is_active AND auth_exists AND email_confirmed) AS espaces_actifs_avec_compte_auth
FROM owner_rows
GROUP BY module
ORDER BY module;

-- Slugs publics uniquement : liste des BUILD à réconcilier humainement.
SELECT p.slug,
       p.is_active,
       p.is_published,
       CASE
         WHEN p.owner_id IS NULL THEN 'ATTRIBUTION_MANQUANTE'
         WHEN u.id IS NULL THEN 'ANCIEN_IDENTIFIANT_SANS_AUTH'
         WHEN u.email_confirmed_at IS NULL THEN 'AUTH_EMAIL_NON_CONFIRME'
         ELSE 'AUTH_OK'
       END AS statut_acces
FROM public.digiy_build_public_profiles p
LEFT JOIN auth.users u ON u.id=p.owner_id
ORDER BY
  CASE WHEN p.is_active AND p.is_published THEN 0 ELSE 1 END,
  p.slug;

-- Integrity: a future owner must not be provisioned by matching names or telephone.
SELECT c.conrelid::regclass::text AS module_table,
       c.conname AS constraint_name,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
WHERE c.conrelid IN (
 'public.digiy_commerce_sites'::regclass,
 'public.digiy_build_public_profiles'::regclass,
 'public.digiy_jobs_owner_workspaces'::regclass
) AND c.contype IN ('p','u','f')
ORDER BY 1,2;

-- Published data is not private owner data: inspect effective access-control contracts.
SELECT c.oid::regclass::text AS module_table,
       c.relrowsecurity AS rls_active,
       has_table_privilege('anon',c.oid,'UPDATE') AS anon_update,
       has_table_privilege('authenticated',c.oid,'UPDATE') AS authenticated_update
FROM pg_class c
WHERE c.oid IN (
 'public.digiy_commerce_sites'::regclass,
 'public.digiy_build_public_profiles'::regclass,
 'public.digiy_jobs_owner_workspaces'::regclass,
 'public.digiy_jobs_candidates_pro'::regclass,
 'public.digiy_build_demandes'::regclass
)
ORDER BY 1;
