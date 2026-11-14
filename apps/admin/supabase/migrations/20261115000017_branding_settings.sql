-- 018 · Branding settings (sent to the apps). Empty = use the built-in asset/name.
-- The launcher/home-screen name itself comes from app.config at build time (stores
-- don't allow changing it remotely); display_name only overrides in-app text.
insert into public.app_settings (key, category, value_type, value, default_value, validation, description) values
  ('branding.display_name', 'branding', 'string', '""', '""', '{}',
   'Name shown inside the apps (empty = the built-in app name)'),
  ('branding.logo_url', 'branding', 'url', '""', '""', '{}',
   'Logo image shown in the apps (empty = built-in logo)'),
  ('branding.splash_url', 'branding', 'url', '""', '""', '{}',
   'Splash screen image (empty = built-in splash)'),
  ('branding.tagline', 'branding', 'string', '""', '""', '{}',
   'Short line under the logo on the splash/welcome screen (optional)')
on conflict (key) do nothing;
