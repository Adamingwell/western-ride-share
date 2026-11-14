-- Western Ride Share: initial Supabase schema (new project only)
-- Run in Supabase SQL Editor after reviewing. Do not run against an existing populated schema.
create extension if not exists pgcrypto;

create table if not exists public.rides (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('Request', 'Offer')),
  direction text not null check (direction in ('campus', 'home')),
  community text not null,
  days text[] not null check (cardinality(days) between 1 and 7),
  time time not null,
  created_at timestamptz not null default now()
);
create index if not exists rides_owner_idx on public.rides(owner_id);

create table if not exists public.ride_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null,
  ride_id uuid not null references public.rides(id) on delete cascade,
  poster_id uuid not null references auth.users(id) on delete cascade,
  visitor_id uuid not null references auth.users(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  subject text not null,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  sent_at timestamptz not null default now(),
  constraint distinct_participants check (poster_id <> visitor_id),
  constraint sender_is_participant check (sender_id in (poster_id, visitor_id))
);
create index if not exists ride_messages_thread_idx on public.ride_messages(thread_id, sent_at);
create index if not exists ride_messages_ride_idx on public.ride_messages(ride_id);

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.rides enable row level security;
alter table public.ride_messages enable row level security;
alter table public.notification_preferences enable row level security;

create policy "Signed-in users can see rides" on public.rides
  for select to authenticated using (true);
create policy "Users create their own rides" on public.rides
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "Users delete their own rides" on public.rides
  for delete to authenticated using (owner_id = (select auth.uid()));
create policy "Users update their own rides" on public.rides
  for update to authenticated using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "Only conversation participants read messages" on public.ride_messages
  for select to authenticated
  using ((select auth.uid()) in (poster_id, visitor_id));
-- Message writes use a narrowly scoped function rather than direct table INSERT.
-- This prevents forged participants, mismatched threads, and RLS recursion.
create or replace function public.send_ride_message(
  p_ride_id uuid,
  p_visitor_id uuid,
  p_subject text,
  p_body text,
  p_thread_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sender uuid := auth.uid();
  v_poster uuid;
  v_thread uuid;
  v_existing public.ride_messages%rowtype;
begin
  if v_sender is null then
    raise exception 'Authentication required';
  end if;
  if char_length(btrim(coalesce(p_body, ''))) not between 1 and 1000
     or char_length(btrim(coalesce(p_subject, ''))) not between 1 and 200 then
    raise exception 'Invalid message';
  end if;

  select owner_id into v_poster from public.rides where id = p_ride_id;
  if v_poster is null or p_visitor_id is null or p_visitor_id = v_poster then
    raise exception 'Invalid ride or participants';
  end if;

  if p_thread_id is null then
    if v_sender <> p_visitor_id then
      raise exception 'Only a prospective rider can start a thread';
    end if;
    v_thread := gen_random_uuid();
  else
    select * into v_existing from public.ride_messages
      where thread_id = p_thread_id
      order by sent_at, id limit 1;
    if not found
       or v_existing.ride_id <> p_ride_id
       or v_existing.poster_id <> v_poster
       or v_existing.visitor_id <> p_visitor_id
       or v_sender not in (v_poster, p_visitor_id) then
      raise exception 'Not a participant in this thread';
    end if;
    v_thread := p_thread_id;
  end if;

  insert into public.ride_messages
    (thread_id, ride_id, poster_id, visitor_id, sender_id, subject, body)
  values
    (v_thread, p_ride_id, v_poster, p_visitor_id, v_sender, p_subject, p_body);
  return v_thread;
end;
$$;

revoke all on function public.send_ride_message(uuid, uuid, text, text, uuid) from public;
revoke all on function public.send_ride_message(uuid, uuid, text, text, uuid) from anon;
grant execute on function public.send_ride_message(uuid, uuid, text, text, uuid) to authenticated;

create policy "Users read own notification preference" on public.notification_preferences
  for select to authenticated using (user_id = (select auth.uid()));
create policy "Users create own notification preference" on public.notification_preferences
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Users update own notification preference" on public.notification_preferences
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
