-- 8.1 admin: Users list shows each user's library (titles saved / in
-- progress). Counts only — admins never read the rows themselves.
drop function if exists public.admin_list_users(text, text, timestamptz, uuid, int);
create or replace function public.admin_list_users(
  p_search text default null,
  p_status text default null,
  p_before_created timestamptz default null,
  p_before_id uuid default null,
  p_limit int default 25
)
returns table (
  id uuid,
  email text,
  display_name text,
  status text,
  is_admin boolean,
  email_confirmed boolean,
  created_at timestamptz,
  last_sign_in_at timestamptz,
  last_seen_at timestamptz,
  library_titles int,
  watching int
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  q text := nullif(btrim(coalesce(p_search, '')), '');
  lim int := least(greatest(coalesce(p_limit, 25), 1), 100);
begin
  if not public.has_permission('users.read') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('active', 'suspended', 'banned') then
    raise exception 'bad status' using errcode = '22023';
  end if;
  return query
    select p.id, u.email::text, p.display_name, p.status,
           exists (select 1 from public.admin_user_roles ur where ur.user_id = p.id),
           u.email_confirmed_at is not null,
           p.created_at, u.last_sign_in_at, p.last_seen_at,
           (select count(*)::int from public.user_library l where l.user_id = p.id and (l.in_my_list or l.rating <> 0)),
           (select count(*)::int from public.user_library l where l.user_id = p.id and l.progress between 0.02 and 0.95)
    from public.profiles p
    join auth.users u on u.id = p.id
    where (q is null
           or u.email ilike '%' || replace(replace(q, '%', '\%'), '_', '\_') || '%'
           or p.display_name ilike '%' || replace(replace(q, '%', '\%'), '_', '\_') || '%')
      and (p_status is null or p.status = p_status)
      and (p_before_created is null
           or (p.created_at, p.id) < (p_before_created, coalesce(p_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by p.created_at desc, p.id desc
    limit lim;
end;
$$;
revoke all on function public.admin_list_users(text, text, timestamptz, uuid, int) from public, anon;
grant execute on function public.admin_list_users(text, text, timestamptz, uuid, int) to authenticated;
