-- 020 · Security settings (category 'security', e.g. admin.require_two_factor) need
-- settings.write — not just customization.write. Other settings unchanged.

drop policy if exists app_settings_update on public.app_settings;
drop policy if exists app_settings_insert on public.app_settings;
drop policy if exists app_settings_delete on public.app_settings;

create policy app_settings_update on public.app_settings
  for update to authenticated
  using (
    case when category = 'security'
      then (select public.has_permission('settings.write'))
      else (select public.has_permission('customization.write')) end)
  with check (
    case when category = 'security'
      then (select public.has_permission('settings.write'))
      else (select public.has_permission('customization.write')) end);

-- New keys / removing keys = schema-level changes → settings.write only.
create policy app_settings_insert on public.app_settings
  for insert to authenticated
  with check ((select public.has_permission('settings.write')));
create policy app_settings_delete on public.app_settings
  for delete to authenticated
  using ((select public.has_permission('settings.write')));

-- Nobody may move a setting into/out of 'security' or change its type via the API.
create or replace function public.lock_setting_shape()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null and (
       new.category is distinct from old.category
       or new.value_type is distinct from old.value_type
       or new.key is distinct from old.key) then
    raise exception 'A setting''s key, category and type can''t be changed here.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function public.lock_setting_shape() from public, anon, authenticated;
create trigger app_settings_lock_shape
  before update on public.app_settings
  for each row execute function public.lock_setting_shape();
