-- 012: Revoke unsafe table capabilities and internal trigger RPC access.
-- This migration was applied to Supabase on 2026-11-14.
do $$
declare t record;
begin
 for t in select tablename from pg_tables where schemaname='public' loop
  execute format('revoke truncate, trigger, references on table public.%I from public, anon, authenticated',t.tablename);
 end loop;
end $$;
revoke execute on function public.create_member_profile() from public, anon, authenticated;
revoke execute on function public.enforce_message_not_suspended() from public, anon, authenticated;
revoke execute on function public.enforce_ride_not_suspended() from public, anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;