-- Runs ONLY on disposable PostgreSQL 17 fixture.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS public;
CREATE TABLE IF NOT EXISTS public.digiy_explore_places(id uuid);
CREATE TABLE IF NOT EXISTS public.digiy_resa_profiles(id uuid);
CREATE TABLE IF NOT EXISTS public.digiy_commerce_sites(id uuid);
CREATE TABLE IF NOT EXISTS public.digiy_build_pros(id uuid);
CREATE TABLE IF NOT EXISTS public.digiy_jobs_owner_workspaces(id uuid);
DO $roles$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticator') THEN CREATE ROLE authenticator NOLOGIN; END IF;
END $roles$;
