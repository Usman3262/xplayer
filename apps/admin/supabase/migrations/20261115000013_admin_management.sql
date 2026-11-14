-- 014 · Admin & role management (admins.read / admins.write).
-- One role per admin. Safety rules enforced here (not only in the UI):
--   • you cannot change or deactivate yourself
--   • the last active super admin can never be removed or deactivated

-- Audit entity id: also understand user_id (admin_user_roles has no id column).
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
    to_jsonb(coalesce(new, old)) ->> 'platform',
    to_jsonb(coalesce(new, old)) ->> 'user_id'
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

do $$
declare
  t text;
begin
  foreach t in array array['admin_user_roles', 'admin_roles', 'admin_role_permissions'] loop
    execute format('create trigger %1$s_audit after insert or update or delete on public.%1$I
                     for each row execute function public.audit_row_change()', t);
  end loop;
end;
$$;

-- List admins with email, role and activity.
create or replace function public.admin_list_admins()
returns table (
  user_id uuid,
  email text,
  role_key text,
  role_name text,
  is_active boolean,
  added_at timestamptz,
  last_sign_in_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('admins.read') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
    select ur.user_id, u.email::text, r.key, r.name, ur.is_active, ur.created_at, u.last_sign_in_at
    from public.admin_user_roles ur
    join public.admin_roles r on r.id = ur.role_id
    join auth.users u on u.id = ur.user_id
    order by (r.key = 'super_admin') desc, u.email;
end;
$$;

-- Number of active super admins other than p_user.
create or replace function public._other_active_super_admins(p_user uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int
  from public.admin_user_roles ur
  join public.admin_roles r on r.id = ur.role_id
  where r.key = 'super_admin' and ur.is_active and ur.user_id <> p_user;
$$;
revoke all on function public._other_active_super_admins(uuid) from public, anon, authenticated;

-- Give an existing auth user an admin role (or change it). One role per admin.
create or replace function public.admin_set_role(p_user uuid, p_role_key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  rid uuid;
  current_key text;
begin
  if not public.has_permission('admins.write') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_user = (select auth.uid()) then
    raise exception 'You cannot change your own role.' using errcode = 'P0001';
  end if;
  select id into rid from public.admin_roles where key = p_role_key;
  if rid is null then
    raise exception 'Unknown role.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from auth.users where id = p_user) then
    raise exception 'User not found.' using errcode = 'P0001';
  end if;

  select r.key into current_key
  from public.admin_user_roles ur join public.admin_roles r on r.id = ur.role_id
  where ur.user_id = p_user limit 1;

  if current_key = 'super_admin' and p_role_key <> 'super_admin'
     and public._other_active_super_admins(p_user) = 0 then
    raise exception 'This is the last super admin; add another super admin first.' using errcode = 'P0001';
  end if;

  delete from public.admin_user_roles where user_id = p_user and role_id <> rid;
  insert into public.admin_user_roles (user_id, role_id, created_by)
  values (p_user, rid, (select auth.uid()))
  on conflict (user_id, role_id) do update set is_active = true;
end;
$$;

-- Activate / deactivate an admin (keeps their role).
create or replace function public.admin_set_active(p_user uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('admins.write') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_user = (select auth.uid()) then
    raise exception 'You cannot deactivate yourself.' using errcode = 'P0001';
  end if;
  if not p_active and exists (
       select 1 from public.admin_user_roles ur join public.admin_roles r on r.id = ur.role_id
       where ur.user_id = p_user and r.key = 'super_admin')
     and public._other_active_super_admins(p_user) = 0 then
    raise exception 'This is the last super admin; it cannot be deactivated.' using errcode = 'P0001';
  end if;
  update public.admin_user_roles set is_active = p_active where user_id = p_user;
  if not found then
    raise exception 'Not an admin.' using errcode = 'P0001';
  end if;
end;
$$;

-- Remove admin access completely (the user account stays).
create or replace function public.admin_remove(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('admins.write') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_user = (select auth.uid()) then
    raise exception 'You cannot remove yourself.' using errcode = 'P0001';
  end if;
  if exists (
       select 1 from public.admin_user_roles ur join public.admin_roles r on r.id = ur.role_id
       where ur.user_id = p_user and r.key = 'super_admin')
     and public._other_active_super_admins(p_user) = 0 then
    raise exception 'This is the last super admin; it cannot be removed.' using errcode = 'P0001';
  end if;
  delete from public.admin_user_roles where user_id = p_user;
end;
$$;

-- Find an existing account by email (for "add admin").
create or replace function public.admin_find_user(p_email text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid;
begin
  if not public.has_permission('admins.write') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select id into uid from auth.users where lower(email) = lower(trim(p_email)) limit 1;
  return uid;
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'admin_list_admins()', 'admin_set_role(uuid, text)', 'admin_set_active(uuid, boolean)',
    'admin_remove(uuid)', 'admin_find_user(text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end;
$$;
