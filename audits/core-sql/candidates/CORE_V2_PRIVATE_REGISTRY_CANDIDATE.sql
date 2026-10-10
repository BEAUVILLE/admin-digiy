-- DIGIY CORE V2 — PRIVATE IDENTITY REGISTRY, FAIL-CLOSED CANDIDATE.
-- No module data copy, no implicit slug mapping, no public RPC, no backfill.
-- Apply only after CI + verified backup + audit approval. DB changes = two
-- new EMPTY tables in a new private schema. Existing schema/rows untouched.
BEGIN;
DO $preflight$
BEGIN
 IF to_regnamespace('digiy_core_private') IS NOT NULL THEN
  RAISE EXCEPTION 'CORE_V2_SCHEMA_EXISTS_REVIEW_BEFORE_APPLY';
 END IF;
 IF to_regclass('public.digiy_explore_places') IS NULL
    OR to_regclass('public.digiy_resa_profiles') IS NULL
    OR to_regclass('public.digiy_commerce_sites') IS NULL
    OR to_regclass('public.digiy_build_pros') IS NULL
    OR to_regclass('public.digiy_jobs_owner_workspaces') IS NULL
 THEN
  RAISE EXCEPTION 'CORE_V2_REQUIRED_MODULE_TABLES_MISSING';
 END IF;
END $preflight$;
CREATE SCHEMA digiy_core_private;
REVOKE ALL ON SCHEMA digiy_core_private FROM PUBLIC;
CREATE TABLE digiy_core_private.professionals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 lifecycle text NOT NULL DEFAULT 'pending'
  CONSTRAINT core_professionals_lifecycle_check CHECK(lifecycle IN ('pending','active','disabled')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE digiy_core_private.module_links (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 professional_id uuid NOT NULL REFERENCES digiy_core_private.professionals(id) ON DELETE RESTRICT,
 module text NOT NULL CONSTRAINT core_module_name_check
  CHECK(module IN ('EXPLORE','RESA','LOC','RESTO','DRIVER','COMMERCE','BUILD','JOB')),
 source_key text NOT NULL CONSTRAINT core_source_key_valid_check
  CHECK (length(source_key) BETWEEN 2 AND 160 AND source_key ~ '^[a-zA-Z0-9][a-zA-Z0-9_-]*$'),
 observed_owner_uid uuid,
 verification_status text NOT NULL DEFAULT 'pending'
  CONSTRAINT core_module_link_verification_check CHECK(verification_status IN ('pending','verified','rejected')),
 verified_at timestamptz,
 verified_by uuid,
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT core_module_unique_source UNIQUE (module,source_key),
 CONSTRAINT core_verified_requires_evidence CHECK (
   verification_status <> 'verified'
   OR (observed_owner_uid IS NOT NULL AND verified_at IS NOT NULL AND verified_by IS NOT NULL)
 ),
 CONSTRAINT core_no_unverified_proof CHECK (
   (verification_status='verified') = (verified_at IS NOT NULL)
 ),
 CONSTRAINT core_no_unverified_reviewer CHECK (
   (verification_status='verified') = (verified_by IS NOT NULL)
 )
);
CREATE INDEX core_module_links_professional_idx ON digiy_core_private.module_links(professional_id);
ALTER TABLE digiy_core_private.professionals ENABLE ROW LEVEL SECURITY;
ALTER TABLE digiy_core_private.module_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE digiy_core_private.professionals FORCE ROW LEVEL SECURITY;
ALTER TABLE digiy_core_private.module_links FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA digiy_core_private FROM PUBLIC;
DO $postflight$
DECLARE v_role text;
BEGIN
 IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='digiy_core_private') THEN
  RAISE EXCEPTION 'CORE_V2_PRIVATE_POLICY_DRIFT';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='digiy_core_private' AND c.relkind='r'
    AND (c.relrowsecurity IS NOT TRUE OR c.relforcerowsecurity IS NOT TRUE)) THEN
  RAISE EXCEPTION 'CORE_V2_PRIVATE_RLS_MISSING';
 END IF;
 FOREACH v_role IN ARRAY ARRAY['anon','authenticated','authenticator','service_role'] LOOP
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
   IF has_schema_privilege(v_role,'digiy_core_private','USAGE') OR
      has_table_privilege(v_role,'digiy_core_private.professionals','SELECT,INSERT,UPDATE,DELETE') OR
      has_table_privilege(v_role,'digiy_core_private.module_links','SELECT,INSERT,UPDATE,DELETE')
   THEN
    RAISE EXCEPTION 'CORE_V2_PUBLIC_OR_API_GRANT_DRIFT: %',v_role;
   END IF;
  END IF;
 END LOOP;
END $postflight$;
COMMIT;
