-- 010: idempotent safety-report email delivery tracking.
-- Run this migration before deploying notify-safety-report.
create table if not exists public.safety_report_email_deliveries (
 report_id uuid primary key references public.safety_reports(id) on delete cascade,
 status text not null default 'pending' check (status in ('pending','sent','failed')),
 provider_id text,
 attempted_at timestamptz not null default now()
);
alter table public.safety_report_email_deliveries enable row level security;
revoke all on public.safety_report_email_deliveries from public,anon,authenticated;
-- Only the service-role Edge Function can read or write delivery state.

-- Required explicit table privileges for the Edge Function's service-role client.
-- Earlier migrations revoke public/anon/authenticated access to these private tables.
-- BYPASSRLS does not replace SQL table privileges.
grant select on table public.safety_reports to service_role;
grant select on table public.site_administrators to service_role;
grant select, insert, update on table public.safety_report_email_deliveries to service_role;
