-- 022 · Catalog sync setting for the apps (Phase 6.2).
-- How many panel categories the app downloads at the same time while it fills
-- its local catalog. Low on purpose: IPTV panels rate-limit / IP-block bursts.
insert into public.app_settings (key, category, value_type, value, default_value, validation, description) values
  ('cache.sync_parallel_categories', 'cache', 'int', '2', '2', '{"min":1,"max":6}',
   'Panel categories the app syncs at the same time')
on conflict (key) do nothing;
