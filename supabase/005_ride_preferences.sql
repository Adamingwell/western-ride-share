-- Optional informational comfort preference on ride listings.
-- No gender information is collected about users and no messaging is blocked.
alter table public.rides
  add column if not exists ride_preference text not null default 'everyone';
alter table public.rides
  add constraint rides_ride_preference_check
  check (ride_preference in ('everyone','women','men'));
comment on column public.rides.ride_preference is
  'Informational ride-sharing comfort preference only; not an identity check or contact restriction.';
