-- 028 · Fast, gentle catalog loading (user decisions 2026-11-19: A1, B1, D1).
--  content.metadata_in_lists   off = titles go to our server (metadata-tmdb)
--                              only for Home rails + opened details pages;
--                              lists / search use the panel's own artwork.
--  providers.list_timeout_ms   wait for the first byte of a whole-list reply
--                              (all movies / series / channels at once).
--  cache.live_ttl_hours        live channel lists refresh after this age
--                              (movies / series: cache.catalog_ttl_hours).
--  cache.refresh_cooldown_min  the refresh button does nothing this long
--                              after a successful refresh.
insert into public.app_settings (key, category, value_type, value, default_value, validation, description) values
  ('content.metadata_in_lists', 'content', 'bool', 'false', 'false', '{}',
   'Send list / search titles to the metadata service (off = Home rails and opened titles only)'),
  ('providers.list_timeout_ms', 'providers', 'int', '60000', '60000', '{"min":10000,"max":300000}',
   'Wait for the first answer of a whole-list request'),
  ('cache.live_ttl_hours', 'cache', 'int', '6', '6', '{"min":1,"max":168}',
   'Refresh live channel lists after'),
  ('cache.refresh_cooldown_min', 'cache', 'int', '5', '5', '{"min":0,"max":120}',
   'Refresh button pause after a successful refresh')
on conflict (key) do nothing;
