-- 019 · At least one "Choose your panel" type must stay enabled (users need a way in).
create or replace function public.ensure_one_panel_type_enabled()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from public.onboarding_panel_types where is_enabled) then
    raise exception 'Keep at least one panel type on — users need a way to connect.' using errcode = 'P0001';
  end if;
  return null;
end;
$$;
revoke all on function public.ensure_one_panel_type_enabled() from public, anon, authenticated;

create constraint trigger onboarding_panel_types_one_enabled
  after update or delete on public.onboarding_panel_types
  deferrable initially deferred
  for each row execute function public.ensure_one_panel_type_enabled();
