-- Sync unread conversation markers across devices.
create table if not exists public.message_read_state (
  user_id uuid not null references auth.users(id) on delete cascade,
  thread_id uuid not null,
  last_read_at timestamptz not null,
  primary key (user_id, thread_id)
);
alter table public.message_read_state enable row level security;
grant select, insert, update on public.message_read_state to authenticated;

create policy "Users see their own read markers"
  on public.message_read_state for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users create their own read markers"
  on public.message_read_state for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.ride_messages m
      where m.thread_id = message_read_state.thread_id
        and (select auth.uid()) in (m.poster_id,m.visitor_id)
    )
  );
create policy "Users update their own read markers"
  on public.message_read_state for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
