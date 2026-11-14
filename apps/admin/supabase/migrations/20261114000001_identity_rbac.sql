-- 001 · Identity, admin RBAC and audit log
-- Rules: RLS on every table, default deny, permissions checked in the DB.

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Profiles (one per auth user; guests = Supabase anonymous users)
-- ─────────────────────────────────────────────────────────────────────────────
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text check (char_length(display_name) <= 80),
  avatar_url    text check (char_length(avatar_url) <= 500),
  locale        text check (char_length(locale) <= 10),
  country       text check (char_length(country) = 2),
  status        text not null default 'active'
                  check (status in ('active', 'suspended', 'banned')),
  is_guest      boolean not null default false,
  last_seen_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
comment on table public.profiles is 'One row per auth user. Status is admin-controlled.';

create index profiles_status_idx on public.profiles (status);
create index profiles_created_at_idx on public.profiles (created_at desc);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- New auth user → profile row.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, is_guest)
  values (
    new.id,
    nullif(left(coalesce(new.raw_user_meta_data ->> 'display_name', ''), 80), ''),
    coalesce(new.is_anonymous, false)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────────────────────────────────────
-- Admin RBAC: permissions → roles → admin users
-- ─────────────────────────────────────────────────────────────────────────────
create table public.admin_permissions (
  key          text primary key check (key ~ '^[a-z_]+\.[a-z_]+$'),
  module       text not null,
  description  text not null
);

create table public.admin_roles (
  id           uuid primary key default gen_random_uuid(),
  key          text not null unique check (key ~ '^[a-z_]+$'),
  name         text not null,
  description  text,
  is_system    boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create trigger admin_roles_set_updated_at
  before update on public.admin_roles
  for each row execute function public.set_updated_at();

create table public.admin_role_permissions (
  role_id         uuid not null references public.admin_roles (id) on delete cascade,
  permission_key  text not null references public.admin_permissions (key) on delete cascade,
  primary key (role_id, permission_key)
);
create index admin_role_permissions_perm_idx
  on public.admin_role_permissions (permission_key);

create table public.admin_user_roles (
  user_id     uuid not null references auth.users (id) on delete cascade,
  role_id     uuid not null references public.admin_roles (id) on delete cascade,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users (id) on delete set null,
  primary key (user_id, role_id)
);
create index admin_user_roles_role_idx on public.admin_user_roles (role_id);

-- True when the current user holds `perm` (super_admin holds everything).
-- SECURITY DEFINER so it can read RBAC tables without RLS recursion.
create or replace function public.has_permission(perm text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admin_user_roles ur
    join public.admin_roles r on r.id = ur.role_id
    left join public.admin_role_permissions rp
      on rp.role_id = r.id and rp.permission_key = perm
    where ur.user_id = (select auth.uid())
      and ur.is_active
      and (r.key = 'super_admin' or rp.permission_key is not null)
  );
$$;

-- True when the current user has any active admin role.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admin_user_roles ur
    where ur.user_id = (select auth.uid()) and ur.is_active
  );
$$;

-- Permission keys of the current user (for building the admin UI).
create or replace function public.my_permissions()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select p.key
  from public.admin_permissions p
  where public.has_permission(p.key);
$$;

revoke all on function public.has_permission(text) from public, anon;
revoke all on function public.is_admin() from public, anon;
revoke all on function public.my_permissions() from public, anon;
grant execute on function public.has_permission(text) to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.my_permissions() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Audit log (append-only; written through log_audit())
-- ─────────────────────────────────────────────────────────────────────────────
create table public.audit_logs (
  id          bigint generated always as identity primary key,
  actor_id    uuid references auth.users (id) on delete set null,
  action      text not null check (char_length(action) <= 100),
  entity      text not null check (char_length(entity) <= 100),
  entity_id   text check (char_length(entity_id) <= 200),
  before      jsonb,
  after       jsonb,
  meta        jsonb,
  created_at  timestamptz not null default now()
);
create index audit_logs_created_at_idx on public.audit_logs (created_at desc);
create index audit_logs_entity_idx on public.audit_logs (entity, entity_id);
create index audit_logs_actor_idx on public.audit_logs (actor_id, created_at desc);

-- Admins write audit rows only through this function (actor = caller).
create or replace function public.log_audit(
  p_action text,
  p_entity text,
  p_entity_id text default null,
  p_before jsonb default null,
  p_after jsonb default null,
  p_meta jsonb default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_id bigint;
begin
  if not public.is_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into public.audit_logs (actor_id, action, entity, entity_id, before, after, meta)
  values ((select auth.uid()), p_action, p_entity, p_entity_id, p_before, p_after, p_meta)
  returning id into new_id;
  return new_id;
end;
$$;
revoke all on function public.log_audit(text, text, text, jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.log_audit(text, text, text, jsonb, jsonb, jsonb) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.profiles               enable row level security;
alter table public.admin_permissions      enable row level security;
alter table public.admin_roles            enable row level security;
alter table public.admin_role_permissions enable row level security;
alter table public.admin_user_roles       enable row level security;
alter table public.audit_logs             enable row level security;

-- profiles: own row, or admins with users.read / users.write.
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.has_permission('users.read')));

create policy profiles_update on public.profiles
  for update to authenticated
  using (id = (select auth.uid()) or (select public.has_permission('users.write')))
  with check (id = (select auth.uid()) or (select public.has_permission('users.write')));

-- Users may only edit their own harmless fields; status/is_guest are admin-only
-- (admins change them through server code with users.write).
revoke update on public.profiles from authenticated;
grant update (display_name, avatar_url, locale, country, last_seen_at)
  on public.profiles to authenticated;

-- RBAC tables: read with admins.read, write with admins.write.
create policy admin_permissions_select on public.admin_permissions
  for select to authenticated using ((select public.is_admin()));

create policy admin_roles_select on public.admin_roles
  for select to authenticated using ((select public.is_admin()));
create policy admin_roles_write on public.admin_roles
  for all to authenticated
  using ((select public.has_permission('admins.write')) and not is_system)
  with check ((select public.has_permission('admins.write')) and not is_system);

create policy admin_role_permissions_select on public.admin_role_permissions
  for select to authenticated using ((select public.is_admin()));
create policy admin_role_permissions_write on public.admin_role_permissions
  for all to authenticated
  using ((select public.has_permission('admins.write')))
  with check ((select public.has_permission('admins.write')));

create policy admin_user_roles_select on public.admin_user_roles
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.has_permission('admins.read')));
create policy admin_user_roles_write on public.admin_user_roles
  for all to authenticated
  using ((select public.has_permission('admins.write')))
  with check ((select public.has_permission('admins.write')));

