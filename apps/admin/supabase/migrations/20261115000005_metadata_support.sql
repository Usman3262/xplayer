-- 006 · Support for the metadata-tmdb Edge Function

-- Titles TMDB could not match, so we don't ask TMDB again for a while.
create table public.metadata_misses (
  kind        text not null check (kind in ('movie', 'series')),
  title_norm  text not null,
  year        int not null default 0,          -- 0 = unknown
  checked_at  timestamptz not null default now(),
  primary key (kind, title_norm, year)
);
create index metadata_misses_checked_idx on public.metadata_misses (checked_at);

-- Last runs of scheduled metadata jobs (trending lists etc.).
create table public.metadata_sync_state (
  job             text primary key,
  last_run_at     timestamptz,
  last_result     jsonb,
  last_error      text
);

-- Server-cached TMDB lists used by home sections with source tmdb_trending /
-- tmdb_popular / tmdb_top_rated. Small; apps read them directly.
create table public.metadata_lists (
  key         text primary key check (key ~ '^(trending|popular|top_rated)_(movie|series)$'),
  items       jsonb not null default '[]'::jsonb check (jsonb_typeof(items) = 'array'),  -- [{"tmdb":1,"kind":"movie"}]
  updated_at  timestamptz not null default now()
);
alter table public.metadata_lists enable row level security;
revoke insert, update, delete on public.metadata_lists from anon, authenticated;
create policy metadata_lists_read on public.metadata_lists
  for select to anon, authenticated using (true);

alter table public.metadata_misses enable row level security;
alter table public.metadata_sync_state enable row level security;
revoke all on public.metadata_misses, public.metadata_sync_state from anon;
revoke insert, update, delete on public.metadata_misses, public.metadata_sync_state from authenticated;
create policy metadata_misses_read on public.metadata_misses
  for select to authenticated using ((select public.has_permission('catalog.read')));
create policy metadata_sync_state_read on public.metadata_sync_state
  for select to authenticated using ((select public.has_permission('catalog.read')));

-- Settings the apps need to show TMDB artwork (paths are stored, not full URLs).
insert into public.app_settings (key, category, value_type, value, default_value, validation, description) values
  ('metadata.image_base_url', 'metadata', 'url', '"https://image.tmdb.org/t/p"', '"https://image.tmdb.org/t/p"', '{}',
   'Base URL for artwork paths (size is appended, e.g. /w342/abc.jpg)'),
  ('metadata.poster_size', 'metadata', 'enum', '"w342"', '"w342"', '{"options":["w185","w342","w500","w780","original"]}',
   'Poster size the apps request'),
  ('metadata.backdrop_size', 'metadata', 'enum', '"w1280"', '"w1280"', '{"options":["w780","w1280","original"]}',
   'Backdrop size the apps request'),
  ('metadata.language', 'metadata', 'string', '"en-US"', '"en-US"', '{}',
   'Language for titles and overviews fetched from TMDB'),
  ('metadata.miss_retry_days', 'metadata', 'int', '7', '7', '{"min":1,"max":90}',
   'Days before an unmatched title is looked up again');

-- Server-side only.
update public.app_settings set is_public = false where key = 'metadata.miss_retry_days';

insert into public.config_versions (snapshot, notes)
values (public.build_app_config_snapshot(), 'Metadata settings');
