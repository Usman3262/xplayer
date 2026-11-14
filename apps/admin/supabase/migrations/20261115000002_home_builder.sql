-- 003 · Home builder & merchandising (sections, banners, Top 10)
--
-- Admin builds the home screen; it is frozen into the published config snapshot
-- (`build_app_config_snapshot`) and filtered per platform/country/time in
-- `get_app_config`, so apps still need ONE call.
--
-- Content is referenced portably (TMDB id + kind, or a category name match)
-- because every user's panel has different ids; the app resolves each item
-- against the user's own catalog and hides what the user can't play.

create table public.home_sections (
  id              uuid primary key default gen_random_uuid(),
  title           text not null check (char_length(title) <= 80),
  subtitle        text check (char_length(subtitle) <= 160),
  section_type    text not null check (section_type in (
                    'hero_banners', 'continue_watching', 'top10', 'new_releases',
                    'recently_added', 'trending', 'popular', 'live_now', 'favorites',
                    'recently_watched', 'recommended', 'category', 'genre', 'collection',
                    'matches_live', 'matches_upcoming', 'custom')),
  content_kind    text check (content_kind in ('live', 'movie', 'series', 'mixed')),
  -- auto: app computes (e.g. newest by provider "added"); manual: items below;
  -- random: random picks from the user's catalog; tmdb_*: server-cached TMDB lists;
  -- provider_category: a category/group from the user's panel (params.match).
  source          text not null default 'auto' check (source in (
                    'auto', 'manual', 'random', 'tmdb_trending', 'tmdb_popular',
                    'tmdb_top_rated', 'provider_category')),
  params          jsonb not null default '{}'::jsonb check (jsonb_typeof(params) = 'object'),
  layout          text not null default 'rail' check (layout in (
                    'rail', 'wide_rail', 'grid', 'hero', 'ranked', 'circles', 'cards')),
  item_limit      int not null default 20 check (item_limit between 1 and 100),
  top10_list_id   uuid,  -- FK added below (for section_type = top10)
  sort_order      int not null default 0,
  is_enabled      boolean not null default true,
  platforms       text[] check (platforms <@ array['android', 'ios', 'tv']),  -- null = all
  countries       text[],                                                     -- null = all
  requires_login  boolean not null default false,
  starts_at       timestamptz,
  ends_at         timestamptz,
  updated_by      uuid references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create index home_sections_order_idx on public.home_sections (sort_order) where is_enabled;

create table public.home_section_items (
  id            uuid primary key default gen_random_uuid(),
  section_id    uuid not null references public.home_sections (id) on delete cascade,
  sort_order    int not null default 0,
  item_kind     text not null check (item_kind in ('movie', 'series', 'live', 'link')),
  tmdb_id       int,
  match_title   text,          -- fallback match when no tmdb id (e.g. channel name)
  title         text,          -- display override
  image_url     text,          -- artwork override
  deep_link     text,          -- for item_kind = link
  created_at    timestamptz not null default now(),
  check (item_kind = 'link' and deep_link is not null
         or item_kind <> 'link' and (tmdb_id is not null or match_title is not null))
);
create index home_section_items_section_idx on public.home_section_items (section_id, sort_order);

create table public.banners (
  id              uuid primary key default gen_random_uuid(),
  title           text not null check (char_length(title) <= 100),
  subtitle        text check (char_length(subtitle) <= 200),
  image_url       text not null,       -- phone (16:9)
  image_url_tv    text,                -- TV (wide); falls back to image_url
  cta_label       text check (char_length(cta_label) <= 30),
  action_type     text not null default 'none'
                    check (action_type in ('none', 'content', 'category', 'screen', 'url')),
  action_value    text,                -- screen route / category name / https url
  item_kind       text check (item_kind in ('movie', 'series', 'live')),
  tmdb_id         int,
  sort_order      int not null default 0,
  is_enabled      boolean not null default true,
  platforms       text[] check (platforms <@ array['android', 'ios', 'tv']),
  countries       text[],
  requires_login  boolean not null default false,
  starts_at       timestamptz,
  ends_at         timestamptz,
  updated_by      uuid references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (action_type <> 'url' or action_value ~ '^https://'),
  check (action_type <> 'content' or tmdb_id is not null),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create index banners_order_idx on public.banners (sort_order) where is_enabled;

create table public.top10_lists (
  id            uuid primary key default gen_random_uuid(),
  title         text not null check (char_length(title) <= 80),
  content_kind  text not null check (content_kind in ('movie', 'series', 'mixed')),
  source        text not null default 'manual'
                  check (source in ('manual', 'tmdb_trending', 'auto_watch_stats')),
  country       text check (char_length(country) = 2),  -- null = everywhere
  is_enabled    boolean not null default true,
  updated_by    uuid references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.top10_items (
  list_id       uuid not null references public.top10_lists (id) on delete cascade,
  rank          int not null check (rank between 1 and 10),
  item_kind     text not null check (item_kind in ('movie', 'series')),
  tmdb_id       int,
  match_title   text,
  title         text,
  image_url     text,
  primary key (list_id, rank),
  check (tmdb_id is not null or match_title is not null)
);

alter table public.home_sections
  add constraint home_sections_top10_fk
  foreign key (top10_list_id) references public.top10_lists (id) on delete set null;

do $$
declare
  t text;
begin
  foreach t in array array['home_sections', 'banners', 'top10_lists'] loop
    execute format('create trigger %1$s_set_updated_at before update on public.%1$I
                     for each row execute function public.set_updated_at()', t);
  end loop;
end;
$$;

-- RLS (same model as 002): read customization.read, write customization.write.
do $$
declare
  t text;
begin
  foreach t in array array['home_sections', 'home_section_items', 'banners',
                           'top10_lists', 'top10_items'] loop
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Snapshot now includes "home"
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.build_home_snapshot()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'sections', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'title', s.title, 'subtitle', s.subtitle, 'type', s.section_type,
        'kind', s.content_kind, 'source', s.source, 'params', s.params,
        'layout', s.layout, 'limit', s.item_limit, 'top10', s.top10_list_id,
        'platforms', s.platforms, 'countries', s.countries,
        'login', s.requires_login, 'from', s.starts_at, 'to', s.ends_at,
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'kind', i.item_kind, 'tmdb', i.tmdb_id, 'match', i.match_title,
            'title', i.title, 'image', i.image_url, 'link', i.deep_link)
            order by i.sort_order)
          from public.home_section_items i where i.section_id = s.id), '[]'::jsonb))
        order by s.sort_order, s.created_at)
      from public.home_sections s
      where s.is_enabled and (s.ends_at is null or s.ends_at > now())), '[]'::jsonb),
    'banners', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'title', b.title, 'subtitle', b.subtitle, 'image', b.image_url,
        'image_tv', b.image_url_tv, 'cta', b.cta_label, 'action', b.action_type,
        'value', b.action_value, 'kind', b.item_kind, 'tmdb', b.tmdb_id,
        'platforms', b.platforms, 'countries', b.countries,
        'login', b.requires_login, 'from', b.starts_at, 'to', b.ends_at)
        order by b.sort_order, b.created_at)
      from public.banners b
      where b.is_enabled and (b.ends_at is null or b.ends_at > now())), '[]'::jsonb),
    'top10', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'title', l.title, 'kind', l.content_kind, 'source', l.source,
        'country', l.country,
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'rank', t.rank, 'kind', t.item_kind, 'tmdb', t.tmdb_id,
            'match', t.match_title, 'title', t.title, 'image', t.image_url)
            order by t.rank)
          from public.top10_items t where t.list_id = l.id), '[]'::jsonb)))
      from public.top10_lists l where l.is_enabled), '[]'::jsonb)
  );
