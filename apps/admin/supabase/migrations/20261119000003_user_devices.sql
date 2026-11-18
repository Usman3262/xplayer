-- 8.3 · Devices of a signed-in user. One row per (user, app install).
-- Never holds panel credentials, MAC or stream URLs — only what the user
-- and support need to recognise a device. A revoked device signs itself
-- out on its next check-in.

create table public.user_devices (
  user_id       uuid not null references auth.users (id) on delete cascade,
  device_id     text not null check (device_id ~ '^[a-z0-9]{8,64}$'),
  name          text check (char_length(name) <= 80),
  platform      text not null default 'android' check (platform in ('android', 'ios', 'android_tv', 'web', 'other')),
  model         text check (char_length(model) <= 120),
  os_version    text check (char_length(os_version) <= 60),
  app_version   text check (char_length(app_version) <= 40),
  panel_kind    text check (panel_kind in ('xtream', 'm3u', 'stalker')),
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  revoked_at    timestamptz,
  revoked_by    uuid references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (user_id, device_id)
);
comment on table public.user_devices is 'Devices of a signed-in user (no panel credentials). Revoked = signs out at next check-in.';
create index user_devices_seen_idx on public.user_devices (last_seen_at desc);

create trigger user_devices_set_updated_at before update on public.user_devices
  for each row execute function public.set_updated_at();

alter table public.user_devices enable row level security;
-- Users read their own devices; every write goes through the RPCs below.
create policy user_devices_own_select on public.user_devices
  for select to authenticated using (user_id = (select auth.uid()));

-- App check-in (sign-in, app start / resume; the app sends it ≤ 1 / 6 h).
-- Returns {revoked: bool}. A revoked device stays revoked until the user
-- signs in again on it (p_signed_in = true clears it).
create or replace function public.device_checkin(p_device jsonb, p_signed_in boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  did text := lower(coalesce(p_device->>'id', ''));
  was_revoked timestamptz;
begin
  if uid is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  if did !~ '^[a-z0-9]{8,64}$' then
    raise exception 'bad device id' using errcode = '22023';
  end if;
  select revoked_at into was_revoked from public.user_devices where user_id = uid and device_id = did;
  if was_revoked is not null and not p_signed_in then
    return jsonb_build_object('revoked', true);
  end if;
  insert into public.user_devices as d (user_id, device_id, name, platform, model, os_version, app_version, panel_kind)
  values (uid, did,
          left(nullif(p_device->>'name', ''), 80),
          case when p_device->>'platform' in ('android', 'ios', 'android_tv', 'web') then p_device->>'platform' else 'other' end,
          left(p_device->>'model', 120), left(p_device->>'os', 60), left(p_device->>'app', 40),
          case when p_device->>'panel' in ('xtream', 'm3u', 'stalker') then p_device->>'panel' end)
  on conflict (user_id, device_id) do update set
    model = excluded.model, os_version = excluded.os_version, app_version = excluded.app_version,
    panel_kind = coalesce(excluded.panel_kind, d.panel_kind), platform = excluded.platform,
    last_seen_at = now(), revoked_at = null, revoked_by = null;
  return jsonb_build_object('revoked', false);
end;
$$;

-- The user removes one of their own devices (it signs out there).
create or replace function public.device_revoke_mine(p_device text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  update public.user_devices set revoked_at = now(), revoked_by = (select auth.uid())
   where user_id = (select auth.uid()) and device_id = p_device and revoked_at is null;
end;
$$;

-- Admin: devices of all users, newest activity first, keyset paging.
create or replace function public.admin_list_devices(
  p_search text default null,
  p_before_seen timestamptz default null,
  p_limit int default 25
)
returns table (
  user_id uuid, email text, device_id text, name text, platform text, model text,
  app_version text, panel_kind text, first_seen_at timestamptz, last_seen_at timestamptz, revoked_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  q text := nullif(btrim(coalesce(p_search, '')), '');
  lim int := least(greatest(coalesce(p_limit, 25), 1), 100);
begin
  if not public.has_permission('devices.read') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
    select d.user_id, u.email::text, d.device_id, d.name, d.platform, d.model, d.app_version, d.panel_kind,
           d.first_seen_at, d.last_seen_at, d.revoked_at
    from public.user_devices d
    join auth.users u on u.id = d.user_id
    where (q is null
           or u.email ilike '%' || replace(replace(q, '%', '\%'), '_', '\_') || '%'
           or d.model ilike '%' || replace(replace(q, '%', '\%'), '_', '\_') || '%'
           or d.device_id = lower(q))
      and (p_before_seen is null or d.last_seen_at < p_before_seen)
    order by d.last_seen_at desc
    limit lim;
end;
$$;

create or replace function public.admin_device_counts()
returns table (total int, active_7_days int, revoked int)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('devices.read') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
    select count(*)::int,
           count(*) filter (where last_seen_at > now() - interval '7 days' and revoked_at is null)::int,
           count(*) filter (where revoked_at is not null)::int
    from public.user_devices;
end;
$$;

create or replace function public.admin_revoke_device(p_user uuid, p_device text, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('devices.write') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if char_length(coalesce(p_reason, '')) > 500 then
    raise exception 'reason too long' using errcode = '22023';
  end if;
  update public.user_devices set revoked_at = now(), revoked_by = (select auth.uid())
   where user_id = p_user and device_id = p_device and revoked_at is null;
  if not found then
    raise exception 'device not found or already revoked' using errcode = 'P0002';
  end if;
  perform public.log_audit(
    'device.revoke', 'user_devices', p_user::text || ':' || p_device,
    null, jsonb_build_object('revoked', true),
    case when nullif(btrim(coalesce(p_reason, '')), '') is null then null
         else jsonb_build_object('reason', btrim(p_reason)) end
  );
end;
$$;

revoke all on function public.device_checkin(jsonb, boolean) from public, anon;
revoke all on function public.device_revoke_mine(text) from public, anon;
revoke all on function public.admin_list_devices(text, timestamptz, int) from public, anon;
revoke all on function public.admin_device_counts() from public, anon;
revoke all on function public.admin_revoke_device(uuid, text, text) from public, anon;
grant execute on function public.device_checkin(jsonb, boolean) to authenticated;
grant execute on function public.device_revoke_mine(text) to authenticated;
grant execute on function public.admin_list_devices(text, timestamptz, int) to authenticated;
grant execute on function public.admin_device_counts() to authenticated;
grant execute on function public.admin_revoke_device(uuid, text, text) to authenticated;
