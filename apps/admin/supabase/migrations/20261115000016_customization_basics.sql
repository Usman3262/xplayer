-- 017 · Customization basics: unpublished-changes status + image storage.

-- What's live vs what's in the tables (draft). `changed` lists the top-level
-- parts that differ (settings, flags, versions, maintenance, onboarding, theme, home).
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
    'can_publish', public.has_permission('customization.publish')
  );
end;
$$;
revoke all on function public.admin_config_status() from public, anon;
grant execute on function public.admin_config_status() to authenticated;

-- Publish only when something changed (avoids empty versions).
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
  select snapshot into live from public.config_versions order by version desc limit 1;
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
revoke all on function public.publish_app_config(text) from public, anon;
grant execute on function public.publish_app_config(text) to authenticated;

-- ── Image storage for banners, logos, splash art ─────────────────────────────
-- Public read (apps load images by URL); write only for customization.write.
-- No SVG (can carry scripts). 2 MB max.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('app-assets', 'app-assets', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy app_assets_admin_read on storage.objects
  for select to authenticated
  using (bucket_id = 'app-assets' and (select public.has_permission('customization.read')));
create policy app_assets_admin_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'app-assets' and (select public.has_permission('customization.write')));
create policy app_assets_admin_update on storage.objects
  for update to authenticated
  using (bucket_id = 'app-assets' and (select public.has_permission('customization.write')))
  with check (bucket_id = 'app-assets' and (select public.has_permission('customization.write')));
create policy app_assets_admin_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'app-assets' and (select public.has_permission('customization.write')));
