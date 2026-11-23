-- Screenshot / screen-recording protection for the apps (Android
-- FLAG_SECURE, iOS black overlay while captured). Was read from the old
-- server (gone) so it was stuck on; now a normal admin setting.
insert into public.app_settings (key, category, value_type, value, default_value, validation, description) values
  ('player.screen_protection', 'player', 'bool', 'true', 'true', '{}',
   'Block screenshots and screen recording in the apps')
on conflict (key) do nothing;