-- audit_logs: read with audit.read; no direct insert/update/delete (log_audit only).
create policy audit_logs_select on public.audit_logs
  for select to authenticated using ((select public.has_permission('audit.read')));

-- anon gets nothing on these tables.
revoke all on public.profiles, public.admin_permissions, public.admin_roles,
  public.admin_role_permissions, public.admin_user_roles, public.audit_logs from anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- Reference data: permissions + system roles
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.admin_permissions (key, module, description) values
  ('dashboard.read',       'dashboard',     'View dashboard'),
  ('users.read',           'users',         'View users'),
  ('users.write',          'users',         'Edit, suspend, ban users'),
  ('admins.read',          'admins',        'View admin users and roles'),
  ('admins.write',         'admins',        'Manage admin users and roles'),
  ('providers.read',       'providers',     'View provider adapters and health'),
  ('providers.write',      'providers',     'Configure provider adapters'),
  ('catalog.read',         'catalog',       'View global catalog'),
  ('catalog.write',        'catalog',       'Edit global catalog and mappings'),
  ('customization.read',   'customization', 'View app customization'),
  ('customization.write',  'customization', 'Edit app customization (theme, home, banners, flags)'),
  ('customization.publish','customization', 'Publish app configuration to apps'),
  ('sports.read',          'sports',        'View sports data'),
  ('sports.write',         'sports',        'Manage sports data'),
  ('subscriptions.read',   'subscriptions', 'View plans and subscriptions'),
  ('subscriptions.write',  'subscriptions', 'Manage plans and subscriptions'),
  ('ads.read',             'ads',           'View ads and campaigns'),
  ('ads.write',            'ads',           'Manage ads and campaigns'),
  ('notifications.read',   'notifications', 'View notifications'),
  ('notifications.write',  'notifications', 'Create and send notifications'),
  ('devices.read',         'devices',       'View devices and sessions'),
  ('devices.write',        'devices',       'Revoke devices and sessions'),
  ('support.read',         'support',       'View support tickets and reports'),
  ('support.write',        'support',       'Answer and resolve tickets'),
  ('analytics.read',       'analytics',     'View analytics'),
  ('audit.read',           'audit',         'View audit log'),
  ('settings.read',        'settings',      'View platform settings'),
  ('settings.write',       'settings',      'Edit platform settings');

