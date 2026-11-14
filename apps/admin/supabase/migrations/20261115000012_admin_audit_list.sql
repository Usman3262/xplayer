-- 013 · Audit log list for the admin (needs audit.read).
-- Returns actor email (auth.users is not exposed over the API) and supports
-- filters. Paging: limit/offset with limit+1 fetched by the caller to know if
-- there is a next page (no expensive count on a growing table).

create or replace function public.admin_audit_logs(
  p_limit int default 25,
  p_offset int default 0,
  p_action text default null,
  p_entity text default null,
  p_q text default null,
  p_since timestamptz default null
)
returns table (
  id bigint,
  created_at timestamptz,
  actor_id uuid,
  actor_email text,
  action text,
  entity text,
  entity_id text,
  before jsonb,
  after jsonb,
  meta jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('audit.read') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
    select al.id, al.created_at, al.actor_id, u.email::text, al.action, al.entity,
           al.entity_id, al.before, al.after, al.meta
    from public.audit_logs al
    left join auth.users u on u.id = al.actor_id
    where (p_action is null or al.action = p_action)
      and (p_entity is null or al.entity = p_entity)
      and (p_since is null or al.created_at >= p_since)
      and (p_q is null or p_q = ''
           or al.entity_id ilike '%' || p_q || '%'
           or al.entity ilike '%' || p_q || '%'
           or u.email ilike '%' || p_q || '%')
    order by al.id desc
    limit least(greatest(p_limit, 1), 101)
    offset greatest(p_offset, 0);
end;
$$;
revoke all on function public.admin_audit_logs(int, int, text, text, text, timestamptz) from public, anon;
grant execute on function public.admin_audit_logs(int, int, text, text, text, timestamptz) to authenticated;

-- Distinct entities for the filter dropdown (small, cheap).
create or replace function public.admin_audit_entities()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select distinct al.entity from public.audit_logs al
  where public.has_permission('audit.read')
  order by 1;
$$;
revoke all on function public.admin_audit_entities() from public, anon;
grant execute on function public.admin_audit_entities() to authenticated;
