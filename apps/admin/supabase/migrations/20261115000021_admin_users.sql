-- 021 · App users for the admin Users page (Phase 5.7).
-- App accounts are optional (D17); this lists who signed up and lets an admin
-- suspend / ban one. Email comes from auth.users, so reads go through
-- SECURITY DEFINER functions that check users.read / users.write in the DB.
-- Blocking is enforced by Supabase Auth itself (auth.users.banned_until):
-- a blocked user can't sign in or refresh a session.

-- Keyset index for the newest-first list.
create index if not exists profiles_created_id_idx on public.profiles (created_at desc, id desc);

-- Page of app users, newest first. Search = email / name contains.
-- Cursor = (created_at, id) of the last row of the previous page.
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
  last_seen_at timestamptz
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
           p.created_at, u.last_sign_in_at, p.last_seen_at
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

-- Counts for the page header (cheap; profiles is indexed by status).
create or replace function public.admin_user_counts()
returns table (total bigint, active bigint, suspended bigint, banned bigint, last_7_days bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('users.read') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
    select count(*),
           count(*) filter (where p.status = 'active'),
           count(*) filter (where p.status = 'suspended'),
           count(*) filter (where p.status = 'banned'),
           count(*) filter (where p.created_at > now() - interval '7 days')
    from public.profiles p;
end;
$$;
revoke all on function public.admin_user_counts() from public, anon;
grant execute on function public.admin_user_counts() to authenticated;

-- Suspend / ban / re-activate an app user. Rules (in the DB, not only UI):
--   • needs users.write; • not yourself; • not an admin account (use Admins);
--   • every change is audited with the reason.
create or replace function public.admin_set_user_status(p_user uuid, p_status text, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_status text;
begin
  if not public.has_permission('users.write') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_status not in ('active', 'suspended', 'banned') then
    raise exception 'bad status' using errcode = '22023';
  end if;
  if p_user = (select auth.uid()) then
    raise exception 'cannot change yourself' using errcode = '42501';
  end if;
  if exists (select 1 from public.admin_user_roles ur where ur.user_id = p_user) then
    raise exception 'admin accounts are managed on the Admins page' using errcode = '42501';
  end if;
  if char_length(coalesce(p_reason, '')) > 500 then
    raise exception 'reason too long' using errcode = '22023';
  end if;

  select status into old_status from public.profiles where id = p_user for update;
  if not found then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  if old_status = p_status then
    return;
  end if;

  update public.profiles set status = p_status where id = p_user;
  -- Blocked users can't sign in or refresh tokens (Supabase Auth checks this).
  update auth.users
     set banned_until = case when p_status = 'active' then null else 'infinity'::timestamptz end
   where id = p_user;

  perform public.log_audit(
    'user.status', 'profiles', p_user::text,
    jsonb_build_object('status', old_status),
    jsonb_build_object('status', p_status),
    case when nullif(btrim(coalesce(p_reason, '')), '') is null then null
         else jsonb_build_object('reason', btrim(p_reason)) end
  );
end;
$$;
revoke all on function public.admin_set_user_status(uuid, text, text) from public, anon;
grant execute on function public.admin_set_user_status(uuid, text, text) to authenticated;
