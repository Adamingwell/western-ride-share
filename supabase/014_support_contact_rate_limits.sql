create table public.support_contact_rate_limits (
  client_key text not null,
  window_start timestamptz not null,
  primary key (client_key, window_start)
);
alter table public.support_contact_rate_limits enable row level security;
revoke all on public.support_contact_rate_limits from public, anon, authenticated;
grant insert, delete on public.support_contact_rate_limits to service_role;