-- 012 · Dashboard: weekly sign-ups for the chart.
create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not public.has_permission('dashboard.read') then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'users', jsonb_build_object(
      'total',      (select count(*) from public.profiles where not is_guest),
      'guests',     (select count(*) from public.profiles where is_guest),
      'new_7d',     (select count(*) from public.profiles where created_at > now() - interval '7 days'),
      'active_7d',  (select count(*) from public.profiles where last_seen_at > now() - interval '7 days'),
      'suspended',  (select count(*) from public.profiles where status <> 'active'),
      'admins',     (select count(distinct user_id) from public.admin_user_roles where is_active)
    ),
    -- New sign-ups per week, oldest first (last 6 weeks incl. this one).
    'signups_weekly', (
      select jsonb_agg(jsonb_build_object('week', w.week_start, 'count', coalesce(c.n, 0)) order by w.week_start)
      from generate_series(date_trunc('week', now()) - interval '5 weeks', date_trunc('week', now()), interval '1 week') as w(week_start)
      left join (
        select date_trunc('week', created_at) as wk, count(*) as n
        from public.profiles
        where created_at >= date_trunc('week', now()) - interval '5 weeks'
        group by 1
      ) c on c.wk = w.week_start
    ),
    'config', (
      select jsonb_build_object('version', version, 'published_at', published_at, 'notes', notes)
      from public.config_versions order by version desc limit 1
    ),
    'customization', jsonb_build_object(
      'sections',       (select count(*) from public.home_sections where is_enabled),
      'banners',        (select count(*) from public.banners where is_enabled and (ends_at is null or ends_at > now())),
      'flags_on',       (select count(*) from public.feature_flags where enabled),
      'flags_total',    (select count(*) from public.feature_flags),
      'panel_types',    (select count(*) from public.onboarding_panel_types where is_enabled),
      'maintenance_now', exists (select 1 from public.maintenance_windows
                                 where is_active and starts_at <= now() and ends_at > now())
    ),
    'catalog', jsonb_build_object(
      'movies',   (select count(*) from public.global_movies),
      'series',   (select count(*) from public.global_series),
      'episodes', (select count(*) from public.global_episodes),
      'channels', (select count(*) from public.global_channels),
      'misses_7d', (select count(*) from public.metadata_misses where checked_at > now() - interval '7 days')
    ),
    'sports', jsonb_build_object(
      'live',     (select count(*) from public.sports_matches where status in ('live', 'halftime') and not is_hidden),
      'today',    (select count(*) from public.sports_matches
                   where kickoff_at >= date_trunc('day', now())
                     and kickoff_at < date_trunc('day', now()) + interval '1 day' and not is_hidden),
      'upcoming', (select count(*) from public.sports_matches where status = 'scheduled' and kickoff_at > now())
    ),
    'recent_activity', case when public.has_permission('audit.read') then coalesce((
      select jsonb_agg(a order by a.created_at desc) from (
        select al.id, al.action, al.entity, al.entity_id, al.created_at,
               u.email as actor_email
        from public.audit_logs al
        left join auth.users u on u.id = al.actor_id
        order by al.created_at desc
        limit 8
      ) a), '[]'::jsonb) else null end
  ) into result;

  return result;
end;
$$;
revoke all on function public.admin_dashboard_stats() from public, anon;
grant execute on function public.admin_dashboard_stats() to authenticated;
