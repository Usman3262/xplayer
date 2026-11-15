-- 023 · Remote app diagnostics (developer request 2026-11-15).
-- The apps upload their important log lines ([PANEL] / [SYNC] / [ACCOUNT] /
-- [BACKEND] / errors / crashes) so issues on real devices can be read and
-- tested without copying logs by hand. Lines are scrubbed on the device (no
-- credentials, no stream URLs, no MACs). Writes only through
-- log_app_events (size + rate limits, on/off from admin); reads only for
-- admins with support.read. Old rows are removed automatically.

create table public.app_logs (
  id            bigint generated always as identity primary key,
  created_at    timestamptz not null default now(),
  logged_at     timestamptz not null,
  device_id     text not null check (device_id ~ '^[a-z0-9]{8,64}$'),
  session_id    text not null check (session_id ~ '^[a-z0-9]{4,32}$'),
  user_id       uuid references auth.users (id) on delete set null,
  platform      text not null check (platform in ('android', 'ios', 'tv', 'web')),
  app_version   text check (char_length(app_version) <= 40),
  device_model  text check (char_length(device_model) <= 80),
  tag           text not null check (tag ~ '^[A-Z]{2,12}$'),
  message       text not null check (char_length(message) <= 2000)
);
comment on table public.app_logs is 'Scrubbed diagnostic lines uploaded by the apps (no credentials). Auto-pruned.';

create index app_logs_created_idx on public.app_logs (created_at desc);
create index app_logs_device_idx on public.app_logs (device_id, created_at desc);

alter table public.app_logs enable row level security;
-- No direct writes from clients; only log_app_events below.
revoke all on public.app_logs from anon, authenticated;
grant select on public.app_logs to authenticated;
create policy app_logs_select on public.app_logs
  for select to authenticated
  using ((select public.has_permission('support.read')));

insert into public.app_settings (key, category, value_type, value, default_value, validation, description) values
  ('diagnostics.remote_logs', 'diagnostics', 'bool', 'true', 'true', '{}',
   'Apps upload important diagnostic lines (scrubbed, no credentials) for support'),
  ('diagnostics.log_retention_days', 'diagnostics', 'int', '7', '7', '{"min":1,"max":30}',
   'Days to keep uploaded app diagnostic lines')
on conflict (key) do nothing;

-- Batch upload from an app. Silently ignores what it can't accept (logging
-- must never break the app): off switch, too many lines, bad fields, flood.
create or replace function public.log_app_events(
  p_device text,
  p_session text,
  p_platform text,
  p_version text,
  p_model text,
  p_events jsonb
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  enabled boolean;
  keep_days int;
  recent int;
  n int := 0;
  e jsonb;
  t timestamptz;
begin
  select coalesce((value)::text::boolean, true) into enabled
    from public.app_settings where key = 'diagnostics.remote_logs';
  if enabled is false then
    return 0;
  end if;
  if p_device !~ '^[a-z0-9]{8,64}$' or p_session !~ '^[a-z0-9]{4,32}$'
     or p_platform not in ('android', 'ios', 'tv', 'web')
     or jsonb_typeof(p_events) <> 'array' or jsonb_array_length(p_events) > 100 then
    return 0;
  end if;

  -- Flood guard: at most 600 lines per device per 10 minutes.
  select count(*) into recent from public.app_logs
   where device_id = p_device and created_at > now() - interval '10 minutes';
  if recent >= 600 then
    return 0;
  end if;

  for e in select * from jsonb_array_elements(p_events) loop
    continue when jsonb_typeof(e) <> 'object'
              or coalesce(e ->> 'tag', '') !~ '^[A-Z]{2,12}$'
              or coalesce(e ->> 'msg', '') = '';
    begin
      t := (e ->> 't')::timestamptz;
    exception when others then
      t := now();
    end;
    if t is null or t > now() + interval '1 day' or t < now() - interval '7 days' then
      t := now();
    end if;
    insert into public.app_logs (logged_at, device_id, session_id, user_id, platform, app_version, device_model, tag, message)
    values (t, p_device, p_session, (select auth.uid()), p_platform,
            left(p_version, 40), left(p_model, 80), e ->> 'tag', left(e ->> 'msg', 2000));
    n := n + 1;
  end loop;

  -- Retention, amortised: ~1 in 50 uploads prunes old rows (bounded batch).
  if random() < 0.02 then
    select coalesce((value)::text::int, 7) into keep_days
      from public.app_settings where key = 'diagnostics.log_retention_days';
    delete from public.app_logs
     where id in (select id from public.app_logs
                   where created_at < now() - make_interval(days => coalesce(keep_days, 7))
                   limit 5000);
  end if;
  return n;
end;
$$;
revoke all on function public.log_app_events(text, text, text, text, text, jsonb) from public;
grant execute on function public.log_app_events(text, text, text, text, text, jsonb) to anon, authenticated;
