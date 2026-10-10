-- Executed after CORE V2 migration on an isolated PG17 service.
BEGIN;
DO $proof$
DECLARE v_reg oid;
BEGIN
 IF to_regclass('digiy_core_private.professionals') IS NULL
    OR to_regclass('digiy_core_private.module_links') IS NULL
 THEN RAISE EXCEPTION 'REGISTRY_MISSING'; END IF;
 IF (SELECT count(*) FROM digiy_core_private.professionals)<>0 OR
    (SELECT count(*) FROM digiy_core_private.module_links)<>0
 THEN RAISE EXCEPTION 'REGISTRY_HAS_TEST_DATA'; END IF;
 IF (SELECT count(*) FROM pg_policies WHERE schemaname='digiy_core_private')<>0
 THEN RAISE EXCEPTION 'UNEXPECTED_POLICIES'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='digiy_core_private' AND c.relkind='r'
    AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity))
 THEN RAISE EXCEPTION 'RLS_REQUIRED'; END IF;
 IF has_schema_privilege('anon','digiy_core_private','USAGE') OR
   has_schema_privilege('authenticated','digiy_core_private','USAGE') OR
   has_schema_privilege('service_role','digiy_core_private','USAGE') OR
   has_table_privilege('anon','digiy_core_private.module_links','SELECT') OR
   has_table_privilege('authenticated','digiy_core_private.module_links','INSERT')
 THEN RAISE EXCEPTION 'UNEXPECTED_API_ACCESS'; END IF;
END $proof$;

-- Controlled synthetic rows, rolled back completely.
INSERT INTO digiy_core_private.professionals(id,lifecycle)
 VALUES ('00000000-0000-4000-8000-000000000001','pending');
INSERT INTO digiy_core_private.module_links
 (professional_id,module,source_key,verification_status)
 VALUES ('00000000-0000-4000-8000-000000000001','EXPLORE','synthetic-pro','pending');
DO $verify$
BEGIN
 BEGIN
  INSERT INTO digiy_core_private.module_links
   (professional_id,module,source_key,verification_status)
  VALUES ('00000000-0000-4000-8000-000000000001','EXPLORE','synthetic-pro','pending');
  RAISE EXCEPTION 'DUPLICATE_LINK_ALLOWED';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  INSERT INTO digiy_core_private.module_links
   (professional_id,module,source_key,verification_status)
  VALUES ('00000000-0000-4000-8000-000000000001','JOB','unverified-candidate','verified');
  RAISE EXCEPTION 'UNVERIFIED_LINK_ALLOWED';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  INSERT INTO digiy_core_private.module_links
   (professional_id,module,source_key,verification_status)
  VALUES ('00000000-0000-4000-8000-000000000001','DUMMY','bad-module','pending');
  RAISE EXCEPTION 'UNKNOWN_MODULE_ALLOWED';
 EXCEPTION WHEN check_violation THEN NULL; END;
END $verify$;
ROLLBACK;
-- DDL still exists but all synthetic tests are gone; no public access created.
SELECT count(*) AS ZERO_TEST_LINKS FROM digiy_core_private.module_links;
SELECT count(*) AS ZERO_TEST_SUBJECTS FROM digiy_core_private.professionals;
