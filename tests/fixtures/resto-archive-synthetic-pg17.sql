-- Synthetic RESTO fixture for isolated PostgreSQL 17 workflow ONLY.
-- No real client details, keys, Supabase accounts or production database.
DO $guard$
BEGIN
 IF current_database()<>'postgres' THEN RAISE EXCEPTION 'expected disposable postgres database'; END IF;
END $guard$;
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE TABLE public.digiy_resa_resto_sites (
 id integer PRIMARY KEY, owner_id uuid, is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE public.digiy_resa_resto_zones (
 id integer PRIMARY KEY, site_id integer NOT NULL REFERENCES public.digiy_resa_resto_sites(id)
);
CREATE TABLE public.digiy_resa_resto_tables (
 id integer PRIMARY KEY, zone_id integer NOT NULL REFERENCES public.digiy_resa_resto_zones(id)
);
CREATE TABLE public.digiy_resa_resto_service_windows (
 id integer PRIMARY KEY, site_id integer NOT NULL REFERENCES public.digiy_resa_resto_sites(id)
);
CREATE TABLE public.digiy_resa_resto_bookings (
 id integer PRIMARY KEY, site_id integer NOT NULL REFERENCES public.digiy_resa_resto_sites(id)
);
CREATE TABLE public.digiy_resa_resto_booking_tables (
 booking_id integer REFERENCES public.digiy_resa_resto_bookings(id),
 table_id integer REFERENCES public.digiy_resa_resto_tables(id)
);
CREATE TABLE public.resa_resto_reservations(id integer PRIMARY KEY);
ALTER TABLE public.digiy_resa_resto_sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.digiy_resa_resto_zones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.digiy_resa_resto_tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.digiy_resa_resto_service_windows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.digiy_resa_resto_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.digiy_resa_resto_booking_tables ENABLE ROW LEVEL SECURITY;
INSERT INTO public.digiy_resa_resto_sites(id,owner_id,is_active)
VALUES (1,'00000000-0000-4000-8000-000000000001',true),
 (2,'00000000-0000-4000-8000-000000000002',true),
 (3,NULL,false),(4,NULL,false);
INSERT INTO public.digiy_resa_resto_zones(id,site_id)
SELECT g,((g-1)%4)+1 FROM generate_series(1,7) g;
INSERT INTO public.digiy_resa_resto_tables(id,zone_id)
SELECT g,((g-1)%7)+1 FROM generate_series(1,10) g;
INSERT INTO public.digiy_resa_resto_service_windows(id,site_id)
SELECT g,((g-1)%4)+1 FROM generate_series(1,8) g;
INSERT INTO public.resa_resto_reservations VALUES (1),(2);
CREATE FUNCTION public.digiy_resa_resto_claim_site_by_email_v1(text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.digiy_resa_resto_owner_refresh_no_shows_v1(uuid)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.digiy_resa_resto_owner_set_booking_status_v1(uuid,text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.digiy_resa_resto_public_book_v1(text,date,time,integer,text,text,text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.digiy_resa_resto_public_availability_v1(text,date,integer,text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
