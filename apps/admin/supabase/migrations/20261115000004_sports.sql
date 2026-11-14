-- 005 · Sports: competitions, teams, matches, lineups, events, standings
--
-- Provider-neutral: every synced row keeps (external_source, external_id) so any
-- sports API can fill it (sync job = Edge Function with the service role, Phase 3.9).
-- Admins can also add/edit by hand. Apps read through two RPCs:
--   get_matches(...)  → compact list for rails / match centre
--   get_match(id)     → one match with lineups, events, channels
-- Which channel shows a match is linked to the global channel catalog and/or a
-- channel-name match the app resolves against the user's own panel.

create table public.sports_competitions (
  id               uuid primary key default gen_random_uuid(),
  sport            text not null default 'football'
                     check (sport in ('football', 'cricket', 'basketball', 'tennis',
                                      'hockey', 'rugby', 'baseball', 'motorsport', 'other')),
  name             text not null,
  short_name       text,
  country          text check (country ~ '^[A-Z]{2}$'),
  logo_url         text,
  season           text,
  is_enabled       boolean not null default true,
  is_featured      boolean not null default false,
  sort_order       int not null default 0,
  external_source  text,
  external_id      text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (external_source, external_id)
);

create table public.sports_teams (
  id               uuid primary key default gen_random_uuid(),
  sport            text not null default 'football',
  name             text not null,
  short_name       text,
  logo_url         text,
  country          text check (country ~ '^[A-Z]{2}$'),
  external_source  text,
  external_id      text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (external_source, external_id)
);
create index sports_teams_name_idx on public.sports_teams (lower(name));

create table public.sports_matches (
  id               uuid primary key default gen_random_uuid(),
  competition_id   uuid references public.sports_competitions (id) on delete set null,
  sport            text not null default 'football',
  home_team_id     uuid not null references public.sports_teams (id) on delete restrict,
  away_team_id     uuid not null references public.sports_teams (id) on delete restrict,
  kickoff_at       timestamptz not null,
  status           text not null default 'scheduled'
                     check (status in ('scheduled', 'live', 'halftime', 'finished',
                                       'postponed', 'cancelled', 'suspended')),
  minute           int check (minute between 0 and 200),
  home_score       int check (home_score >= 0),
  away_score       int check (away_score >= 0),
  round            text,
  venue            text,
  is_featured      boolean not null default false,
  is_hidden        boolean not null default false,
  external_source  text,
  external_id      text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (external_source, external_id),
  check (home_team_id <> away_team_id)
);
create index sports_matches_kickoff_idx on public.sports_matches (kickoff_at) where not is_hidden;
create index sports_matches_live_idx on public.sports_matches (status) where status in ('live', 'halftime');
create index sports_matches_comp_idx on public.sports_matches (competition_id, kickoff_at);

-- Lineups: player lists vary a lot by sport/API → JSONB.
-- players: [{"name","number","position","starter":true,"grid":"1:1"}]
create table public.sports_lineups (
  match_id    uuid not null references public.sports_matches (id) on delete cascade,
  team_id     uuid not null references public.sports_teams (id) on delete cascade,
  formation   text,
  coach       text,
  players     jsonb not null default '[]'::jsonb check (jsonb_typeof(players) = 'array'),
  updated_at  timestamptz not null default now(),
  primary key (match_id, team_id)
);

create table public.sports_events (
  id            uuid primary key default gen_random_uuid(),
  match_id      uuid not null references public.sports_matches (id) on delete cascade,
  team_id       uuid references public.sports_teams (id) on delete set null,
  minute        int not null check (minute between 0 and 200),
  extra_minute  int,
  type          text not null check (type in ('goal', 'own_goal', 'penalty_goal',
                  'penalty_miss', 'yellow', 'red', 'substitution', 'var', 'other')),
  player        text,
  assist        text,
  detail        text,
  created_at    timestamptz not null default now()
);
create index sports_events_match_idx on public.sports_events (match_id, minute, extra_minute);

