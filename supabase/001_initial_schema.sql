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
-- Inserts are validated against the ride owner and existing thread membership.
-- The sender must be the authenticated user. First messages must come from the visitor.
create policy "Participants can send messages" on public.ride_messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.rides r
      where r.id = ride_id and r.owner_id = poster_id
    )
    and (
      (
        sender_id = visitor_id
        and not exists (
          select 1 from public.ride_messages prior
          where prior.thread_id = ride_messages.thread_id
        )
      )
      or (
        exists (
          select 1 from public.ride_messages prior
          where prior.thread_id = ride_messages.thread_id
            and prior.ride_id = ride_messages.ride_id
            and prior.poster_id = ride_messages.poster_id
            and prior.visitor_id = ride_messages.visitor_id
        )
      )
    )
  );

create policy "Users read own notification preference" on public.notification_preferences
  for select to authenticated using (user_id = (select auth.uid()));
create policy "Users create own notification preference" on public.notification_preferences
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Users update own notification preference" on public.notification_preferences
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
