-- 002 · App configuration (remote control of the apps)
--
-- Admins edit the tables below (= draft). `publish_app_config()` freezes them
-- into one JSON snapshot in `config_versions`. Apps call ONE function,
-- `get_app_config(platform, app_version, known_version)`, which returns the
-- latest snapshot evaluated for that platform/version/time — or just
-- `{"version":n,"unchanged":true}` when the app already has it.

-- ─────────────────────────────────────────────────────────────────────────────
-- Generic audit trigger (actor = current user). Reused by later migrations.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  pk text;
begin
  pk := coalesce(
    to_jsonb(coalesce(new, old)) ->> 'id',
    to_jsonb(coalesce(new, old)) ->> 'key',
    to_jsonb(coalesce(new, old)) ->> 'platform'
  );
  insert into public.audit_logs (actor_id, action, entity, entity_id, before, after)
  values (
    (select auth.uid()),
    lower(tg_op),
    tg_table_name,
    pk,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$$;
revoke all on function public.audit_row_change() from public, anon, authenticated;

-- Semantic version compare: -1 / 0 / 1. "6.0.36+145" → 6.0.36 (build ignored).
create or replace function public.version_cmp(a text, b text)
returns int
language plpgsql
immutable
set search_path = ''
as $$
declare
  pa int[];
  pb int[];
  i int;
  sa text := regexp_replace(split_part(coalesce(a, '0'), '+', 1), '[^0-9.]', '', 'g');
  sb text := regexp_replace(split_part(coalesce(b, '0'), '+', 1), '[^0-9.]', '', 'g');
begin
  pa := array[
    coalesce(nullif(split_part(sa, '.', 1), '')::int, 0),
    coalesce(nullif(split_part(sa, '.', 2), '')::int, 0),
    coalesce(nullif(split_part(sa, '.', 3), '')::int, 0)];
  pb := array[
    coalesce(nullif(split_part(sb, '.', 1), '')::int, 0),
    coalesce(nullif(split_part(sb, '.', 2), '')::int, 0),
    coalesce(nullif(split_part(sb, '.', 3), '')::int, 0)];
  for i in 1..3 loop
    if pa[i] < pb[i] then return -1; end if;
    if pa[i] > pb[i] then return 1; end if;
  end loop;
  return 0;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Settings (typed key/value)
-- ─────────────────────────────────────────────────────────────────────────────
create table public.app_settings (
  key            text primary key check (key ~ '^[a-z_]+(\.[a-z_]+)+$'),
  category       text not null,
  value_type     text not null
                   check (value_type in ('bool', 'int', 'number', 'string', 'enum',
                                         'color', 'url', 'json', 'string_list')),
  value          jsonb not null,
  default_value  jsonb not null,
  validation     jsonb not null default '{}'::jsonb,  -- {"options":[..]} / {"min":0,"max":10}
  description    text not null,
  is_public      boolean not null default true,      -- sent to the apps
  updated_by     uuid references auth.users (id) on delete set null,
  updated_at     timestamptz not null default now()
);
create index app_settings_category_idx on public.app_settings (category);

-- Reject values that don't match the declared type / validation.
create or replace function public.validate_app_setting()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  t text := jsonb_typeof(new.value);
  opts jsonb := new.validation -> 'options';
begin
  if new.value_type = 'bool' and t <> 'boolean' then
    raise exception 'setting % must be a boolean', new.key;
  elsif new.value_type in ('int', 'number') then
    if t <> 'number' then raise exception 'setting % must be a number', new.key; end if;
    if new.value_type = 'int' and (new.value #>> '{}')::numeric % 1 <> 0 then
      raise exception 'setting % must be an integer', new.key;
    end if;
    if new.validation ? 'min' and (new.value #>> '{}')::numeric < (new.validation ->> 'min')::numeric then
      raise exception 'setting % is below its minimum', new.key;
    end if;
    if new.validation ? 'max' and (new.value #>> '{}')::numeric > (new.validation ->> 'max')::numeric then
      raise exception 'setting % is above its maximum', new.key;
    end if;
  elsif new.value_type in ('string', 'url', 'color', 'enum') and t <> 'string' then
    raise exception 'setting % must be a string', new.key;
  elsif new.value_type = 'enum' and opts is not null and not (opts ? (new.value #>> '{}')) then
    raise exception 'setting % must be one of %', new.key, opts;
  elsif new.value_type = 'color' and (new.value #>> '{}') !~ '^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$' then
    raise exception 'setting % must be a #RRGGBB or #AARRGGBB colour', new.key;
  elsif new.value_type = 'url' and (new.value #>> '{}') !~ '^(https?://.+)?$' then
    raise exception 'setting % must be an http(s) URL', new.key;
  elsif new.value_type = 'string_list' and t <> 'array' then
    raise exception 'setting % must be a list', new.key;
  end if;
  new.updated_at := now();
  new.updated_by := coalesce((select auth.uid()), new.updated_by);
  return new;
end;
$$;
revoke all on function public.validate_app_setting() from public, anon, authenticated;

create trigger app_settings_validate
  before insert or update on public.app_settings
  for each row execute function public.validate_app_setting();

-- ─────────────────────────────────────────────────────────────────────────────
-- Feature flags (+ targeted overrides)
-- ─────────────────────────────────────────────────────────────────────────────
create table public.feature_flags (
  key              text primary key check (key ~ '^[a-z_]+$'),
  name             text not null,
  description      text not null,
  enabled          boolean not null default false,
  platforms        text[] check (platforms <@ array['android', 'ios', 'tv']),  -- null = all
  min_app_version  text,
  max_app_version  text,
  starts_at        timestamptz,
  ends_at          timestamptz,
  is_public        boolean not null default true,
  updated_by       uuid references auth.users (id) on delete set null,
  updated_at       timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create table public.feature_overrides (
  id            uuid primary key default gen_random_uuid(),
  flag_key      text not null references public.feature_flags (key) on delete cascade,
  target_type   text not null check (target_type in ('user', 'country', 'plan')),
  target_value  text not null,
  enabled       boolean not null,
  starts_at     timestamptz,
  ends_at       timestamptz,
  created_by    uuid references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  unique (flag_key, target_type, target_value)
);
create index feature_overrides_target_idx
  on public.feature_overrides (target_type, target_value);

create trigger feature_flags_set_updated_at
  before update on public.feature_flags
  for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- App versions, maintenance, onboarding panel types, themes
-- ─────────────────────────────────────────────────────────────────────────────
create table public.app_versions (
  platform             text primary key check (platform in ('android', 'ios', 'tv')),
  min_version          text not null default '0.0.0',  -- below = must update
  recommended_version  text,                           -- below = suggest update
  latest_version       text,
  update_url           text check (update_url is null or update_url ~ '^https://'),
  release_notes        text,
  updated_by           uuid references auth.users (id) on delete set null,
  updated_at           timestamptz not null default now()
);
create trigger app_versions_set_updated_at
  before update on public.app_versions
  for each row execute function public.set_updated_at();

create table public.maintenance_windows (
  id          uuid primary key default gen_random_uuid(),
  platforms   text[] check (platforms <@ array['android', 'ios', 'tv']),  -- null = all
  title       text not null,
  message     text not null,
  starts_at   timestamptz not null,
  ends_at     timestamptz not null,
  is_active   boolean not null default true,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index maintenance_windows_active_idx
  on public.maintenance_windows (ends_at) where is_active;

-- "Choose your panel" screen. `fields` describes the connect form, e.g.
-- [{"key":"host","type":"url","label":"Server URL","required":true}, …]
create table public.onboarding_panel_types (
  key          text primary key check (key ~ '^[a-z0-9_]+$'),
  label        text not null,
  description  text,
  help_text    text,
  icon         text,
  sort_order   int not null default 0,
  is_enabled   boolean not null default true,
  platforms    text[] check (platforms <@ array['android', 'ios', 'tv']),
  fields       jsonb not null default '[]'::jsonb check (jsonb_typeof(fields) = 'array'),
  updated_by   uuid references auth.users (id) on delete set null,
  updated_at   timestamptz not null default now()
);
create trigger onboarding_panel_types_set_updated_at
  before update on public.onboarding_panel_types
  for each row execute function public.set_updated_at();

-- Tokens match Flutter AppThemeConfig keys (background, surface, primary, …).
create table public.app_themes (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  tokens      jsonb not null check (jsonb_typeof(tokens) = 'object'),
  is_active   boolean not null default false,
  updated_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index app_themes_one_active on public.app_themes (is_active) where is_active;
create trigger app_themes_set_updated_at
  before update on public.app_themes
  for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- Published snapshots
-- ─────────────────────────────────────────────────────────────────────────────
create table public.config_versions (
  version       bigint generated always as identity primary key,
  snapshot      jsonb not null,
  notes         text,
  published_by  uuid references auth.users (id) on delete set null,
  published_at  timestamptz not null default now()
);

-- Freeze the current (public) config into one JSON document.
create or replace function public.build_app_config_snapshot()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'settings', coalesce((
      select jsonb_object_agg(s.key, s.value)
      from public.app_settings s where s.is_public), '{}'::jsonb),
    'flags', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', f.key, 'enabled', f.enabled, 'platforms', f.platforms,
        'min', f.min_app_version, 'max', f.max_app_version,
        'from', f.starts_at, 'to', f.ends_at) order by f.key)
      from public.feature_flags f where f.is_public), '[]'::jsonb),
    'versions', coalesce((
      select jsonb_object_agg(v.platform, jsonb_build_object(
        'min', v.min_version, 'recommended', v.recommended_version,
        'latest', v.latest_version, 'url', v.update_url, 'notes', v.release_notes))
      from public.app_versions v), '{}'::jsonb),
    'maintenance', coalesce((
      select jsonb_agg(jsonb_build_object(
        'platforms', m.platforms, 'title', m.title, 'message', m.message,
        'from', m.starts_at, 'to', m.ends_at) order by m.starts_at)
      from public.maintenance_windows m
      where m.is_active and m.ends_at > now()), '[]'::jsonb),
    'onboarding', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', o.key, 'label', o.label, 'description', o.description,
        'help', o.help_text, 'icon', o.icon, 'platforms', o.platforms,
        'fields', o.fields) order by o.sort_order, o.key)
      from public.onboarding_panel_types o where o.is_enabled), '[]'::jsonb),
    'theme', coalesce((
      select t.tokens from public.app_themes t where t.is_active), '{}'::jsonb)
  );
$$;
revoke all on function public.build_app_config_snapshot() from public, anon, authenticated;

-- Admin action: publish the current tables as a new version.
create or replace function public.publish_app_config(p_notes text default null)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v bigint;
begin
  if not public.has_permission('customization.publish') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into public.config_versions (snapshot, notes, published_by)
  values (public.build_app_config_snapshot(), p_notes, (select auth.uid()))
  returning version into v;
  perform public.log_audit('publish', 'app_config', v::text, null, null,
                           jsonb_build_object('notes', p_notes));
  return v;
end;
$$;
revoke all on function public.publish_app_config(text) from public, anon;
grant execute on function public.publish_app_config(text) to authenticated;

-- App entry point (anon + signed-in). One small call per app start/refresh.
create or replace function public.get_app_config(
  p_platform text,
  p_app_version text default null,
  p_known_version bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  cv public.config_versions;
  snap jsonb;
  now_ts timestamptz := now();
  uid uuid := (select auth.uid());
  user_country text;
  flags jsonb := '{}'::jsonb;
  f jsonb;
  on_ boolean;
  ov record;
  has_schedule boolean := false;
begin
  if p_platform not in ('android', 'ios', 'tv') then
    raise exception 'unknown platform' using errcode = '22023';
  end if;

  select * into cv from public.config_versions order by version desc limit 1;
  if cv.version is null then
    return jsonb_build_object('version', 0, 'unchanged', false);
  end if;
  snap := cv.snapshot;

  -- Time-based items make a cached copy stale, so only short-circuit when none exist.
  has_schedule := exists (
      select 1 from jsonb_array_elements(snap -> 'flags') x
      where x ->> 'from' is not null or x ->> 'to' is not null)
    or jsonb_array_length(snap -> 'maintenance') > 0;

  if p_known_version = cv.version and not has_schedule and uid is null then
    return jsonb_build_object('version', cv.version, 'unchanged', true);
  end if;

  -- Evaluate flags for this platform / version / time.
  for f in select * from jsonb_array_elements(snap -> 'flags') loop
    on_ := (f ->> 'enabled')::boolean
      and (f -> 'platforms' = 'null'::jsonb or (f -> 'platforms') ? p_platform)
      and (f ->> 'min' is null or p_app_version is null
           or public.version_cmp(p_app_version, f ->> 'min') >= 0)
      and (f ->> 'max' is null or p_app_version is null
           or public.version_cmp(p_app_version, f ->> 'max') <= 0)
      and (f ->> 'from' is null or (f ->> 'from')::timestamptz <= now_ts)
      and (f ->> 'to' is null or (f ->> 'to')::timestamptz > now_ts);
    flags := flags || jsonb_build_object(f ->> 'key', on_);
  end loop;

  -- Targeted overrides (signed-in users): country, then user (user wins).
  if uid is not null then
    select p.country into user_country from public.profiles p where p.id = uid;
    for ov in
      select o.flag_key, o.enabled
      from public.feature_overrides o
      where ((o.target_type = 'country' and o.target_value = user_country)
          or (o.target_type = 'user' and o.target_value = uid::text))
        and (o.starts_at is null or o.starts_at <= now_ts)
        and (o.ends_at is null or o.ends_at > now_ts)
        and flags ? o.flag_key
      order by case o.target_type when 'country' then 1 else 2 end
    loop
      flags := flags || jsonb_build_object(ov.flag_key, ov.enabled);
    end loop;
  end if;

  return jsonb_build_object(
    'version', cv.version,
    'unchanged', false,
    'published_at', cv.published_at,
    'settings', snap -> 'settings',
    'flags', flags,
    'version_policy', coalesce(snap -> 'versions' -> p_platform, 'null'::jsonb),
    'maintenance', coalesce((
      select x from jsonb_array_elements(snap -> 'maintenance') x
      where (x -> 'platforms' = 'null'::jsonb or (x -> 'platforms') ? p_platform)
        and (x ->> 'from')::timestamptz <= now_ts
        and (x ->> 'to')::timestamptz > now_ts
      limit 1), 'null'::jsonb),
    'onboarding', coalesce((
      select jsonb_agg(x) from jsonb_array_elements(snap -> 'onboarding') x
      where x -> 'platforms' = 'null'::jsonb or (x -> 'platforms') ? p_platform),
      '[]'::jsonb),
    'theme', snap -> 'theme'
  );
end;
$$;
revoke all on function public.get_app_config(text, text, bigint) from public;
grant execute on function public.get_app_config(text, text, bigint) to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS: read = customization.read, write = customization.write; apps use the RPC.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  t text;
begin
  foreach t in array array['app_settings', 'feature_flags', 'feature_overrides',
    'app_versions', 'maintenance_windows', 'onboarding_panel_types', 'app_themes']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format($p$create policy %1$s_select on public.%1$I for select to authenticated
                     using ((select public.has_permission('customization.read')))$p$, t);
    execute format($p$create policy %1$s_insert on public.%1$I for insert to authenticated
                     with check ((select public.has_permission('customization.write')))$p$, t);
    execute format($p$create policy %1$s_update on public.%1$I for update to authenticated
                     using ((select public.has_permission('customization.write')))
                     with check ((select public.has_permission('customization.write')))$p$, t);
    execute format($p$create policy %1$s_delete on public.%1$I for delete to authenticated
                     using ((select public.has_permission('customization.write')))$p$, t);
  end loop;
end;
$$;

alter table public.config_versions enable row level security;
revoke all on public.config_versions from anon;
revoke insert, update, delete on public.config_versions from authenticated;
create policy config_versions_select on public.config_versions
  for select to authenticated using ((select public.has_permission('customization.read')));

-- ─────────────────────────────────────────────────────────────────────────────
-- Defaults
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.app_settings (key, category, value_type, value, default_value, validation, description) values
  ('auth.mode', 'account', 'enum', '"optional"', '"optional"', '{"options":["optional","required","disabled"]}', 'Sign-in policy: optional (guest allowed), required, or disabled (guest only)'),
  ('auth.allow_registration', 'account', 'bool', 'true', 'true', '{}', 'Allow new account sign-ups'),
  ('auth.guest_enabled', 'account', 'bool', 'true', 'true', '{}', 'Allow using the app without an account'),
  ('app.default_language', 'app', 'enum', '"en"', '"en"', '{"options":["en","ar","ur"]}', 'Default interface language'),
  ('app.supported_languages', 'app', 'string_list', '["en","ar","ur"]', '["en","ar","ur"]', '{}', 'Languages users can choose'),
  ('app.support_email', 'app', 'string', '""', '""', '{}', 'Support contact shown in the app (empty = hidden)'),
  ('app.privacy_url', 'app', 'url', '""', '""', '{}', 'Privacy policy link (empty = built-in text)'),
  ('app.terms_url', 'app', 'url', '""', '""', '{}', 'Terms of use link (empty = built-in text)'),
  ('config.refresh_interval_s', 'app', 'int', '900', '900', '{"min":60,"max":86400}', 'How often apps re-check this config (seconds)'),
  ('providers.max_connections', 'providers', 'int', '5', '5', '{"min":1,"max":50}', 'Max panels a user can add'),
  ('providers.connect_timeout_ms', 'providers', 'int', '8000', '8000', '{"min":1000,"max":60000}', 'Panel login timeout'),
  ('providers.request_timeout_ms', 'providers', 'int', '20000', '20000', '{"min":2000,"max":120000}', 'Catalog request timeout'),
  ('providers.request_concurrency', 'providers', 'int', '4', '4', '{"min":1,"max":16}', 'Parallel requests per panel'),
  ('player.live_format', 'player', 'enum', '"ts"', '"ts"', '{"options":["ts","m3u8"]}', 'Preferred live stream format for Xtream panels'),
  ('player.retry_count', 'player', 'int', '3', '3', '{"min":0,"max":10}', 'Automatic stream retries'),
  ('player.buffer_seconds', 'player', 'int', '10', '10', '{"min":2,"max":120}', 'Target buffer'),
  ('player.progress_save_s', 'player', 'int', '30', '30', '{"min":10,"max":300}', 'How often playback progress is saved'),
  ('cache.catalog_ttl_hours', 'cache', 'int', '24', '24', '{"min":1,"max":720}', 'Catalog refresh age'),
  ('cache.epg_retention_hours', 'cache', 'int', '48', '48', '{"min":6,"max":336}', 'EPG kept on device'),
  ('cache.image_cache_mb', 'cache', 'int', '200', '200', '{"min":50,"max":2000}', 'Artwork cache size on device'),
  ('search.min_chars', 'search', 'int', '2', '2', '{"min":1,"max":5}', 'Characters before search starts'),
  ('notifications.inbox_enabled', 'notifications', 'bool', 'true', 'true', '{}', 'In-app notification inbox');

insert into public.feature_flags (key, name, description, enabled) values
  ('live_tv', 'Live TV', 'Live channels tab', true),
  ('movies', 'Movies', 'Movies tab', true),
  ('series', 'Series', 'Series tab', true),
  ('epg', 'TV guide (EPG)', 'Programme guide for live channels', true),
  ('catchup', 'Catch-up', 'Watch past programmes where the panel supports it', true),
  ('search', 'Search', 'Universal search', true),
  ('favorites', 'Favorites', 'Favorite channels and titles', true),
  ('watch_history', 'Watch history', 'History and continue watching', true),
  ('multi_provider', 'Multiple panels', 'Let users add more than one panel', true),
  ('profiles', 'Profiles', 'Multiple household profiles', true),
  ('parental_controls', 'Parental controls', 'PIN, kids mode, locked categories', true),
  ('kids', 'Kids section', 'Kids home and catalog', true),
  ('sports', 'Sports', 'Matches, lineups and standings', true),
  ('clips', 'Clips', 'Short clips feed', false),
  ('downloads', 'Downloads', 'Offline downloads', false),
  ('picture_in_picture', 'Picture-in-picture', 'Keep playing in a small window', true),
  ('chromecast', 'Cast', 'Cast to TV', false),
  ('trailers', 'Trailers', 'Play trailers on details pages', true),
  ('tmdb_metadata', 'Rich metadata', 'Posters, cast and plots from the metadata service', true),
  ('push_notifications', 'Push notifications', 'FCM push (built, off until enabled here)', false),
  ('notification_inbox', 'Notification inbox', 'In-app messages', true),
  ('diagnostics', 'Diagnostics', 'Playback and connection diagnostics screens', true),
  ('speed_test', 'Speed test', 'Network speed test in settings', true),
  ('theme_presets', 'Appearance presets', 'Let users pick an appearance preset', true),
  ('guest_mode', 'Guest mode', 'Use the app without an account', true);

insert into public.app_versions (platform, min_version, recommended_version) values
  ('android', '0.0.0', null), ('ios', '0.0.0', null), ('tv', '0.0.0', null);

insert into public.onboarding_panel_types (key, label, description, help_text, icon, sort_order, fields) values
  ('xtream', 'Xtream Codes', 'Server URL, username and password', 'Use the details your provider sent you (often called "Xtream" or "API" login).', 'dns', 1,
   '[{"key":"host","type":"url","label":"Server URL","placeholder":"http://example.com:8080","required":true},
     {"key":"username","type":"text","label":"Username","required":true},
     {"key":"password","type":"password","label":"Password","required":true}]'),
  ('m3u', 'M3U playlist', 'Playlist link or file', 'Paste the M3U/M3U8 link from your provider.', 'playlist_play', 2,
   '[{"key":"url","type":"url","label":"Playlist URL","placeholder":"http://example.com/get.php?…","required":true},
     {"key":"epg_url","type":"url","label":"EPG URL (optional)","required":false}]'),
  ('stalker', 'Stalker portal (MAC)', 'Portal URL and MAC address', 'Use the portal link and the MAC address registered with your provider.', 'router', 3,
   '[{"key":"portal","type":"url","label":"Portal URL","placeholder":"http://example.com/c/","required":true},
     {"key":"mac","type":"mac","label":"MAC address","placeholder":"00:1A:79:00:00:00","required":true}]');

insert into public.app_themes (name, tokens, is_active) values
  ('XPlayer default', '{
    "background":"#0B0B12","surface":"#14141F","surfaceElevated":"#1C1C2B",
    "primary":"#22D3EE","primaryDim":"#06B6D4","secondary":"#7C3AED",
    "gold":"#FBBF24","live":"#F43F5E","success":"#34D399",
    "textPrimary":"#F1F5F9","textSecondary":"#94A3B8",
    "border":"#2A2A3D","danger":"#EF4444"}', true);

-- First published version so apps get a config immediately.
insert into public.config_versions (snapshot, notes)
values (public.build_app_config_snapshot(), 'Initial defaults');

-- Audit every admin change from now on (created after the defaults on purpose).
do $$
declare
  t text;
begin
  foreach t in array array['app_settings', 'feature_flags', 'feature_overrides',
    'app_versions', 'maintenance_windows', 'onboarding_panel_types', 'app_themes']
  loop
    execute format('create trigger %1$s_audit after insert or update or delete on public.%1$I
                     for each row execute function public.audit_row_change()', t);
  end loop;
end;
$$;
