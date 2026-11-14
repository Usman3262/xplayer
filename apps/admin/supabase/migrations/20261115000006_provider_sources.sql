-- 007 · Rails and Top 10 come from the user's PANEL (Neo/Xtream/M3U/Stalker), not TMDB lists.
--
-- Panels have huge catalogs (e.g. Neo ≈ 60k movies + 70k series). They are never
-- imported into Supabase: the app caches the panel catalog on the device and
-- computes rails from it. TMDB is used ONLY for metadata, fetched on demand
-- (metadata-tmdb `resolve`) and cached in the global catalog.
--
-- Section / Top 10 sources:
--   auto              app logic for the section type (continue watching, favorites, live now…)
--   provider_added    newest items in the user's panel (panel "added" date)   params: {"days":30}
--   provider_rating   best-rated items in the user's panel                    params: {"days":90,"min_rating":6}
--   provider_category a panel category/group by name                          params: {"match":"Netflix"}
--   manual            items an admin picked (from a reference panel account, Phase 3)
--   random            random items from the user's panel
--   watch_stats       most watched by XPlayer users (needs analytics, Phase 10)

-- Drop a CHECK constraint by a fragment of its definition (auto-generated names vary).
create or replace function pg_temp.drop_check(p_table text, p_fragment text)
returns void
language plpgsql
as $$
declare
  c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = ('public.' || p_table)::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%' || p_fragment || '%'
  loop
    execute format('alter table public.%I drop constraint %I', p_table, c.conname);
  end loop;
end;
$$;

-- ── home_sections.source ─────────────────────────────────────────────────────
select pg_temp.drop_check('home_sections', 'tmdb_trending');
update public.home_sections set source = 'provider_rating', params = '{"days":90}'
  where section_type = 'top10';
update public.home_sections set source = 'provider_added', title = 'New series',
       section_type = 'new_releases', params = '{"days":30}'
  where source in ('tmdb_trending', 'tmdb_popular', 'tmdb_top_rated');
alter table public.home_sections add constraint home_sections_source_check check (source in (
  'auto', 'provider_added', 'provider_rating', 'provider_category', 'manual', 'random', 'watch_stats'));

-- ── Top 10 lists ─────────────────────────────────────────────────────────────
select pg_temp.drop_check('top10_lists', 'tmdb_trending');
alter table public.top10_lists add column params jsonb not null default '{}'::jsonb
  check (jsonb_typeof(params) = 'object');
update public.top10_lists set source = 'provider_rating', params = '{"days":90}'
  where source = 'tmdb_trending';
alter table public.top10_lists add constraint top10_lists_source_check check (source in (
  'manual', 'provider_added', 'provider_rating', 'watch_stats'));
delete from public.top10_items;  -- old TMDB-trending picks

-- ── Panel item references for admin picks ────────────────────────────────────
-- When admin picks from a reference panel (same provider as users, e.g. Neo),
-- the panel's own id lets the app match exactly; tmdb_id / title stay as fallback.
alter table public.home_section_items
  add column panel_item_id text,
  add column panel_key text;          -- which provider family the id belongs to (e.g. 'neo')
select pg_temp.drop_check('home_section_items', 'deep_link');
alter table public.home_section_items add constraint home_section_items_ref_check check (
  item_kind = 'link' and deep_link is not null
  or item_kind <> 'link' and (tmdb_id is not null or match_title is not null or panel_item_id is not null));

alter table public.top10_items
  add column panel_item_id text,
  add column panel_key text;
select pg_temp.drop_check('top10_items', 'match_title');
alter table public.top10_items add constraint top10_items_ref_check
  check (tmdb_id is not null or match_title is not null or panel_item_id is not null);

alter table public.banners
  add column panel_item_id text,
  add column panel_key text;
select pg_temp.drop_check('banners', '''content''::text');
alter table public.banners add constraint banners_content_ref_check
  check (action_type <> 'content' or tmdb_id is not null or panel_item_id is not null);

-- ── TMDB lists are not used ──────────────────────────────────────────────────
drop table public.metadata_lists;
delete from public.metadata_sync_state where job = 'lists';

-- ── Snapshot: include the new fields ─────────────────────────────────────────
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
            'kind', i.item_kind, 'panel', i.panel_key, 'panel_id', i.panel_item_id,
            'tmdb', i.tmdb_id, 'match', i.match_title,
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
        'panel', b.panel_key, 'panel_id', b.panel_item_id,
        'platforms', b.platforms, 'countries', b.countries,
        'login', b.requires_login, 'from', b.starts_at, 'to', b.ends_at)
        order by b.sort_order, b.created_at)
      from public.banners b
      where b.is_enabled and (b.ends_at is null or b.ends_at > now())), '[]'::jsonb),
    'top10', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'title', l.title, 'kind', l.content_kind, 'source', l.source,
        'params', l.params, 'country', l.country,
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'rank', t.rank, 'kind', t.item_kind, 'panel', t.panel_key,
            'panel_id', t.panel_item_id, 'tmdb', t.tmdb_id,
            'match', t.match_title, 'title', t.title, 'image', t.image_url)
            order by t.rank)
          from public.top10_items t where t.list_id = l.id), '[]'::jsonb)))
      from public.top10_lists l where l.is_enabled), '[]'::jsonb)
  );
$$;
revoke all on function public.build_home_snapshot() from public, anon, authenticated;

insert into public.config_versions (snapshot, notes)
values (public.build_app_config_snapshot(), 'Rails/Top 10 from the user''s panel, not TMDB');
