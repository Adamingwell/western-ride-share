-- Preserve private conversations when a ride listing is removed.
-- Run this migration in the existing Supabase project BEFORE deploying the updated board.
-- Existing conversations and message bodies remain intact.
alter table public.ride_messages drop constraint if exists ride_messages_ride_id_fkey;
alter table public.ride_messages alter column ride_id drop not null;
alter table public.ride_messages
  add constraint ride_messages_ride_id_fkey
  foreign key (ride_id) references public.rides(id) on delete set null;

-- A participant can remove a conversation from THEIR OWN inbox only.
-- A later message in the thread makes it appear again.
create table if not exists public.hidden_ride_conversations (
  user_id uuid not null references auth.users(id) on delete cascade,
  thread_id uuid not null,
  hidden_at timestamptz not null default now(),
  primary key (user_id,thread_id)
);
alter table public.hidden_ride_conversations enable row level security;
grant select, insert, update on public.hidden_ride_conversations to authenticated;
create policy "Participants read their own hidden conversations"
  on public.hidden_ride_conversations for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Participants hide their own conversations"
  on public.hidden_ride_conversations for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.ride_messages m
      where m.thread_id = hidden_ride_conversations.thread_id
      and (select auth.uid()) in (m.poster_id,m.visitor_id)
    )
  );
create policy "Participants update their own hidden conversations"
  on public.hidden_ride_conversations for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Replies use the existing thread's saved participants even after its ride is deleted.
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
  v_ride_id uuid;
  v_visitor uuid;
  v_subject text;
  v_thread uuid;
  v_existing public.ride_messages%rowtype;
begin
  if v_sender is null then raise exception 'Authentication required'; end if;
  if char_length(btrim(coalesce(p_body,''))) not between 1 and 1000
     or char_length(btrim(coalesce(p_subject,''))) not between 1 and 200 then
    raise exception 'Invalid message';
  end if;

  if p_thread_id is null then
    select owner_id into v_poster from public.rides where id = p_ride_id;
    if v_poster is null or p_visitor_id is null or p_visitor_id = v_poster then
      raise exception 'Invalid ride or participants';
    end if;
    if v_sender <> p_visitor_id then
      raise exception 'Only a prospective rider can start a thread';
    end if;
    v_thread := gen_random_uuid();
    v_ride_id := p_ride_id;
    v_visitor := p_visitor_id;
    v_subject := p_subject;
  else
    select * into v_existing from public.ride_messages
      where thread_id = p_thread_id order by sent_at,id limit 1;
    if not found or v_sender not in (v_existing.poster_id,v_existing.visitor_id)
       or p_visitor_id is distinct from v_existing.visitor_id
       or p_ride_id is distinct from v_existing.ride_id then
      raise exception 'Not a participant in this thread';
    end if;
    v_thread := p_thread_id;
    v_ride_id := v_existing.ride_id;
    v_poster := v_existing.poster_id;
    v_visitor := v_existing.visitor_id;
    v_subject := v_existing.subject;
  end if;

  insert into public.ride_messages
    (thread_id,ride_id,poster_id,visitor_id,sender_id,subject,body)
  values (v_thread,v_ride_id,v_poster,v_visitor,v_sender,v_subject,p_body);
  return v_thread;
end;
$$;
revoke all on function public.send_ride_message(uuid,uuid,text,text,uuid) from public,anon;
grant execute on function public.send_ride_message(uuid,uuid,text,text,uuid) to authenticated;
