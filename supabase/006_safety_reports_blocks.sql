-- 006: user blocking and confidential safety reports.
-- Run in Supabase SQL Editor before testing the safety controls.
create table if not exists public.blocked_users (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id,blocked_id),
  constraint blocked_users_not_self check (blocker_id <> blocked_id)
);
alter table public.blocked_users enable row level security;
revoke all on public.blocked_users from anon;
grant select,insert,delete on public.blocked_users to authenticated;
create policy "Read own blocks" on public.blocked_users for select to authenticated using (blocker_id=(select auth.uid()));
create policy "Create own blocks" on public.blocked_users for insert to authenticated with check (blocker_id=(select auth.uid()));
create policy "Remove own blocks" on public.blocked_users for delete to authenticated using (blocker_id=(select auth.uid()));

create table if not exists public.safety_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_id uuid not null references auth.users(id) on delete cascade,
  thread_id uuid,
  ride_id uuid,
  category text not null check (category in ('harassment','unsafe','fraud','discrimination','other')),
  details text not null check (char_length(btrim(details)) between 10 and 2000),
  created_at timestamptz not null default now(),
  status text not null default 'new' check (status in ('new','reviewing','closed')),
  constraint safety_reports_not_self check (reporter_id <> reported_id)
);
create index if not exists safety_reports_created_at_idx on public.safety_reports(created_at desc);
alter table public.safety_reports enable row level security;
revoke all on public.safety_reports from anon,authenticated;
-- Reports are written through a security-definer function; not publicly readable.
create or replace function public.report_ride_user(
  p_reported_id uuid,p_category text,p_details text,p_thread_id uuid default null,p_ride_id uuid default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_reporter uuid:=auth.uid();
begin
 if v_reporter is null or p_reported_id is null or p_reported_id=v_reporter then raise exception 'Invalid report'; end if;
 if p_category not in ('harassment','unsafe','fraud','discrimination','other')
    or char_length(btrim(coalesce(p_details,''))) not between 10 and 2000 then raise exception 'Invalid report details'; end if;
 if p_thread_id is not null then
   if not exists(select 1 from public.ride_messages m where m.thread_id=p_thread_id
     and v_reporter in (m.poster_id,m.visitor_id)
     and p_reported_id in (m.poster_id,m.visitor_id)) then raise exception 'Conversation not found'; end if;
 elsif p_ride_id is not null then
   if not exists(select 1 from public.rides r where r.id=p_ride_id and r.owner_id=p_reported_id) then raise exception 'Ride not found'; end if;
 else
   raise exception 'Report must reference a ride or conversation';
 end if;
 insert into public.safety_reports(reporter_id,reported_id,thread_id,ride_id,category,details)
 values(v_reporter,p_reported_id,p_thread_id,p_ride_id,p_category,btrim(p_details)) returning id into v_id;
 return v_id;
end; $$;
revoke all on function public.report_ride_user(uuid,text,text,uuid,uuid) from public,anon;
grant execute on function public.report_ride_user(uuid,text,text,uuid,uuid) to authenticated;

-- Replace the existing message function to enforce blocks on the server.
create or replace function public.send_ride_message(
 p_ride_id uuid,p_visitor_id uuid,p_subject text,p_body text,p_thread_id uuid default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_sender uuid:=auth.uid(); v_poster uuid; v_ride_id uuid; v_visitor uuid;
 v_subject text; v_thread uuid; v_existing public.ride_messages%rowtype;
begin
 if v_sender is null then raise exception 'Authentication required'; end if;
 if char_length(btrim(coalesce(p_body,''))) not between 1 and 1000
    or char_length(btrim(coalesce(p_subject,''))) not between 1 and 200 then raise exception 'Invalid message'; end if;
 if p_thread_id is null then
   select owner_id into v_poster from public.rides where id=p_ride_id;
   if v_poster is null or p_visitor_id is null or p_visitor_id=v_poster then raise exception 'Invalid ride or participants'; end if;
   if v_sender<>p_visitor_id then raise exception 'Only a prospective rider can start a thread'; end if;
   v_thread:=gen_random_uuid();v_ride_id:=p_ride_id;v_visitor:=p_visitor_id;v_subject:=p_subject;
 else
   select * into v_existing from public.ride_messages where thread_id=p_thread_id order by sent_at,id limit 1;
   if not found or v_sender not in (v_existing.poster_id,v_existing.visitor_id)
      or p_visitor_id is distinct from v_existing.visitor_id
      or p_ride_id is distinct from v_existing.ride_id then raise exception 'Not a participant in this thread'; end if;
   v_thread:=p_thread_id;v_ride_id:=v_existing.ride_id;v_poster:=v_existing.poster_id;
   v_visitor:=v_existing.visitor_id;v_subject:=v_existing.subject;
 end if;
 if exists(select 1 from public.blocked_users b
   where (b.blocker_id=v_poster and b.blocked_id=v_visitor)
      or (b.blocker_id=v_visitor and b.blocked_id=v_poster)) then
   raise exception 'Messaging is unavailable between these accounts';
 end if;
 insert into public.ride_messages(thread_id,ride_id,poster_id,visitor_id,sender_id,subject,body)
 values(v_thread,v_ride_id,v_poster,v_visitor,v_sender,v_subject,p_body);
 return v_thread;
end; $$;
revoke all on function public.send_ride_message(uuid,uuid,text,text,uuid) from public,anon;
grant execute on function public.send_ride_message(uuid,uuid,text,text,uuid) to authenticated;
