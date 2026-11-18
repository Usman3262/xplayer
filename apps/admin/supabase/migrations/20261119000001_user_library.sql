-- 8.1 / 8.2 · The signed-in user's own library in the cloud (My List,
-- ratings, Continue Watching / history). Only the user's own rows; the
-- catalog itself never comes here (it stays on the phone).
--   panel_key = panel type + host (e.g. "xtream:cf.example.com"), never a
--               username / password / MAC. Title ids are per panel.
--   Newest wins: a push only replaces a row when it is newer.

create table public.user_library (
  user_id       uuid not null references auth.users (id) on delete cascade,
  panel_key     text not null check (char_length(panel_key) between 3 and 200),
  item_id       text not null check (char_length(item_id) between 1 and 200),
  kind          text not null check (kind in ('movie', 'series', 'live', 'sports')),
  title         text not null default '' check (char_length(title) <= 300),
  poster_url    text check (char_length(poster_url) <= 1000),
  series_id     text check (char_length(series_id) <= 200),
  extra         jsonb not null default '{}'::jsonb
                  check (jsonb_typeof(extra) = 'object' and pg_column_size(extra) <= 2000),
  in_my_list    boolean not null default false,
  rating        smallint not null default 0 check (rating between -1 and 1),
  progress      real not null default 0 check (progress between 0 and 1),
  position_sec  int check (position_sec between 0 and 86400),
  duration_sec  int check (duration_sec between 0 and 86400),
  changed_at    timestamptz not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (user_id, panel_key, item_id)
);
comment on table public.user_library is 'A user''s My List / ratings / watch progress per panel title. Own rows only.';
create index user_library_changed_idx on public.user_library (user_id, panel_key, changed_at desc);

create trigger user_library_set_updated_at before update on public.user_library
  for each row execute function public.set_updated_at();

alter table public.user_library enable row level security;
create policy user_library_own_select on public.user_library
  for select to authenticated using (user_id = (select auth.uid()));
create policy user_library_own_insert on public.user_library
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy user_library_own_update on public.user_library
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy user_library_own_delete on public.user_library
  for delete to authenticated using (user_id = (select auth.uid()));
-- Admins see counts through admin RPCs (security definer, permission-checked), not rows.

-- Push a batch (≤ 300 rows) — newest wins per title. Security invoker: RLS
-- applies; user_id is always the caller.
create or replace function public.library_push(p_panel text, p_items jsonb)
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare
  n int;
begin
  if (select auth.uid()) is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 300 then
    raise exception 'items must be an array of at most 300' using errcode = '22023';
  end if;
  insert into public.user_library as l
    (user_id, panel_key, item_id, kind, title, poster_url, series_id, extra,
     in_my_list, rating, progress, position_sec, duration_sec, changed_at)
  select (select auth.uid()), p_panel, i->>'id', coalesce(i->>'kind', 'movie'),
         left(coalesce(i->>'title', ''), 300), left(i->>'poster', 1000), left(i->>'series', 200),
         coalesce(i->'extra', '{}'::jsonb),
         coalesce((i->>'my_list')::boolean, false), coalesce((i->>'rating')::smallint, 0),
         least(greatest(coalesce((i->>'progress')::real, 0), 0), 1),
         (i->>'pos')::int, (i->>'dur')::int,
         least(coalesce((i->>'at')::timestamptz, now()), now() + interval '5 minutes')
  from jsonb_array_elements(p_items) i
  where coalesce(i->>'id', '') <> ''
  on conflict (user_id, panel_key, item_id) do update set
    kind = excluded.kind, title = case when excluded.title <> '' then excluded.title else l.title end,
    poster_url = coalesce(excluded.poster_url, l.poster_url), series_id = coalesce(excluded.series_id, l.series_id),
    extra = excluded.extra, in_my_list = excluded.in_my_list, rating = excluded.rating,
    progress = excluded.progress, position_sec = excluded.position_sec, duration_sec = excluded.duration_sec,
    changed_at = excluded.changed_at
  where excluded.changed_at > l.changed_at;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Pull what changed since a time (null = everything), newest first, ≤ 1000.
create or replace function public.library_pull(p_panel text, p_since timestamptz default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', item_id, 'kind', kind, 'title', title, 'poster', poster_url, 'series', series_id,
           'extra', extra, 'my_list', in_my_list, 'rating', rating, 'progress', progress,
           'pos', position_sec, 'dur', duration_sec, 'at', changed_at) order by changed_at desc), '[]'::jsonb)
  from (
    select * from public.user_library
    where user_id = (select auth.uid()) and panel_key = p_panel
      and (p_since is null or changed_at > p_since)
    order by changed_at desc
    limit 1000
  ) x;
$$;

revoke all on function public.library_push(text, jsonb) from public, anon;
revoke all on function public.library_pull(text, timestamptz) from public, anon;
grant execute on function public.library_push(text, jsonb) to authenticated;
grant execute on function public.library_pull(text, timestamptz) to authenticated;
