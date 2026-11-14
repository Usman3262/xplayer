-- 021 · Phase 3 completion: config history + rollback, user lookup for flag overrides.

-- Published versions with publisher email (customization.read).
create or replace function public.admin_config_history(p_limit int default 30)
returns table (version bigint, notes text, published_at timestamptz, published_by text, size_bytes int, restored_from bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('customization.read') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
    select cv.version, cv.notes, cv.published_at, u.email::text,
           octet_length(cv.snapshot::text), (cv.snapshot ->> '_restored_from')::bigint
    from public.config_versions cv
    left join auth.users u on u.id = cv.published_by
    order by cv.version desc
    limit least(greatest(p_limit, 1), 100);
end;
$$;
revoke all on function public.admin_config_history(int) from public, anon;
grant execute on function public.admin_config_history(int) to authenticated;

-- Emergency rollback: publish an OLD snapshot again as a new version.
-- The draft tables are not touched (the publish bar then shows the difference).
create or replace function public.admin_republish_version(p_version bigint, p_notes text default null)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  snap jsonb;
  v bigint;
begin
  if not public.has_permission('customization.publish') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select snapshot into snap from public.config_versions where version = p_version;
  if snap is null then
    raise exception 'That version doesn''t exist.' using errcode = 'P0001';
  end if;
  insert into public.config_versions (snapshot, notes, published_by)
  values (snap || jsonb_build_object('_restored_from', p_version),
          coalesce(nullif(left(trim(p_notes), 200), ''), 'Rollback to version ' || p_version),
          (select auth.uid()))
  returning version into v;
  perform public.log_audit('rollback', 'app_config', v::text, null, null,
                           jsonb_build_object('restored_from', p_version));
  return v;
end;
$$;
revoke all on function public.admin_republish_version(bigint, text) from public, anon;
grant execute on function public.admin_republish_version(bigint, text) to authenticated;

-- Admin status compares the draft with the live snapshot minus bookkeeping keys.
create or replace function public.admin_config_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  live public.config_versions;
  draft jsonb;
  changed text[];
begin
  if not public.has_permission('customization.read') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into live from public.config_versions order by version desc limit 1;
  draft := public.build_app_config_snapshot();
  select coalesce(array_agg(k order by k), '{}') into changed
  from jsonb_object_keys(draft) k
  where live.snapshot is null or (draft -> k) is distinct from (live.snapshot -> k);

  return jsonb_build_object(
    'version', coalesce(live.version, 0),
    'published_at', live.published_at,
    'notes', live.notes,
    'published_by', (select u.email from auth.users u where u.id = live.published_by),
    'dirty', cardinality(changed) > 0,
    'changed', to_jsonb(changed),
    'can_publish', public.has_permission('customization.publish'),
    'restored_from', (live.snapshot ->> '_restored_from')::bigint
  );
end;
$$;

-- Publishing compares without bookkeeping keys too.
create or replace function public.publish_app_config(p_notes text default null)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v bigint;
  draft jsonb;
  live jsonb;
begin
  if not public.has_permission('customization.publish') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  draft := public.build_app_config_snapshot();
  select snapshot - '_restored_from' into live from public.config_versions order by version desc limit 1;
  if live is not null and live = draft then
    raise exception 'Nothing to publish — the apps already have these settings.' using errcode = 'P0001';
  end if;
  insert into public.config_versions (snapshot, notes, published_by)
  values (draft, nullif(left(trim(p_notes), 200), ''), (select auth.uid()))
  returning version into v;
  perform public.log_audit('publish', 'app_config', v::text, null, null,
                           jsonb_build_object('notes', p_notes));
  return v;
end;
$$;

-- Flag overrides by user: resolve an email to a user id (customization.write).
create or replace function public.admin_user_id_by_email(p_email text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid;
begin
  if not public.has_permission('customization.write') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select id into uid from auth.users where lower(email) = lower(trim(p_email)) limit 1;
  return uid;
end;
$$;
revoke all on function public.admin_user_id_by_email(text) from public, anon;
grant execute on function public.admin_user_id_by_email(text) to authenticated;

-- Overrides list with user emails for display.
create or replace function public.admin_flag_overrides()
returns table (id uuid, flag_key text, target_type text, target_value text, target_label text,
               enabled boolean, starts_at timestamptz, ends_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('customization.read') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
    select o.id, o.flag_key, o.target_type, o.target_value,
           case when o.target_type = 'user' then coalesce(u.email::text, 'deleted user') else o.target_value end,
           o.enabled, o.starts_at, o.ends_at
    from public.feature_overrides o
    left join auth.users u on o.target_type = 'user' and u.id::text = o.target_value
    order by o.flag_key, o.target_type, 5;
end;
$$;
revoke all on function public.admin_flag_overrides() from public, anon;
grant execute on function public.admin_flag_overrides() to authenticated;
