-- 011: harden private-message write boundaries.
-- Apply after 006 and 009. No client code changes are needed.
-- The SECURITY DEFINER send_ride_message RPC remains the supported write path.
-- Prevent authenticated users from bypassing RPC participant and blocking checks.
revoke insert, update, delete on table public.ride_messages from anon, authenticated;
-- Explicitly disallow write operations for PUBLIC as well.
revoke insert, update, delete on table public.ride_messages from public;

-- Defense in depth: validate each inserted message even when a privileged
-- server-side function performs the write. RPC is responsible for checking
-- conversation membership, blocked accounts and suspension status.
create or replace function public.enforce_message_not_suspended() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_owner uuid;
begin
 if auth.uid() is null or new.sender_id is distinct from auth.uid()
 then raise exception 'Invalid message sender'; end if;
 if new.poster_id is null or new.visitor_id is null
    or new.poster_id = new.visitor_id
    or new.sender_id not in (new.poster_id,new.visitor_id)
 then raise exception 'Invalid conversation participants'; end if;
 select r.owner_id into v_owner from public.rides r where r.id=new.ride_id;
 if v_owner is distinct from new.poster_id then raise exception 'Invalid ride owner'; end if;
 if exists (
   select 1 from public.blocked_users b
   where (b.blocker_id=new.poster_id and b.blocked_id=new.visitor_id)
      or (b.blocker_id=new.visitor_id and b.blocked_id=new.poster_id)
 ) then raise exception 'Messaging is unavailable between these accounts'; end if;
 if public.is_account_suspended(new.sender_id)
    or public.is_account_suspended(new.poster_id)
    or public.is_account_suspended(new.visitor_id)
 then raise exception 'Messaging unavailable for this account'; end if;
 return new;
end; $$;

-- The trigger created in 009 already calls this function, so CREATE OR REPLACE
-- updates its behavior without dropping or disabling the existing trigger.
-- Note: revoking table grants does not remove permissive RLS policies.
-- Audit policies separately and confirm direct inserts fail for authenticated.
