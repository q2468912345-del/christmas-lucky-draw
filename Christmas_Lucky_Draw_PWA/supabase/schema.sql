-- CHRISTMAS LUCKY DRAW 2026 - corrected schema V2
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.event_settings (
 id boolean primary key default true check (id),
 participant_limit integer not null default 25 check (participant_limit between 1 and 25),
 admin_password_hash text not null,
 created_at timestamptz not null default now()
);
create table if not exists public.participants (
 id uuid primary key,
 display_name text not null,
 name_key text not null unique,
 draw_number integer not null unique check (draw_number between 1 and 25),
 created_at timestamptz not null default now()
);
create table if not exists public.gift_numbers (
 number integer primary key check (number between 1 and 25),
 gift_name text not null default '',
 updated_at timestamptz not null default now()
);
alter table public.event_settings enable row level security;
alter table public.participants enable row level security;
alter table public.gift_numbers enable row level security;
revoke all on public.event_settings,public.participants,public.gift_numbers from anon,authenticated;

insert into public.event_settings(id,participant_limit,admin_password_hash)
values(true,25,extensions.crypt('CHANGE_TO_YOUR_OWN_PASSWORD',extensions.gen_salt('bf')))
on conflict(id) do nothing;
insert into public.gift_numbers(number,gift_name)
select n,'' from generate_series(1,25) n on conflict(number) do nothing;

create or replace function public.public_event()
returns json language sql security definer set search_path=public,extensions as $$
 select json_build_object('participant_limit',participant_limit) from public.event_settings where id=true;
$$;
create or replace function public.public_gifts()
returns table(number integer,gift_name text,participant_name text)
language sql security definer set search_path=public,extensions as $$
 select g.number,g.gift_name,p.display_name from public.gift_numbers g
 left join public.participants p on p.draw_number=g.number order by g.number;
$$;
create or replace function public.my_draw(p_participant_id uuid)
returns table(number integer,name text)
language sql security definer set search_path=public,extensions as $$
 select draw_number,display_name from public.participants where id=p_participant_id;
$$;
create or replace function public.draw_number(p_name text,p_participant_id uuid)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare v_number integer; v_limit integer; v_name text;
begin
 perform pg_advisory_xact_lock(817263);
 select participant_limit into v_limit from public.event_settings where id=true;
 if v_limit is null then raise exception '活動尚未初始化'; end if;
 select display_name,draw_number into v_name,v_number from public.participants where id=p_participant_id;
 if v_number is not null then return json_build_object('number',v_number,'name',v_name); end if;
 if length(trim(coalesce(p_name,'')))=0 then raise exception '請輸入姓名'; end if;
 if exists(select 1 from public.participants where name_key=lower(trim(p_name))) then raise exception '這個姓名已經抽過'; end if;
 if (select count(*) from public.participants)>=v_limit then raise exception '抽籤名額已滿'; end if;
 select n into v_number from generate_series(1,v_limit) n
 where not exists(select 1 from public.participants p where p.draw_number=n)
 order by random() limit 1;
 insert into public.participants(id,display_name,name_key,draw_number)
 values(p_participant_id,trim(p_name),lower(trim(p_name)),v_number);
 return json_build_object('number',v_number,'name',trim(p_name));
end $$;
create or replace function public.admin_check(p_password text)
returns boolean language sql security definer set search_path=public,extensions as $$
 select (admin_password_hash=extensions.crypt(p_password,admin_password_hash))
 from public.event_settings where id=true;
$$;
create or replace function public.admin_set_gift(p_password text,p_number integer,p_gift text)
returns boolean language plpgsql security definer set search_path=public,extensions as $$
begin
 if not coalesce(public.admin_check(p_password),false) then raise exception '管理員密碼錯誤'; end if;
 if p_number<1 or p_number>25 then raise exception '號碼超出範圍'; end if;
 update public.gift_numbers set gift_name=coalesce(p_gift,''),updated_at=now() where number=p_number;
 return true;
end $$;
create or replace function public.admin_set_limit(p_password text,p_limit integer)
returns boolean language plpgsql security definer set search_path=public,extensions as $$
declare v_used integer;
begin
 if not coalesce(public.admin_check(p_password),false) then raise exception '管理員密碼錯誤'; end if;
 if p_limit<1 or p_limit>25 then raise exception '人數必須介於 1 到 25 人'; end if;
 select count(*) into v_used from public.participants;
 if p_limit<v_used then raise exception '設定人數不可少於已抽籤人數'; end if;
 update public.event_settings set participant_limit=p_limit where id=true;
 return true;
end $$;
revoke all on function public.public_event(),public.public_gifts(),public.my_draw(uuid),public.draw_number(text,uuid),public.admin_check(text),public.admin_set_gift(text,integer,text),public.admin_set_limit(text,integer) from public;
grant execute on function public.public_event(),public.public_gifts(),public.my_draw(uuid),public.draw_number(text,uuid),public.admin_check(text),public.admin_set_gift(text,integer,text),public.admin_set_limit(text,integer) to anon,authenticated;
