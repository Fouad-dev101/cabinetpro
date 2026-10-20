create extension if not exists pgcrypto;
create type public.clinic_role as enum ('owner', 'doctor', 'secretary');

create or replace function public.set_updated_at() returns trigger language plpgsql set search_path = public, pg_temp as $$ begin new.updated_at := now(); return new; end $$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  preferred_locale text not null default 'fr' check (preferred_locale in ('fr','ar')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);
create table public.clinics (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 160),
  specialty text not null check (length(trim(specialty)) between 1 and 120),
  phone text not null check (length(trim(phone)) between 1 and 40),
  address text not null check (length(trim(address)) between 1 and 300),
  city text not null check (length(trim(city)) between 1 and 120),
  logo_path text, ice text, if_number text, patente text, rc text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict
);
create table public.clinic_members (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  role public.clinic_role not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);
create index clinic_members_clinic_id_idx on public.clinic_members(clinic_id);

-- Only trusted server code creates invitations; client-editable auth metadata is not used for tenancy.
create table public.clinic_invitations (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  email text not null check (email = lower(trim(email))),
  role public.clinic_role not null check (role in ('doctor','secretary')),
  invited_by uuid not null references auth.users(id) on delete restrict,
  accepted_at timestamptz, expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);
create unique index clinic_invitations_pending_email_idx on public.clinic_invitations(email) where accepted_at is null;
create index clinic_invitations_clinic_id_idx on public.clinic_invitations(clinic_id);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.profiles(id, full_name, created_by)
  values (new.id, nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), new.id) on conflict (id) do nothing;
  return new;
