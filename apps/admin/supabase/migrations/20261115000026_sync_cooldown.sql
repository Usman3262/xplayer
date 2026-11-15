-- 026 · Back-off after a panel blocks / stops answering (user request
-- 2026-11-15: "minimum requests, handle new network blocks"). The app stops
-- its background catalog sync and waits this long before trying again, also
-- across app restarts. The user's own requests (opening a title) still go.
insert into public.app_settings (key, category, value_type, value, default_value, validation, description) values
  ('cache.sync_cooldown_min', 'cache', 'int', '30', '30', '{"min":1,"max":1440}',
   'Minutes to pause background catalog sync after the panel stops answering')
on conflict (key) do nothing;
