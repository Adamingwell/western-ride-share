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
