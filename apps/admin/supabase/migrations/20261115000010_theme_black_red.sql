-- 011 · Default theme: black + red (matches Flutter AppThemeConfig.defaults).
update public.app_themes
set name = 'XPlayer black & red',
    tokens = '{
      "background":"#0D0607","surface":"#1A0B0D","surfaceElevated":"#2A1013",
      "primary":"#E11D2E","primaryDim":"#A3111D","secondary":"#7A0C14",
      "gold":"#F5B301","live":"#FF3B30","success":"#22C55E",
      "textPrimary":"#FFFFFF","textSecondary":"#BFAFB1",
      "border":"#3A1A1E","danger":"#FF6B6B"}'
where is_active;

insert into public.config_versions (snapshot, notes)
values (public.build_app_config_snapshot(), 'Default theme: black & red');
