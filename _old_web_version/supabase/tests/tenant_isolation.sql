-- Run against a disposable local Supabase database with:
--   supabase start
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/tenant_isolation.sql
-- This transaction rolls back all fixture users and clinics.
begin;
select gen_random_uuid() as user_a \gset
select gen_random_uuid() as user_b \gset
select gen_random_uuid() as user_secretary \gset

insert into auth.users(id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  (:'user_a','authenticated','authenticated','isolation-a@example.test','',now(),'{}','{}',now(),now()),
  (:'user_b','authenticated','authenticated','isolation-b@example.test','',now(),'{}','{}',now(),now()),
  (:'user_secretary','authenticated','authenticated','isolation-secretary@example.test','',now(),'{}','{}',now(),now());

set local role authenticated;
select set_config('request.jwt.claim.sub', :'user_a', true);
select public.create_clinic('Tenant A','Dentiste','0600000001','1 rue A','Casablanca') as clinic_a \gset
select set_config('request.jwt.claim.sub', :'user_b', true);
select public.create_clinic('Tenant B','Médecin','0600000002','2 rue B','Rabat') as clinic_b \gset

-- A cannot see or alter B's clinic row or membership row.
select set_config('request.jwt.claim.sub', :'user_a', true);
select case when count(*)=0 then 1 else 1/0 end as assert_clinic_hidden
from public.clinics where id=:'clinic_b';
select case when changed=0 then 1 else 1/0 end as assert_clinic_update_blocked
from (with changed as (update public.clinics set name='Stolen' where id=:'clinic_b' returning 1) select count(*) changed from changed) q;
select case when changed=0 then 1 else 1/0 end as assert_clinic_delete_blocked
from (with changed as (delete from public.clinics where id=:'clinic_b' returning 1) select count(*) changed from changed) q;
select case when count(*)=0 then 1 else 1/0 end as assert_member_hidden
from public.clinic_members where clinic_id=:'clinic_b';
select case when changed=0 then 1 else 1/0 end as assert_member_update_blocked
from (with changed as (update public.clinic_members set role='owner' where clinic_id=:'clinic_b' returning 1) select count(*) changed from changed) q;
select case when changed=0 then 1 else 1/0 end as assert_member_delete_blocked
from (with changed as (delete from public.clinic_members where clinic_id=:'clinic_b' returning 1) select count(*) changed from changed) q;

-- Owner A adds a secretary; that secretary cannot promote themselves or edit another member's role.
select set_config('request.jwt.claim.sub', :'user_a', true);
insert into public.clinic_members(clinic_id,user_id,role,created_by)
values (:'clinic_a',:'user_secretary','secretary',:'user_a');
select set_config('request.jwt.claim.sub', :'user_secretary', true);
select case when changed=0 then 1 else 1/0 end as assert_secretary_cannot_promote_self
from (with changed as (update public.clinic_members set role='owner' where user_id=:'user_secretary' returning 1) select count(*) changed from changed) q;
select case when changed=0 then 1 else 1/0 end as assert_secretary_cannot_change_roles
from (with changed as (update public.clinic_members set role='doctor' where clinic_id=:'clinic_a' and user_id=:'user_a' returning 1) select count(*) changed from changed) q;

rollback;