create table public.sports_standings (
  competition_id  uuid not null references public.sports_competitions (id) on delete cascade,
  group_name      text not null default '',
  team_id         uuid not null references public.sports_teams (id) on delete cascade,
  rank            int not null,
  played          int not null default 0,
  won             int not null default 0,
  drawn           int not null default 0,
  lost            int not null default 0,
  goals_for       int not null default 0,
  goals_against   int not null default 0,
  points          int not null default 0,
  form            text,
  updated_at      timestamptz not null default now(),
  primary key (competition_id, group_name, team_id)
);
create index sports_standings_rank_idx on public.sports_standings (competition_id, group_name, rank);

-- Where to watch: a global channel and/or a name the app matches in the user's panel.
create table public.sports_match_channels (
  id             uuid primary key default gen_random_uuid(),
  match_id       uuid not null references public.sports_matches (id) on delete cascade,
  channel_id     uuid references public.global_channels (id) on delete set null,
  channel_match  text,                 -- e.g. "beIN Sports 1"
  country        text check (country ~ '^[A-Z]{2}$'),
  note           text,
  check (channel_id is not null or channel_match is not null)
);
create index sports_match_channels_match_idx on public.sports_match_channels (match_id);

-- Sync bookkeeping for the sports API job (server only).
create table public.sports_sync_state (
  source          text not null,
  resource        text not null,      -- fixtures / live / lineups / standings …
  cursor          jsonb not null default '{}'::jsonb,
  last_synced_at  timestamptz,
  last_error      text,
  primary key (source, resource)
);

do $$
declare
  t text;
