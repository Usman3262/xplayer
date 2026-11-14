-- 015 · Admin two-factor (TOTP) enforced in the database.
-- If an admin has a verified MFA factor, every permission requires an aal2 session
-- (password + code). is_admin() stays aal-agnostic so the login step can tell
-- "this is an admin, now ask for the code".

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
  )
  and (
    not exists (
      select 1 from auth.mfa_factors f
      where f.user_id = (select auth.uid()) and f.status = 'verified'
    )
    or coalesce((select auth.jwt() ->> 'aal'), 'aal1') = 'aal2'
  );
$$;

-- Platform-wide admin security policy (server-side setting, not sent to apps).
insert into public.app_settings (key, category, value_type, value, default_value, validation, description, is_public)
values ('admin.require_two_factor', 'security', 'bool', 'false', 'false', '{}',
        'Require every admin to use two-factor sign-in (authenticator app)', false)
on conflict (key) do nothing;

-- What the admin UI needs to know about the current admin's security state.
create or replace function public.admin_security_state()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when not public.is_admin() then null else jsonb_build_object(
    'require_2fa', coalesce((select (value #>> '{}')::boolean from public.app_settings
                             where key = 'admin.require_two_factor'), false),
    'has_2fa', exists (select 1 from auth.mfa_factors f
                       where f.user_id = (select auth.uid()) and f.status = 'verified'),
    'aal', coalesce((select auth.jwt() ->> 'aal'), 'aal1')
  ) end;
$$;
revoke all on function public.admin_security_state() from public, anon;
grant execute on function public.admin_security_state() to authenticated;
