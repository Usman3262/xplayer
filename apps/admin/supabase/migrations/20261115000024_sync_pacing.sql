-- 024 · Gentler catalog sync (device logs 2026-11-15: a full sync of a big
-- panel, 2 categories at a time without pauses, got the user's connection
-- blocked by the provider). Default now: 1 category at a time, 300 ms apart.
insert into public.app_settings (key, category, value_type, value, default_value, validation, description) values
  ('cache.sync_gap_ms', 'cache', 'int', '300', '300', '{"min":0,"max":5000}',
   'Pause between two panel category requests during catalog sync (ms)')
on conflict (key) do nothing;

-- Lower the parallel default; keep an admin's own choice.
update public.app_settings
   set default_value = '1',
       value = case when value = '2'::jsonb then '1'::jsonb else value end
 where key = 'cache.sync_parallel_categories';