$$;
revoke all on function public.build_home_snapshot() from public, anon, authenticated;

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
      select t.tokens from public.app_themes t where t.is_active), '{}'::jsonb),
    'home', public.build_home_snapshot()
  );
$$;
revoke all on function public.build_app_config_snapshot() from public, anon, authenticated;

-- True when a snapshot entry (section/banner) is visible for this request.
create or replace function public.config_item_visible(
  x jsonb, p_platform text, p_country text, p_signed_in boolean, p_now timestamptz)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select (x -> 'platforms' is null or x -> 'platforms' = 'null'::jsonb
          or (x -> 'platforms') ? p_platform)
     and (x -> 'countries' is null or x -> 'countries' = 'null'::jsonb
          or (p_country is not null and (x -> 'countries') ? p_country))
     and (coalesce((x ->> 'login')::boolean, false) = false or p_signed_in)
     and (x ->> 'from' is null or (x ->> 'from')::timestamptz <= p_now)
     and (x ->> 'to' is null or (x ->> 'to')::timestamptz > p_now);
$$;

-- get_app_config: same contract as before + "home" (filtered).
-- p_country: optional ISO-2 hint from the device for guests (signed-in users use their profile).
drop function if exists public.get_app_config(text, text, bigint);
create or replace function public.get_app_config(
  p_platform text,
  p_app_version text default null,
  p_known_version bigint default null,
  p_country text default null
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
  signed_in boolean := false;
  v_country text := upper(left(nullif(trim(p_country), ''), 2));
  flags jsonb := '{}'::jsonb;
  f jsonb;
  on_ boolean;
  ov record;
  has_schedule boolean := false;
  home jsonb;
begin
  if p_platform not in ('android', 'ios', 'tv') then
    raise exception 'unknown platform' using errcode = '22023';
  end if;

  select * into cv from public.config_versions order by version desc limit 1;
  if cv.version is null then
    return jsonb_build_object('version', 0, 'unchanged', false);
  end if;
  snap := cv.snapshot;

  if uid is not null then
    select coalesce(p.country, v_country), not p.is_guest
      into v_country, signed_in
      from public.profiles p where p.id = uid;
  end if;

  -- Anything time-, user- or country-dependent makes a cached copy unsafe to reuse.
  has_schedule :=
       exists (select 1 from jsonb_array_elements(snap -> 'flags') x
               where x ->> 'from' is not null or x ->> 'to' is not null)
    or jsonb_array_length(snap -> 'maintenance') > 0
    or exists (select 1 from jsonb_array_elements(snap -> 'home' -> 'sections') x
               where x ->> 'from' is not null or x ->> 'to' is not null
                  or x -> 'countries' <> 'null'::jsonb or (x ->> 'login')::boolean)
    or exists (select 1 from jsonb_array_elements(snap -> 'home' -> 'banners') x
               where x ->> 'from' is not null or x ->> 'to' is not null
                  or x -> 'countries' <> 'null'::jsonb or (x ->> 'login')::boolean);

  if p_known_version = cv.version and not has_schedule and uid is null then
    return jsonb_build_object('version', cv.version, 'unchanged', true);
  end if;

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

  if uid is not null then
    for ov in
      select o.flag_key, o.enabled
      from public.feature_overrides o
      where ((o.target_type = 'country' and o.target_value = v_country)
          or (o.target_type = 'user' and o.target_value = uid::text))
        and (o.starts_at is null or o.starts_at <= now_ts)
        and (o.ends_at is null or o.ends_at > now_ts)
        and flags ? o.flag_key
      order by case o.target_type when 'country' then 1 else 2 end
    loop
      flags := flags || jsonb_build_object(ov.flag_key, ov.enabled);
    end loop;
  end if;

  home := jsonb_build_object(
    'sections', coalesce((
      select jsonb_agg(x - 'platforms' - 'countries' - 'from' - 'to')
      from jsonb_array_elements(snap -> 'home' -> 'sections') x
      where public.config_item_visible(x, p_platform, v_country, signed_in, now_ts)), '[]'::jsonb),
    'banners', coalesce((
      select jsonb_agg(x - 'platforms' - 'countries' - 'from' - 'to')
      from jsonb_array_elements(snap -> 'home' -> 'banners') x
      where public.config_item_visible(x, p_platform, v_country, signed_in, now_ts)), '[]'::jsonb),
    'top10', coalesce((
      select jsonb_agg(x)
      from jsonb_array_elements(snap -> 'home' -> 'top10') x
      where x ->> 'country' is null or x ->> 'country' = v_country), '[]'::jsonb)
  );

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
    'theme', snap -> 'theme',
    'home', home
  );
