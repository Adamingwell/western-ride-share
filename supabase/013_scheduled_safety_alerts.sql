-- Prerequisite: store the Supabase service_role key in Vault under
-- 'western_ride_share_service_role_key'. Never commit the actual key.
-- Run only after deploying process-safety-alerts with JWT verification enabled.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
select cron.schedule(
 'western-ride-share-safety-alerts',
 '*/5 * * * *',
 $job$
 select net.http_post(
  url := 'https://psvinzqgpnpzglropdkp.supabase.co/functions/v1/process-safety-alerts',
  headers := jsonb_build_object(
   'Content-Type','application/json',
   'Authorization','Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name='western_ride_share_service_role_key')
  ),
  body := '{}'::jsonb,
  timeout_milliseconds := 10000
 );
 $job$
);
