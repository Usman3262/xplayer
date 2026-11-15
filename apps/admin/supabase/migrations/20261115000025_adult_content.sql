-- 025 · Adult (18+) content controls (user request 2026-11-15).
-- Apps hide 18+ categories everywhere; an "Adult 18+" button (series) opens
-- them after a PIN: the panel's parental PIN on Stalker portals
-- (parent_password), an XPlayer PIN the user sets on Xtream/M3U (the Xtream API
-- does not share the panel's PIN). A category is 18+ when the panel flags it
-- (Xtream is_adult / Stalker censored) or its name contains one of the words below.
insert into public.app_settings (key, category, value_type, value, default_value, validation, description) values
  ('content.adult_section', 'content', 'bool', 'true', 'true', '{}',
   'Show the "Adult 18+" button (PIN protected). Off = 18+ content is never shown'),
  ('content.adult_keywords', 'content', 'string_list',
   '["xxx","adult","adults","18+","+18","porn","porno","sex","sexy","erotic","erotica","hentai","playboy","hustler","brazzers","للكبار","كبار فقط"]',
   '["xxx","adult","adults","18+","+18","porn","porno","sex","sexy","erotic","erotica","hentai","playboy","hustler","brazzers","للكبار","كبار فقط"]',
   '{}', 'Words in a category name that mark it 18+ (whole words)')
on conflict (key) do nothing;
