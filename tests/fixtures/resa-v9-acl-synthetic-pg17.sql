-- Entirely synthetic PostgreSQL 17 catalog for ACL export/replay CI.
-- Never connected to DIGIY CORE. Zero real rows or credentials.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE TABLE public.digiy_resa_universal_launch_controls (slug text PRIMARY KEY, enabled boolean NOT NULL DEFAULT false);
ALTER TABLE public.digiy_resa_universal_launch_controls ENABLE ROW LEVEL SECURITY;
GRANT ALL ON TABLE public.digiy_resa_universal_launch_controls TO service_role;

CREATE FUNCTION public.digiy_resa_universal_request_v0(p_slug text,p_slot_id uuid,p_service_id uuid,p_client_name text,p_client_phone text,p_request_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path TO public AS $$ SELECT false $$;
CREATE FUNCTION public.digiy_resa_universal_request_v1(p_slug text,p_slot_id uuid,p_service_id uuid,p_client_name text,p_client_phone text,p_request_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path TO public AS $$ SELECT false $$;
CREATE FUNCTION public.digiy_resa_universal_owner_manage_v2(p_booking_id uuid,p_action text,p_note_text text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path TO public AS $$ SELECT false $$;
CREATE FUNCTION public.digiy_resa_universal_pilot_gate_v1(p_slug text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path TO public AS $$ SELECT false $$;
CREATE FUNCTION public.digiy_resa_universal_public_options_v1(p_slug text,p_start_date date)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path TO public AS $$ SELECT false $$;

REVOKE ALL ON FUNCTION public.digiy_resa_universal_request_v0(text,uuid,uuid,text,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.digiy_resa_universal_request_v1(text,uuid,uuid,text,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.digiy_resa_universal_owner_manage_v2(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.digiy_resa_universal_pilot_gate_v1(text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.digiy_resa_universal_public_options_v1(text,date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.digiy_resa_universal_request_v0(text,uuid,uuid,text,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.digiy_resa_universal_request_v1(text,uuid,uuid,text,text,uuid) TO anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.digiy_resa_universal_owner_manage_v2(uuid,text,text) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.digiy_resa_universal_pilot_gate_v1(text) TO anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.digiy_resa_universal_public_options_v1(text,date) TO anon,authenticated,service_role;
