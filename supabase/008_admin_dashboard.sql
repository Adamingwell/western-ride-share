-- 008: restricted administrator review tools.
-- After running, grant your account access using the separate command below.
create table if not exists public.site_administrators (
 user_id uuid primary key references auth.users(id) on delete cascade,
 granted_at timestamptz not null default now()
);
alter table public.site_administrators enable row level security;
revoke all on public.site_administrators from public,anon,authenticated;

create table if not exists public.safety_report_audit (
 id bigint generated always as identity primary key,
 report_id uuid not null references public.safety_reports(id) on delete cascade,
 admin_id uuid not null references auth.users(id),
 old_status text not null,
 new_status text not null,
 changed_at timestamptz not null default now()
);
alter table public.safety_report_audit enable row level security;
revoke all on public.safety_report_audit from public,anon,authenticated;

create or replace function public.is_site_admin()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.site_administrators a where a.user_id=(select auth.uid()))
$$;
revoke all on function public.is_site_admin() from public,anon;
grant execute on function public.is_site_admin() to authenticated;

create or replace function public.admin_member_list(p_limit integer default 100,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.is_site_admin() then raise exception 'Access denied'; end if;
 return coalesce((select jsonb_agg(to_jsonb(t)) from (
  select u.id as user_id,u.email,u.email_confirmed_at,u.created_at,
         p.full_name,p.phone,
         (select count(*) from public.rides r where r.owner_id=u.id) as ride_count,
         (select count(*) from public.safety_reports s where s.reported_id=u.id) as reports_received
  from auth.users u left join public.member_profiles p on p.user_id=u.id
  order by u.created_at desc limit least(greatest(p_limit,1),100) offset greatest(p_offset,0)
 ) t),'[]'::jsonb);
end; $$;
revoke all on function public.admin_member_list(integer,integer) from public,anon;
grant execute on function public.admin_member_list(integer,integer) to authenticated;

create or replace function public.admin_report_list(p_limit integer default 100,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.is_site_admin() then raise exception 'Access denied'; end if;
 return coalesce((select jsonb_agg(to_jsonb(t)) from (
  select s.id,s.reporter_id,s.reported_id,s.thread_id,s.ride_id,
    s.category,s.details,s.created_at,s.status,
    reporter.email as reporter_email,reported.email as reported_email
  from public.safety_reports s
  left join auth.users reporter on reporter.id=s.reporter_id
  left join auth.users reported on reported.id=s.reported_id
  order by s.created_at desc limit least(greatest(p_limit,1),100) offset greatest(p_offset,0)
 ) t),'[]'::jsonb);
end; $$;
revoke all on function public.admin_report_list(integer,integer) from public,anon;
grant execute on function public.admin_report_list(integer,integer) to authenticated;

create or replace function public.admin_update_report_status(p_report_id uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
declare v_old text;
begin
 if not public.is_site_admin() then raise exception 'Access denied'; end if;
 if p_status not in ('new','reviewing','closed') then raise exception 'Invalid status'; end if;
 select status into v_old from public.safety_reports where id=p_report_id for update;
 if not found then raise exception 'Report not found'; end if;
 if v_old is distinct from p_status then
  update public.safety_reports set status=p_status where id=p_report_id;
  insert into public.safety_report_audit(report_id,admin_id,old_status,new_status)
   values(p_report_id,auth.uid(),v_old,p_status);
 end if;
end; $$;
revoke all on function public.admin_update_report_status(uuid,text) from public,anon;
grant execute on function public.admin_update_report_status(uuid,text) to authenticated;

-- Run separately after this migration, replacing the address with YOUR confirmed login:
-- insert into public.site_administrators(user_id)
-- select id from auth.users where lower(email)=lower('YOUR_EMAIL_HERE')
-- on conflict (user_id) do nothing;
-- Do not add admin privileges from browser code or user-editable signup metadata.
