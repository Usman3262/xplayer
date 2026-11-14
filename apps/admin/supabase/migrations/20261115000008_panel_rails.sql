-- 009 · Default "new" rails read the user's panel (newest by panel "added" date).
update public.home_sections set source = 'provider_added'
where section_type in ('new_releases', 'recently_added') and source = 'auto';

insert into public.config_versions (snapshot, notes)
values (public.build_app_config_snapshot(), 'New/recent rails from the user''s panel');
