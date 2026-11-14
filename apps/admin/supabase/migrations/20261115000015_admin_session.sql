-- 016 · One call for everything the admin shell needs about the current user
-- (replaces admin_security_state + my_permissions = 2 round trips → 1).
-- Permissions follow has_permission() rules, including the aal2 requirement.

create or replace function public.admin_session()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select (select auth.uid()) as uid,
           coalesce((select auth.jwt() ->> 'aal'), 'aal1') as aal
  ),
  sec as (
    select
      public.is_admin() as is_admin,
      exists (select 1 from auth.mfa_factors f, me
              where f.user_id = me.uid and f.status = 'verified') as has_2fa,
      coalesce((select (value #>> '{}')::boolean from public.app_settings
                where key = 'admin.require_two_factor'), false) as require_2fa
  )
  select case when not sec.is_admin then null else jsonb_build_object(
    'require_2fa', sec.require_2fa,
    'has_2fa', sec.has_2fa,
    'aal', me.aal,
    'permissions', case
      when sec.has_2fa and me.aal <> 'aal2' then '[]'::jsonb
      else coalesce((
        select jsonb_agg(p.key order by p.key)
        from public.admin_permissions p
        where exists (
          select 1
          from public.admin_user_roles ur
          join public.admin_roles r on r.id = ur.role_id
          left join public.admin_role_permissions rp
            on rp.role_id = r.id and rp.permission_key = p.key
          where ur.user_id = me.uid and ur.is_active
            and (r.key = 'super_admin' or rp.permission_key is not null))), '[]'::jsonb)
    end
  ) end
  from sec, me;
$$;
revoke all on function public.admin_session() from public, anon;
grant execute on function public.admin_session() to authenticated;