end;
$$;
revoke all on function public.get_app_config(text, text, bigint, text) from public;
grant execute on function public.get_app_config(text, text, bigint, text) to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Default home (mirrors today's app rails; admin edits/reorders it)
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.top10_lists (id, title, content_kind, source) values
  ('00000000-0000-0000-0000-00000000a010', 'Top 10 this week', 'mixed', 'tmdb_trending');

insert into public.home_sections (title, section_type, content_kind, source, layout, item_limit, sort_order, requires_login, params, top10_list_id) values
  ('Featured',            'hero_banners',      'mixed',  'manual',        'hero',      8,  10, false, '{}', null),
  ('Continue watching',   'continue_watching', 'mixed',  'auto',          'wide_rail', 20, 20, false, '{}', null),
  ('Top 10 this week',    'top10',             'mixed',  'tmdb_trending', 'ranked',    10, 30, false, '{}', '00000000-0000-0000-0000-00000000a010'),
  ('Live now',            'live_now',          'live',   'auto',          'rail',      20, 40, false, '{}', null),
  ('New movies',          'new_releases',      'movie',  'auto',          'rail',      20, 50, false, '{"days":30}', null),
  ('Recently added',      'recently_added',    'mixed',  'auto',          'rail',      20, 60, false, '{}', null),
  ('Trending series',     'trending',          'series', 'tmdb_trending', 'rail',      20, 70, false, '{}', null),
  ('Matches',             'matches_upcoming',  'live',   'auto',          'cards',     10, 80, false, '{}', null),
  ('Picked for you',      'recommended',       'mixed',  'random',        'rail',      20, 90, false, '{}', null),
  ('My favorites',        'favorites',         'mixed',  'auto',          'rail',      20, 100, false, '{}', null);

-- Audit after defaults.
do $$
declare
  t text;
begin
  foreach t in array array['home_sections', 'home_section_items', 'banners',
                           'top10_lists', 'top10_items'] loop
    execute format('create trigger %1$s_audit after insert or update or delete on public.%1$I
                     for each row execute function public.audit_row_change()', t);
  end loop;
end;
$$;

-- Publish v2 with the default home.
insert into public.config_versions (snapshot, notes)
values (public.build_app_config_snapshot(), 'Default home layout');
