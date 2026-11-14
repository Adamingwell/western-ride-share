-- 007: private signup contact records; apply before deploying the new signup form.
-- Email verification is handled by Supabase Auth; phone numbers are NOT verified.
create table if not exists public.member_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(btrim(full_name)) between 2 and 120),
  phone text check (phone is null or (char_length(phone) between 7 and 25 and phone ~ '^[+0-9(). -]+$')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.member_profiles enable row level security;
revoke all on public.member_profiles from anon;
grant select,update on public.member_profiles to authenticated;
-- No client INSERT or DELETE: new profiles are created from auth signup via trigger.
create policy "Members read own profile" on public.member_profiles for select to authenticated
 using (user_id=(select auth.uid()));
create policy "Members update own profile" on public.member_profiles for update to authenticated
 using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));

create or replace function public.create_member_profile() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_name text; v_phone text;
begin
  v_name:=btrim(coalesce(new.raw_user_meta_data->>'full_name',''));
  v_phone:=nullif(btrim(coalesce(new.raw_user_meta_data->>'phone','')),'');
  -- Existing registration flows may omit the new fields; do not break authentication.
  if char_length(v_name) between 2 and 120 and
    (v_phone is null or (char_length(v_phone) between 7 and 25 and v_phone ~ '^[+0-9(). -]+$')) then
    insert into public.member_profiles(user_id,full_name,phone)
      values(new.id,v_name,v_phone) on conflict(user_id) do nothing;
  end if;
  return new;
end; $$;
drop trigger if exists on_auth_user_created_member_profile on auth.users;
create trigger on_auth_user_created_member_profile
after insert on auth.users for each row execute function public.create_member_profile();
comment on table public.member_profiles is 'Private signup contact details. Only account holder and privileged server administrators may read. No public directory.';