end $$;
revoke all on function public.handle_new_user() from public, anon, authenticated;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- SECURITY DEFINER membership helpers avoid recursive policies on clinic_members.
create or replace function public.is_clinic_member(p_clinic_id uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists(select 1 from public.clinic_members m where m.clinic_id = p_clinic_id and m.user_id = (select auth.uid()))
$$;
create or replace function public.has_role(p_clinic_id uuid, p_roles public.clinic_role[]) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists(select 1 from public.clinic_members m where m.clinic_id = p_clinic_id and m.user_id = (select auth.uid()) and m.role = any(p_roles))
$$;
revoke all on function public.is_clinic_member(uuid) from public, anon;
revoke all on function public.has_role(uuid, public.clinic_role[]) from public, anon;
grant execute on function public.is_clinic_member(uuid), public.has_role(uuid, public.clinic_role[]) to authenticated;

-- Atomic first-clinic creation resolves RLS bootstrap safely.
create or replace function public.create_clinic(p_name text, p_specialty text, p_phone text, p_address text, p_city text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid := auth.uid(); v_clinic uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if exists(select 1 from public.clinic_members where user_id = v_user) then raise exception 'A user may belong to exactly one clinic'; end if;
  insert into public.clinics(name,specialty,phone,address,city,created_by)
    values(trim(p_name),trim(p_specialty),trim(p_phone),trim(p_address),trim(p_city),v_user) returning id into v_clinic;
  perform set_config('cabinetpro.trusted_membership_insert','on',true);
  insert into public.clinic_members(clinic_id,user_id,role,created_by) values(v_clinic,v_user,'owner',v_user);
  return v_clinic;
end $$;
revoke all on function public.create_clinic(text,text,text,text,text) from public, anon;
grant execute on function public.create_clinic(text,text,text,text,text) to authenticated;

-- Called after sign-in by the invited user; clinic and role come only from the server-created invite.
create or replace function public.accept_clinic_invitation() returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid := auth.uid(); v_email text; v_invite public.clinic_invitations%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if exists(select 1 from public.clinic_members where user_id = v_user) then raise exception 'User already belongs to a clinic'; end if;
  select lower(email) into v_email from auth.users where id = v_user;
  select * into v_invite from public.clinic_invitations where email = v_email and accepted_at is null and expires_at > now() order by created_at desc limit 1 for update;
  if not found then raise exception 'No valid invitation found'; end if;
  perform set_config('cabinetpro.trusted_membership_insert','on',true);
  insert into public.clinic_members(clinic_id,user_id,role,created_by) values(v_invite.clinic_id,v_user,v_invite.role,v_invite.invited_by);
  update public.clinic_invitations set accepted_at = now(), updated_at = now() where id = v_invite.id;
  return v_invite.clinic_id;
end $$;
revoke all on function public.accept_clinic_invitation() from public, anon;
grant execute on function public.accept_clinic_invitation() to authenticated;

-- Defense in depth on owner roster edits, including no self-role changes and no last-owner loss.
create or replace function public.guard_clinic_member_change() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    if current_setting('cabinetpro.trusted_membership_insert',true) = 'on' then return new; end if;
    if v_actor is null or not public.has_role(new.clinic_id,array['owner']::public.clinic_role[]) then raise exception 'Only owners can add members'; end if;
    if new.user_id = v_actor then raise exception 'Use create_clinic to establish ownership'; end if;
    return new;
  elsif tg_op = 'UPDATE' then
    if v_actor is null or not public.has_role(old.clinic_id,array['owner']::public.clinic_role[]) then raise exception 'Only owners can update members'; end if;
    if new.user_id <> old.user_id or new.clinic_id <> old.clinic_id then raise exception 'Member identity and clinic are immutable'; end if;
    if old.user_id = v_actor and new.role <> old.role then raise exception 'Cannot change your own role'; end if;
    if old.role = 'owner' and new.role <> 'owner' and (select count(*) from public.clinic_members where clinic_id=old.clinic_id and role='owner') <= 1 then raise exception 'Cannot demote the last owner'; end if;
    return new;
  else
    if v_actor is null or not public.has_role(old.clinic_id,array['owner']::public.clinic_role[]) then raise exception 'Only owners can remove members'; end if;
    if old.role='owner' and (select count(*) from public.clinic_members where clinic_id=old.clinic_id and role='owner') <= 1 then raise exception 'Cannot remove the last owner'; end if;
    return old;
  end if;
end $$;
revoke all on function public.guard_clinic_member_change() from public, anon, authenticated;
create trigger guard_clinic_member_change before insert or update or delete on public.clinic_members for each row execute function public.guard_clinic_member_change();

create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger clinics_set_updated_at before update on public.clinics for each row execute function public.set_updated_at();
create trigger clinic_members_set_updated_at before update on public.clinic_members for each row execute function public.set_updated_at();
create trigger clinic_invitations_set_updated_at before update on public.clinic_invitations for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.clinics enable row level security;
alter table public.clinic_members enable row level security;
alter table public.clinic_invitations enable row level security;
alter table public.profiles force row level security;
alter table public.clinics force row level security;
alter table public.clinic_members force row level security;
alter table public.clinic_invitations force row level security;
create policy profiles_select_self on public.profiles for select to authenticated using(id=(select auth.uid()));
create policy profiles_update_self on public.profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
create policy clinics_select_member on public.clinics for select to authenticated using(public.is_clinic_member(id));
create policy clinics_update_owner on public.clinics for update to authenticated using(public.has_role(id,array['owner']::public.clinic_role[])) with check(public.has_role(id,array['owner']::public.clinic_role[]));
create policy clinics_delete_owner on public.clinics for delete to authenticated using(public.has_role(id,array['owner']::public.clinic_role[]));
create policy clinic_members_select_same_clinic on public.clinic_members for select to authenticated using(public.is_clinic_member(clinic_id));
create policy clinic_members_insert_owner on public.clinic_members for insert to authenticated with check(public.has_role(clinic_id,array['owner']::public.clinic_role[]));
create policy clinic_members_update_owner on public.clinic_members for update to authenticated using(public.has_role(clinic_id,array['owner']::public.clinic_role[])) with check(public.has_role(clinic_id,array['owner']::public.clinic_role[]));
create policy clinic_members_delete_owner on public.clinic_members for delete to authenticated using(public.has_role(clinic_id,array['owner']::public.clinic_role[]));
create policy clinic_invitations_service_role_only on public.clinic_invitations for all to service_role using(true) with check(true);
grant select,update on public.profiles to authenticated;
grant select,update,delete on public.clinics to authenticated;
grant select,insert,update,delete on public.clinic_members to authenticated;
revoke all on public.clinic_invitations from anon,authenticated;
grant all on public.clinic_invitations to service_role;

-- Private bucket; paths are <clinic UUID>/<filename>. Members read; owners write/delete.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('clinic-logos','clinic-logos',false,5242880,array['image/png','image/jpeg','image/webp','image/svg+xml'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy clinic_logo_read_member on storage.objects for select to authenticated using(
  bucket_id='clinic-logos' and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and public.is_clinic_member(((storage.foldername(name))[1])::uuid));
create policy clinic_logo_insert_owner on storage.objects for insert to authenticated with check(
  bucket_id='clinic-logos' and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and public.has_role(((storage.foldername(name))[1])::uuid,array['owner']::public.clinic_role[]));
create policy clinic_logo_update_owner on storage.objects for update to authenticated using(
  bucket_id='clinic-logos' and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and public.has_role(((storage.foldername(name))[1])::uuid,array['owner']::public.clinic_role[])) with check(
  bucket_id='clinic-logos' and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and public.has_role(((storage.foldername(name))[1])::uuid,array['owner']::public.clinic_role[]));
create policy clinic_logo_delete_owner on storage.objects for delete to authenticated using(
  bucket_id='clinic-logos' and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and public.has_role(((storage.foldername(name))[1])::uuid,array['owner']::public.clinic_role[]));