insert into public.admin_roles (key, name, description, is_system) values
  ('super_admin',          'Super Admin',          'Full platform control',            true),
  ('admin',                'Admin',                'General management',               true),
  ('content_manager',      'Content Manager',      'Catalog, home screen, sports',     true),
  ('subscription_manager', 'Subscription Manager', 'Plans and subscriptions',          true),
  ('marketing_manager',    'Marketing Manager',    'Ads, promotions, notifications',   true),
  ('support_agent',        'Support Agent',        'User support',                     true),
  ('analyst',              'Analyst',              'Read-only analytics',              true);

-- admin: everything except managing admins.
insert into public.admin_role_permissions (role_id, permission_key)
select r.id, p.key from public.admin_roles r, public.admin_permissions p
where r.key = 'admin' and p.key not in ('admins.write');

insert into public.admin_role_permissions (role_id, permission_key)
select r.id, p.key from public.admin_roles r
join public.admin_permissions p on p.key in (
  'dashboard.read', 'catalog.read', 'catalog.write', 'customization.read',
  'customization.write', 'customization.publish', 'sports.read', 'sports.write',
  'providers.read')
where r.key = 'content_manager';

insert into public.admin_role_permissions (role_id, permission_key)
select r.id, p.key from public.admin_roles r
join public.admin_permissions p on p.key in (
  'dashboard.read', 'users.read', 'subscriptions.read', 'subscriptions.write')
where r.key = 'subscription_manager';

insert into public.admin_role_permissions (role_id, permission_key)
select r.id, p.key from public.admin_roles r
join public.admin_permissions p on p.key in (
  'dashboard.read', 'ads.read', 'ads.write', 'notifications.read',
  'notifications.write', 'customization.read', 'analytics.read')
where r.key = 'marketing_manager';

insert into public.admin_role_permissions (role_id, permission_key)
select r.id, p.key from public.admin_roles r
join public.admin_permissions p on p.key in (
  'dashboard.read', 'users.read', 'devices.read', 'devices.write',
  'support.read', 'support.write')
where r.key = 'support_agent';

insert into public.admin_role_permissions (role_id, permission_key)
select r.id, p.key from public.admin_roles r
join public.admin_permissions p on p.key in ('dashboard.read', 'analytics.read')
where r.key = 'analyst';

-- ─────────────────────────────────────────────────────────────────────────────
-- Bootstrap: make the FIRST super admin (works only while no admin exists).
-- Run once in the Supabase SQL editor:  select public.bootstrap_super_admin('you@example.com');
-- Not callable by app users (no grant to anon/authenticated).
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.bootstrap_super_admin(p_email text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid;
begin
  if exists (select 1 from public.admin_user_roles) then
    raise exception 'an admin already exists; add more admins from the panel';
  end if;
  select id into uid from auth.users where lower(email) = lower(p_email) limit 1;
  if uid is null then
    raise exception 'no auth user with that email; sign up first (Auth → Users → Add user)';
  end if;
  insert into public.admin_user_roles (user_id, role_id)
  select uid, id from public.admin_roles where key = 'super_admin';
  insert into public.audit_logs (actor_id, action, entity, entity_id)
  values (uid, 'bootstrap_super_admin', 'admin_user_roles', uid::text);
  return 'super admin set for ' || p_email;
end;
$$;
revoke all on function public.bootstrap_super_admin(text) from public, anon, authenticated;

-- Trigger functions are not meant to be called over the API.
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.set_updated_at() from public, anon, authenticated;
