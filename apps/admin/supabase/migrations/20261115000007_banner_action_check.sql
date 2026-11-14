-- 008 · Restore banners.action_type allowed values (dropped by 007's fragment match).
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.banners'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%''screen''::text%'
  ) then
    alter table public.banners add constraint banners_action_type_check
      check (action_type in ('none', 'content', 'category', 'screen', 'url'));
  end if;
end;
$$;
