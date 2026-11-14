-- 004 · Global catalog (canonical metadata shared by all users)
--
-- One row per real-world movie / series / season / episode / channel, filled by
-- the `metadata-tmdb` Edge Function (service role) and editable by admins.
-- `locked_fields` = fields an admin edited; automatic refreshes never overwrite them.
-- Per-user availability (which panel has which title) is NOT stored here — that
-- lives on the device / in user tables (Phase 6).
--
-- Apps (anon or signed in) may READ published rows; only admins/server write.

create extension if not exists pg_trgm with schema extensions;

-- Audit only real admin actions (skip migrations and service-role jobs).
create or replace function public.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  pk text;
begin
  if (select auth.uid()) is null then
    return coalesce(new, old);
  end if;
  pk := coalesce(
    to_jsonb(coalesce(new, old)) ->> 'id',
    to_jsonb(coalesce(new, old)) ->> 'key',
    to_jsonb(coalesce(new, old)) ->> 'platform'
  );
  insert into public.audit_logs (actor_id, action, entity, entity_id, before, after)
  values (
    (select auth.uid()), lower(tg_op), tg_table_name, pk,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$$;
revoke all on function public.audit_row_change() from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Lookups
-- ─────────────────────────────────────────────────────────────────────────────
create table public.genres (
  id        int generated always as identity primary key,
  tmdb_id   int unique,
  name      text not null,
  slug      text not null unique check (slug ~ '^[a-z0-9-]+$')
);

create table public.countries (
  code  text primary key check (code ~ '^[A-Z]{2}$'),
  name  text not null
);

create table public.languages (
  code  text primary key check (code ~ '^[a-z]{2,3}$'),
  name  text not null
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Movies
-- ─────────────────────────────────────────────────────────────────────────────
create table public.global_movies (
  id                 uuid primary key default gen_random_uuid(),
  tmdb_id            int unique,
  imdb_id            text unique check (imdb_id ~ '^tt[0-9]+$'),
  title              text not null,
  title_norm         text generated always as (lower(title)) stored,
  original_title     text,
  original_language  text,
  overview           text,
  tagline            text,
  release_date       date,
  year               int generated always as (extract(year from release_date)::int) stored,
  runtime_min        int check (runtime_min between 0 and 1000),
  certification      text,                -- age rating (e.g. PG-13)
  poster_path        text,                -- TMDB path ("/abc.jpg") or full https URL
  backdrop_path      text,
  logo_path          text,
  trailer_youtube    text,                -- YouTube video key
  rating             numeric(3, 1) check (rating between 0 and 10),
  vote_count         int,
  popularity         numeric,
  credits            jsonb not null default '{}'::jsonb,  -- {"cast":[{name,character,profile}],"directors":[..]}
  countries          text[],                              -- ISO-2
  adult              boolean not null default false,
  is_published       boolean not null default true,
  locked_fields      text[] not null default '{}',
  metadata_source    text not null default 'tmdb' check (metadata_source in ('tmdb', 'admin', 'provider')),
  fetched_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index global_movies_title_trgm on public.global_movies using gin (title_norm extensions.gin_trgm_ops);
create index global_movies_popular_idx on public.global_movies (popularity desc nulls last) where is_published;
create index global_movies_release_idx on public.global_movies (release_date desc nulls last) where is_published;
create index global_movies_title_year_idx on public.global_movies (title_norm, year);

create table public.movie_genres (
  movie_id  uuid not null references public.global_movies (id) on delete cascade,
  genre_id  int not null references public.genres (id) on delete cascade,
  primary key (movie_id, genre_id)
);
create index movie_genres_genre_idx on public.movie_genres (genre_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Series / seasons / episodes
-- ─────────────────────────────────────────────────────────────────────────────
create table public.global_series (
  id                 uuid primary key default gen_random_uuid(),
  tmdb_id            int unique,
  imdb_id            text unique check (imdb_id ~ '^tt[0-9]+$'),
  title              text not null,
  title_norm         text generated always as (lower(title)) stored,
  original_title     text,
  original_language  text,
  overview           text,
  first_air_date     date,
  last_air_date      date,
  year               int generated always as (extract(year from first_air_date)::int) stored,
  status             text,                -- Returning Series / Ended / …
  season_count       int,
  episode_count      int,
  certification      text,
  poster_path        text,
  backdrop_path      text,
  logo_path          text,
  trailer_youtube    text,
  rating             numeric(3, 1) check (rating between 0 and 10),
  vote_count         int,
  popularity         numeric,
  credits            jsonb not null default '{}'::jsonb,
  countries          text[],
  adult              boolean not null default false,
  is_published       boolean not null default true,
  locked_fields      text[] not null default '{}',
  metadata_source    text not null default 'tmdb' check (metadata_source in ('tmdb', 'admin', 'provider')),
  fetched_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index global_series_title_trgm on public.global_series using gin (title_norm extensions.gin_trgm_ops);
create index global_series_popular_idx on public.global_series (popularity desc nulls last) where is_published;
create index global_series_air_idx on public.global_series (first_air_date desc nulls last) where is_published;
create index global_series_title_year_idx on public.global_series (title_norm, year);

create table public.series_genres (
  series_id  uuid not null references public.global_series (id) on delete cascade,
  genre_id   int not null references public.genres (id) on delete cascade,
  primary key (series_id, genre_id)
);
create index series_genres_genre_idx on public.series_genres (genre_id);

create table public.global_seasons (
  id             uuid primary key default gen_random_uuid(),
  series_id      uuid not null references public.global_series (id) on delete cascade,
  season_number  int not null check (season_number >= 0),
  name           text,
  overview       text,
  poster_path    text,
  air_date       date,
  episode_count  int,
  locked_fields  text[] not null default '{}',
  updated_at     timestamptz not null default now(),
  unique (series_id, season_number)
);

create table public.global_episodes (
  id              uuid primary key default gen_random_uuid(),
  series_id       uuid not null references public.global_series (id) on delete cascade,
  season_id       uuid references public.global_seasons (id) on delete cascade,
  season_number   int not null check (season_number >= 0),
  episode_number  int not null check (episode_number >= 0),
  name            text,
  overview        text,
  still_path      text,
  air_date        date,
  runtime_min     int check (runtime_min between 0 and 1000),
  locked_fields   text[] not null default '{}',
  updated_at      timestamptz not null default now(),
  unique (series_id, season_number, episode_number)
);
create index global_episodes_season_idx on public.global_episodes (season_id);
create index global_episodes_air_idx on public.global_episodes (air_date desc nulls last);

-- ─────────────────────────────────────────────────────────────────────────────
-- Channels (canonical logos / EPG ids / categories)
-- ─────────────────────────────────────────────────────────────────────────────
create table public.global_channels (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  name_norm       text generated always as (lower(name)) stored,
  aliases         text[] not null default '{}',   -- other names panels use ("BBC One HD", "UK: BBC 1")
  logo_url        text,
  country         text check (country ~ '^[A-Z]{2}$'),
  language        text,
  category        text,
  epg_channel_id  text,                            -- XMLTV id (tvg-id)
  quality         text check (quality in ('sd', 'hd', 'fhd', 'uhd')),
  is_published    boolean not null default true,
  locked_fields   text[] not null default '{}',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index global_channels_name_trgm on public.global_channels using gin (name_norm extensions.gin_trgm_ops);
create index global_channels_epg_idx on public.global_channels (epg_channel_id);
create index global_channels_aliases_idx on public.global_channels using gin (aliases);

-- updated_at triggers
do $$
declare
  t text;
begin
  foreach t in array array['global_movies', 'global_series', 'global_seasons',
                           'global_episodes', 'global_channels'] loop
    execute format('create trigger %1$s_set_updated_at before update on public.%1$I
                     for each row execute function public.set_updated_at()', t);
  end loop;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS: apps read published rows; admins with catalog.* read/write everything.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  t text;
  pub text;
begin
  foreach t in array array['genres', 'countries', 'languages', 'global_movies',
    'movie_genres', 'global_series', 'series_genres', 'global_seasons',
    'global_episodes', 'global_channels'] loop
    execute format('alter table public.%I enable row level security', t);
    -- Clients can only read; writes go through admin policies below or the service role.
    execute format('revoke insert, update, delete on public.%I from anon', t);

    pub := case
      when t in ('global_movies', 'global_series', 'global_channels') then 'is_published'
      when t = 'movie_genres' then
        'exists (select 1 from public.global_movies m where m.id = movie_id and m.is_published)'
      when t = 'series_genres' or t in ('global_seasons', 'global_episodes') then
        'exists (select 1 from public.global_series s where s.id = series_id and s.is_published)'
      else 'true' end;

    execute format('create policy %1$s_read on public.%1$I for select to anon, authenticated
                     using (%2$s or (select public.has_permission(''catalog.read'')))', t, pub);
    execute format($p$create policy %1$s_insert on public.%1$I for insert to authenticated
                     with check ((select public.has_permission('catalog.write')))$p$, t);
    execute format($p$create policy %1$s_update on public.%1$I for update to authenticated
                     using ((select public.has_permission('catalog.write')))
                     with check ((select public.has_permission('catalog.write')))$p$, t);
    execute format($p$create policy %1$s_delete on public.%1$I for delete to authenticated
                     using ((select public.has_permission('catalog.write')))$p$, t);
    execute format('create trigger %1$s_audit after insert or update or delete on public.%1$I
                     for each row execute function public.audit_row_change()', t);
  end loop;
end;
$$;

-- has_permission() must be callable inside anon policies (returns false for anon).
grant execute on function public.has_permission(text) to anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- Search (typo-tolerant, trigram). Apps call this; results are published rows.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.search_catalog(
  q text,
  kinds text[] default array['movie', 'series', 'live'],
  max_results int default 30
)
returns table (kind text, id uuid, title text, year int, image text, score real)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  with term as (select lower(trim(q)) as t),
  hits as (
    select 'movie'::text as kind, m.id, m.title, m.year, m.poster_path as image,
           similarity(m.title_norm, term.t) as score, m.popularity
    from public.global_movies m, term
    where 'movie' = any(kinds) and m.is_published
      and (m.title_norm % term.t or m.title_norm like term.t || '%')
    union all
    select 'series', s.id, s.title, s.year, s.poster_path,
           similarity(s.title_norm, term.t), s.popularity
    from public.global_series s, term
    where 'series' = any(kinds) and s.is_published
      and (s.title_norm % term.t or s.title_norm like term.t || '%')
    union all
    select 'live', c.id, c.name, null::int, c.logo_url,
           similarity(c.name_norm, term.t), null::numeric
    from public.global_channels c, term
    where 'live' = any(kinds) and c.is_published
      and (c.name_norm % term.t or c.name_norm like term.t || '%')
  )
  select kind, id, title, year, image, score
  from hits
  where char_length((select t from term)) >= 2
  order by score desc, popularity desc nulls last
  limit least(greatest(max_results, 1), 50);
$$;
revoke all on function public.search_catalog(text, text[], int) from public;
grant execute on function public.search_catalog(text, text[], int) to anon, authenticated;