begin
  foreach t in array array['sports_competitions', 'sports_teams', 'sports_matches',
                           'sports_lineups', 'sports_standings'] loop
    execute format('create trigger %1$s_set_updated_at before update on public.%1$I
                     for each row execute function public.set_updated_at()', t);
  end loop;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS: apps read visible sports data; sports.write edits; sync job = service role.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  t text;
  pub text;
begin
  foreach t in array array['sports_competitions', 'sports_teams', 'sports_matches',
    'sports_lineups', 'sports_events', 'sports_standings', 'sports_match_channels'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke insert, update, delete on public.%I from anon', t);
    pub := case t
      when 'sports_competitions' then 'is_enabled'
      when 'sports_matches' then 'not is_hidden'
      when 'sports_teams' then 'true'
      when 'sports_standings' then
        'exists (select 1 from public.sports_competitions c where c.id = competition_id and c.is_enabled)'
      else 'exists (select 1 from public.sports_matches m where m.id = match_id and not m.is_hidden)'
    end;
    execute format('create policy %1$s_read on public.%1$I for select to anon, authenticated
                     using (%2$s or (select public.has_permission(''sports.read'')))', t, pub);
    execute format($p$create policy %1$s_insert on public.%1$I for insert to authenticated
                     with check ((select public.has_permission('sports.write')))$p$, t);
    execute format($p$create policy %1$s_update on public.%1$I for update to authenticated
                     using ((select public.has_permission('sports.write')))
                     with check ((select public.has_permission('sports.write')))$p$, t);
    execute format($p$create policy %1$s_delete on public.%1$I for delete to authenticated
                     using ((select public.has_permission('sports.write')))$p$, t);
    execute format('create trigger %1$s_audit after insert or update or delete on public.%1$I
                     for each row execute function public.audit_row_change()', t);
  end loop;
end;
$$;

alter table public.sports_sync_state enable row level security;
revoke all on public.sports_sync_state from anon;
revoke insert, update, delete on public.sports_sync_state from authenticated;
create policy sports_sync_state_read on public.sports_sync_state
  for select to authenticated using ((select public.has_permission('sports.read')));

-- ─────────────────────────────────────────────────────────────────────────────
-- App RPCs (one call per screen)
-- ─────────────────────────────────────────────────────────────────────────────

-- Compact match list. p_window: 'live' | 'upcoming' | 'recent' | 'today' | 'all'.
create or replace function public.get_matches(
  p_window text default 'upcoming',
  p_competition uuid default null,
  p_featured_only boolean default false,
  p_limit int default 20
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(row_to_json(x)::jsonb - 'sort_key' order by x.sort_key), '[]'::jsonb)
  from (
    select
      m.id, m.status, m.minute, m.kickoff_at, m.round, m.is_featured,
      m.home_score, m.away_score,
      jsonb_build_object('id', c.id, 'name', coalesce(c.short_name, c.name), 'logo', c.logo_url) as competition,
      jsonb_build_object('id', h.id, 'name', coalesce(h.short_name, h.name), 'logo', h.logo_url) as home,
      jsonb_build_object('id', a.id, 'name', coalesce(a.short_name, a.name), 'logo', a.logo_url) as away,
      (select count(*) > 0 from public.sports_match_channels mc where mc.match_id = m.id) as has_channels,
      case when p_window = 'recent' then -extract(epoch from m.kickoff_at)
           else extract(epoch from m.kickoff_at) end as sort_key
    from public.sports_matches m
    join public.sports_teams h on h.id = m.home_team_id
    join public.sports_teams a on a.id = m.away_team_id
    left join public.sports_competitions c on c.id = m.competition_id
    where not m.is_hidden
      and (c.id is null or c.is_enabled)
      and (p_competition is null or m.competition_id = p_competition)
      and (not p_featured_only or m.is_featured)
      and case p_window
        when 'live' then m.status in ('live', 'halftime')
        when 'upcoming' then m.status = 'scheduled' and m.kickoff_at > now() - interval '15 minutes'
        when 'recent' then m.status = 'finished' and m.kickoff_at > now() - interval '7 days'
        when 'today' then m.kickoff_at >= date_trunc('day', now())
                      and m.kickoff_at < date_trunc('day', now()) + interval '1 day'
        else true end
    order by sort_key
    limit least(greatest(p_limit, 1), 100)
  ) x;
$$;

-- Full match page: match + lineups + events + where to watch.
create or replace function public.get_match(p_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'match', to_jsonb(m) - 'external_source' - 'external_id' - 'created_at',
    'competition', (select to_jsonb(c) - 'external_source' - 'external_id'
                    from public.sports_competitions c where c.id = m.competition_id),
    'home', (select jsonb_build_object('id', t.id, 'name', t.name, 'short', t.short_name, 'logo', t.logo_url)
             from public.sports_teams t where t.id = m.home_team_id),
    'away', (select jsonb_build_object('id', t.id, 'name', t.name, 'short', t.short_name, 'logo', t.logo_url)
             from public.sports_teams t where t.id = m.away_team_id),
    'lineups', coalesce((select jsonb_agg(jsonb_build_object(
                 'team', l.team_id, 'formation', l.formation, 'coach', l.coach, 'players', l.players))
               from public.sports_lineups l where l.match_id = m.id), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object(
                'minute', e.minute, 'extra', e.extra_minute, 'type', e.type, 'team', e.team_id,
                'player', e.player, 'assist', e.assist, 'detail', e.detail)
                order by e.minute, e.extra_minute nulls first, e.created_at)
              from public.sports_events e where e.match_id = m.id), '[]'::jsonb),
    'channels', coalesce((select jsonb_agg(jsonb_build_object(
                  'channel', mc.channel_id, 'match', mc.channel_match,
                  'country', mc.country, 'note', mc.note,
                  'name', gc.name, 'logo', gc.logo_url, 'epg', gc.epg_channel_id))
                from public.sports_match_channels mc
                left join public.global_channels gc on gc.id = mc.channel_id
                where mc.match_id = m.id), '[]'::jsonb)
  )
  from public.sports_matches m
  where m.id = p_id;
$$;

revoke all on function public.get_matches(text, uuid, boolean, int) from public;
revoke all on function public.get_match(uuid) from public;
grant execute on function public.get_matches(text, uuid, boolean, int) to anon, authenticated;
grant execute on function public.get_match(uuid) to anon, authenticated;
