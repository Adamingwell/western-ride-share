-- 009: allow legacy members to complete private profiles; add administrator moderation.
create policy "Members create own profile" on public.member_profiles
 for insert to authenticated with check (user_id=(select auth.uid()));

create table if not exists public.member_moderation (
 user_id uuid primary key references auth.users(id) on delete cascade,
 suspended_until timestamptz,
 reason text,
 updated_by uuid references auth.users(id),
 updated_at timestamptz not null default now()
);
alter table public.member_moderation enable row level security;
revoke all on public.member_moderation from public,anon,authenticated;

create table if not exists public.moderation_notes (
 id bigint generated always as identity primary key,
 report_id uuid not null references public.safety_reports(id) on delete cascade,
 admin_id uuid not null references auth.users(id),
 note text not null check (char_length(btrim(note)) between 3 and 2000),
 created_at timestamptz not null default now()
);
alter table public.moderation_notes enable row level security;
revoke all on public.moderation_notes from public,anon,authenticated;

create or replace function public.is_account_suspended(p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.member_moderation
 where user_id=p_user and suspended_until>now())
$$;
revoke all on function public.is_account_suspended(uuid) from public,anon;
grant execute on function public.is_account_suspended(uuid) to authenticated;

create or replace function public.admin_set_suspension(p_user uuid,p_until timestamptz,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_site_admin() then raise exception 'Access denied'; end if;
 if p_user is null or p_user=auth.uid() then raise exception 'Cannot moderate this account'; end if;
 if exists(select 1 from public.site_administrators where user_id=p_user) then raise exception 'Cannot suspend an administrator'; end if;
 if p_until is not null and (p_until<=now() or p_until>now()+interval '365 days') then raise exception 'Invalid suspension period'; end if;
 if p_until is not null and char_length(btrim(coalesce(p_reason,'')))<5 then raise exception 'A reason is required'; end if;
 insert into public.member_moderation(user_id,suspended_until,reason,updated_by,updated_at)
 values(p_user,p_until,nullif(btrim(p_reason),''),auth.uid(),now())
 on conflict(user_id) do update set suspended_until=excluded.suspended_until,
 reason=excluded.reason,updated_by=excluded.updated_by,updated_at=now();
end; $$;
revoke all on function public.admin_set_suspension(uuid,timestamptz,text) from public,anon;
grant execute on function public.admin_set_suspension(uuid,timestamptz,text) to authenticated;

create or replace function public.admin_add_report_note(p_report uuid,p_note text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_site_admin() then raise exception 'Access denied'; end if;
 if char_length(btrim(coalesce(p_note,''))) not between 3 and 2000 then raise exception 'Invalid note'; end if;
 insert into public.moderation_notes(report_id,admin_id,note)
 values(p_report,auth.uid(),btrim(p_note));
end; $$;
revoke all on function public.admin_add_report_note(uuid,text) from public,anon;
grant execute on function public.admin_add_report_note(uuid,text) to authenticated;

create or replace function public.admin_report_notes(p_report uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.is_site_admin() then raise exception 'Access denied'; end if;
 return coalesce((select jsonb_agg(to_jsonb(t)) from
 (select n.id,n.note,n.created_at,n.admin_id from public.moderation_notes n
 where n.report_id=p_report order by n.created_at desc limit 100) t),'[]'::jsonb);
end; $$;
revoke all on function public.admin_report_notes(uuid) from public,anon;
grant execute on function public.admin_report_notes(uuid) to authenticated;

create or replace function public.admin_member_moderation(p_limit integer default 100,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.is_site_admin() then raise exception 'Access denied'; end if;
 return coalesce((select jsonb_agg(to_jsonb(t)) from
 (select m.user_id,m.suspended_until,m.reason,m.updated_at
 from public.member_moderation m order by m.updated_at desc
 limit least(greatest(p_limit,1),100) offset greatest(p_offset,0)) t),'[]'::jsonb);
end; $$;
revoke all on function public.admin_member_moderation(integer,integer) from public,anon;
grant execute on function public.admin_member_moderation(integer,integer) to authenticated;

-- Enforce suspensions on the server for ride creation and private messaging.
create or replace function public.enforce_ride_not_suspended() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if public.is_account_suspended(auth.uid()) then raise exception 'Your account is suspended'; end if;
 return new;
end; $$;
drop trigger if exists enforce_ride_not_suspended on public.rides;
create trigger enforce_ride_not_suspended before insert or update on public.rides
for each row execute function public.enforce_ride_not_suspended();

-- Restrict direct ride_messages inserts to prevent bypass of messaging RPC.
-- Existing policies are not modified; review them if direct inserts are permitted.
create or replace function public.enforce_message_not_suspended() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if public.is_account_suspended(new.sender_id) then raise exception 'Your account is suspended'; end if;
 if public.is_account_suspended(new.poster_id) or public.is_account_suspended(new.visitor_id)
 then raise exception 'Messaging unavailable for this account'; end if;
 return new;
end; $$;
drop trigger if exists enforce_message_not_suspended on public.ride_messages;
create trigger enforce_message_not_suspended before insert on public.ride_messages
for each row execute function public.enforce_message_not_suspended();

-- Important: this migration does not revoke login, remove existing rides, or hide old posts.
-- Those capabilities require separate policy work and incident-response procedures.
