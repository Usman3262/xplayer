-- pgTAP tests for migration 001. Run with `supabase test db` (needs Docker/local DB).
begin;
select plan(12);

-- Fixtures: two normal users + one admin (content_manager).
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'bob@test.local'),
  ('00000000-0000-0000-0000-0000000000c3', 'carol@test.local');
insert into public.admin_user_roles (user_id, role_id)
select '00000000-0000-0000-0000-0000000000c3', id
from public.admin_roles where key = 'content_manager';

select is((select count(*)::int from public.profiles
           where id in ('00000000-0000-0000-0000-0000000000a1',
                        '00000000-0000-0000-0000-0000000000b2')), 2,
          'profile row created for each new auth user');

-- As Alice (plain user).
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1"}';

select is((select count(*)::int from public.profiles), 1, 'user sees only own profile');
select is(public.is_admin(), false, 'plain user is not admin');
select is(public.has_permission('users.read'), false, 'plain user has no permissions');
select is((select count(*)::int from public.admin_roles), 0, 'plain user cannot read roles');
select throws_ok($$ update public.profiles set status = 'banned'
                   where id = '00000000-0000-0000-0000-0000000000a1' $$,
                 '42501', null, 'user cannot change own status');
select lives_ok($$ update public.profiles set display_name = 'Alice'
                  where id = '00000000-0000-0000-0000-0000000000a1' $$,
                'user can change own display name');
select throws_ok($$ select public.log_audit('x', 'y') $$, '42501', null,
                 'plain user cannot write audit log');
select throws_ok($$ insert into public.admin_user_roles (user_id, role_id)
                    select '00000000-0000-0000-0000-0000000000a1', id
                    from public.admin_roles where key = 'super_admin' $$,
                 '42501', null, 'user cannot make themself admin');

-- As Carol (content_manager).
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c3"}';
select is(public.has_permission('catalog.write'), true, 'content manager has catalog.write');
select is(public.has_permission('users.read'), false, 'content manager lacks users.read');
select isnt(public.log_audit('test', 'unit'), null, 'admin can write audit log');

select * from finish();
rollback;
