-- DIGIY P0 candidate: serverless admin using verified Supabase Auth user + existing admin PIN.
-- HOLD: do not apply to production before code review and smoke test plan.
-- Additive: DOES NOT revoke admin_login, change any existing PIN, or break legacy backoffice.
create schema if not exists digiy_admin_private;
revoke all on schema digiy_admin_private from public, anon, authenticated;
create table if not exists digiy_admin_private.pin_attempt_limits (
  user_id uuid primary key,
  attempts integer not null default 0,
  window_started_at timestamptz not null default now(),
  locked_until timestamptz
);
revoke all on digiy_admin_private.pin_attempt_limits from public, anon, authenticated;
alter table digiy_admin_private.pin_attempt_limits enable row level security;

create or replace function public.digiy_admin_login_for_user(p_user_id uuid, p_pin text)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, extensions
as $$
declare
  v_state digiy_admin_private.pin_attempt_limits%rowtype;
  v_role text;
  v_label text;
  v_token text;
  v_expires_at timestamptz;
begin
  -- The Edge Function validates Supabase Auth, then passes the verified user.id.
  -- Caller privilege is service_role only.
  select coalesce(a.label,'Admin')
    into v_label
    from public.digiy_admins a
   where a.user_id=p_user_id and a.is_active is true
   limit 1;
  if not found then
    return jsonb_build_object('ok',false,'error','access_denied');
  end if;

  insert into digiy_admin_private.pin_attempt_limits(user_id)
  values(p_user_id) on conflict(user_id) do nothing;
  select * into v_state from digiy_admin_private.pin_attempt_limits
    where user_id=p_user_id for update;
  if v_state.locked_until is not null and v_state.locked_until > now() then
    return jsonb_build_object('ok',false,'error','temporarily_locked');
  end if;
  if v_state.window_started_at < now()-interval '15 minutes' then
    update digiy_admin_private.pin_attempt_limits
      set attempts=0, window_started_at=now(), locked_until=null
      where user_id=p_user_id;
  end if;
  if p_pin is null or length(trim(p_pin)) < 4 or length(trim(p_pin)) > 32 or not exists (
    select 1 from public.digiy_admin_pins ap
     where ap.is_active is true
       and ap.pin_hash = extensions.crypt(trim(p_pin), ap.pin_hash)
  ) then
    update digiy_admin_private.pin_attempt_limits
      set attempts=attempts+1,
          locked_until=case when attempts+1 >= 5 then now()+interval '15 minutes' else null end
      where user_id=p_user_id;
    return jsonb_build_object('ok',false,'error','invalid_credentials');
  end if;
  update digiy_admin_private.pin_attempt_limits
     set attempts=0,window_started_at=now(),locked_until=null
   where user_id=p_user_id;

  select coalesce(ap.role,'OPS') into v_role
    from public.digiy_admin_pins ap where ap.is_active is true
    order by ap.created_at desc limit 1;
  update public.digiy_admin_tokens set revoked=true
   where user_id=p_user_id and revoked=false and expires_at>now();
  v_token := pg_catalog.encode(extensions.gen_random_bytes(32),'hex');
  v_expires_at := now()+interval '8 hours';
  insert into public.digiy_admin_tokens(token,created_at,expires_at,revoked,user_id)
    values(v_token,now(),v_expires_at,false,p_user_id);
  return jsonb_build_object('ok',true,'token',v_token,'exp',extract(epoch from v_expires_at)*1000,
                            'role',coalesce(v_role,'OPS'),'label',v_label);
end;
$$;
revoke execute on function public.digiy_admin_login_for_user(uuid,text) from public, anon, authenticated;
grant execute on function public.digiy_admin_login_for_user(uuid,text) to service_role;

create or replace function public.digiy_admin_check_for_user(p_user_id uuid,p_token text)
returns boolean language sql stable security definer
set search_path = pg_catalog, extensions
as $$
  select exists (
    select 1 from public.digiy_admin_tokens t
      join public.digiy_admins a on a.user_id=t.user_id
    where t.user_id=p_user_id and t.token=p_token and t.revoked=false
      and t.expires_at>now() and a.is_active is true
  );
$$;
revoke execute on function public.digiy_admin_check_for_user(uuid,text) from public, anon, authenticated;
grant execute on function public.digiy_admin_check_for_user(uuid,text) to service_role;
-- Existing admin_login and its grants deliberately remain unchanged for zero-cutover risk.