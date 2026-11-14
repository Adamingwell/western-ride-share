-- Run after 001_initial_schema.sql. Only the server-side Edge Function may write this table.
create table if not exists public.message_email_deliveries (
  message_id uuid primary key references public.ride_messages(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  status text not null check(status in ('pending','sent','failed')),
  provider_id text,
  created_at timestamptz not null default now()
);
alter table public.message_email_deliveries enable row level security;
revoke all on public.message_email_deliveries from anon, authenticated;
