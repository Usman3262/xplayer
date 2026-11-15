-- Phase 7.8: what the phone match centre needs, one round trip per screen.
--   get_matches_between: one day of matches in the user's own time zone
--                        (the app passes the day's start / end instants).
--   get_standings:       a competition's league table.
-- Both are SECURITY INVOKER: the sports tables' RLS (public read of
-- enabled / not hidden rows) applies. No new tables.

create or replace function public.get_matches_between(
  p_from timestamptz,
  p_to timestamptz,
  p_limit int default 100
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.kickoff_at, x.id), '[]'::jsonb)
  from (
    select
      m.id, m.status, m.minute, m.kickoff_at, m.round, m.venue, m.is_featured,
      m.home_score, m.away_score,
      jsonb_build_object('id', c.id, 'name', c.name, 'short', c.short_name,
                         'country', c.country, 'logo', c.logo_url) as competition,
      jsonb_build_object('id', h.id, 'name', h.name, 'short', h.short_name, 'logo', h.logo_url) as home,
      jsonb_build_object('id', a.id, 'name', a.name, 'short', a.short_name, 'logo', a.logo_url) as away,
      coalesce((select jsonb_agg(coalesce(gc.name, mc.channel_match))
                from public.sports_match_channels mc
                left join public.global_channels gc on gc.id = mc.channel_id
                where mc.match_id = m.id), '[]'::jsonb) as channels
    from public.sports_matches m
    join public.sports_teams h on h.id = m.home_team_id
    join public.sports_teams a on a.id = m.away_team_id
    left join public.sports_competitions c on c.id = m.competition_id
    where not m.is_hidden
      and (c.id is null or c.is_enabled)
      and m.kickoff_at >= p_from
      and m.kickoff_at < p_to
      and p_to > p_from
      and p_to - p_from <= interval '3 days'
    order by m.kickoff_at, m.id
    limit least(greatest(p_limit, 1), 200)
  ) x;
$$;

create or replace function public.get_standings(p_competition uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'competition', (select jsonb_build_object('id', c.id, 'name', c.name, 'short', c.short_name,
                                              'country', c.country, 'logo', c.logo_url, 'season', c.season)
                    from public.sports_competitions c where c.id = p_competition and c.is_enabled),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
                'group', s.group_name, 'rank', s.rank, 'played', s.played, 'won', s.won,
                'drawn', s.drawn, 'lost', s.lost, 'gf', s.goals_for, 'ga', s.goals_against,
                'points', s.points, 'form', s.form,
                'team', jsonb_build_object('id', t.id, 'name', t.name, 'short', t.short_name, 'logo', t.logo_url))
                order by s.group_name, s.rank)
              from public.sports_standings s
              join public.sports_teams t on t.id = s.team_id
              where s.competition_id = p_competition), '[]'::jsonb)
  );
$$;

-- Hot query: matches of one day (kickoff range) — sports_matches_kickoff_idx
-- (kickoff_at where not is_hidden) already covers it; standings use
-- sports_standings_rank_idx (competition_id, group_name, rank).

revoke all on function public.get_matches_between(timestamptz, timestamptz, int) from public;
revoke all on function public.get_standings(uuid) from public;
grant execute on function public.get_matches_between(timestamptz, timestamptz, int) to anon, authenticated;
grant execute on function public.get_standings(uuid) to anon, authenticated;
