-- Christmas Lucky Draw: participant-submitted gifts and draw completion gate
begin;

alter table public.participants
  add column if not exists submitted_gift text not null default '';

alter table public.event_settings
  add column if not exists draw_completed boolean not null default false;

-- Carry over any legacy gift names where possible; new registrations store their own gift.
update public.participants p
set submitted_gift = g.gift_name
from public.gift_numbers g
where g.number = p.draw_number
  and btrim(coalesce(g.gift_name,'')) <> ''
  and btrim(coalesce(p.submitted_gift,'')) = '';

-- Migrate existing votes: old gift_number N becomes the participant who drew number N.
alter table public.gift_votes
  add column if not exists target_participant_id uuid;

update public.gift_votes v
set target_participant_id = p.id
from public.participants p
where p.draw_number = v.gift_number
  and v.target_participant_id is null;

-- Old votes without a matching participant cannot represent a participant gift.
delete from public.gift_votes where target_participant_id is null;

alter table public.gift_votes alter column gift_number drop not null;
alter table public.gift_votes
  add constraint gift_votes_target_participant_fk
  foreign key (target_participant_id) references public.participants(id) on delete cascade;

create unique index if not exists gift_votes_one_vote_per_target
  on public.gift_votes(participant_id,target_participant_id);
create index if not exists gift_votes_target_participant_idx
  on public.gift_votes(target_participant_id);

drop function if exists public.draw_number(text,uuid);
create or replace function public.draw_number(p_name text,p_participant_id uuid,p_submitted_gift text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare v_number integer; v_limit integer; v_name text; v_gift text;
begin
 perform pg_advisory_xact_lock(817263);
 select participant_limit into v_limit from public.event_settings where id=true;
 if v_limit is null then raise exception '活動尚未初始化'; end if;
 select display_name,draw_number,submitted_gift into v_name,v_number,v_gift
 from public.participants where id=p_participant_id;
 if v_number is not null then
   return json_build_object('number',v_number,'name',v_name,'gift',v_gift);
 end if;
 if coalesce((select draw_completed from public.event_settings where id=true),false) then
   raise exception '抽選已完畢，不能再登記';
 end if;
 if length(trim(coalesce(p_name,'')))=0 then raise exception '請輸入姓名'; end if;
 if length(trim(coalesce(p_submitted_gift,'')))=0 then raise exception '請輸入你準備的禮物'; end if;
 if exists(select 1 from public.participants where name_key=lower(trim(p_name))) then
   raise exception '這個姓名已經登記';
 end if;
 if (select count(*) from public.participants)>=v_limit then raise exception '登記名額已滿'; end if;
 select n into v_number from generate_series(1,v_limit) n
 where not exists(select 1 from public.participants p where p.draw_number=n)
 order by random() limit 1;
 insert into public.participants(id,display_name,name_key,draw_number,submitted_gift)
 values(p_participant_id,trim(p_name),lower(trim(p_name)),v_number,trim(p_submitted_gift));
 return json_build_object('number',v_number,'name',trim(p_name),'gift',trim(p_submitted_gift));
end $$;

create or replace function public.public_event()
returns json language sql security definer set search_path=public,extensions as $$
 select json_build_object(
   'participant_limit',participant_limit,
   'participant_count',(select count(*) from public.participants),
   'draw_completed',draw_completed
 ) from public.event_settings where id=true;
$$;

drop function if exists public.my_draw(uuid);
create function public.my_draw(p_participant_id uuid)
returns table(number integer,name text,submitted_gift text)
language sql security definer set search_path=public,extensions as $$
 select draw_number,display_name,participants.submitted_gift
 from public.participants where id=p_participant_id;
$$;

drop function if exists public.admin_list_voters(text);
create function public.admin_list_voters(p_password text)
returns table(participant_id uuid,display_name text,draw_number integer,submitted_gift text,vote_count bigint)
language plpgsql security definer set search_path=public,extensions as $$
begin
 if not coalesce(public.admin_check(p_password),false) then raise exception '管理員密碼錯誤'; end if;
 return query
 select p.id,p.display_name,p.draw_number,p.submitted_gift,count(v.id)::bigint
 from public.participants p
 left join public.gift_votes v on v.participant_id=p.id
 group by p.id,p.display_name,p.draw_number,p.submitted_gift
 order by p.draw_number;
end $$;

create or replace function public.public_revealed_participants()
returns table(participant_id uuid,display_name text,draw_number integer,submitted_gift text)
language plpgsql security definer set search_path=public,extensions as $$
begin
 if not coalesce((select draw_completed from public.event_settings where id=true),false) then
   raise exception '管理員尚未宣布抽選完畢';
 end if;
 return query
 select p.id,p.display_name,p.draw_number,p.submitted_gift
 from public.participants p order by p.draw_number;
end $$;

create or replace function public.admin_complete_draw(p_password text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare v_count integer; v_limit integer;
begin
 perform pg_advisory_xact_lock(817263);
 if not coalesce(public.admin_check(p_password),false) then raise exception '管理員密碼錯誤'; end if;
 select participant_limit into v_limit from public.event_settings where id=true;
 select count(*) into v_count from public.participants;
 if v_count<>v_limit then
   raise exception '目前完成登記 % / % 人，尚未全員登記，不能宣布抽選完畢',v_count,v_limit;
 end if;
 if exists(select 1 from public.participants where btrim(submitted_gift)='') then
   raise exception '仍有參加者未填寫禮物，不能宣布抽選完畢';
 end if;
 update public.event_settings set draw_completed=true where id=true;
 return json_build_object('success',true,'participant_count',v_count,'voting_open',true);
end $$;

create or replace function public.cast_gift_vote(p_participant_id uuid,p_target_participant_id uuid)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare v_count integer;
begin
 perform pg_advisory_xact_lock(817264);
 if not coalesce((select draw_completed from public.event_settings where id=true),false) then
   raise exception '管理員尚未宣布抽選完畢，投票尚未開放';
 end if;
 if not exists(select 1 from public.participants where id=p_participant_id) then
   raise exception '請先完成抽籤，再進行投票';
 end if;
 if not exists(select 1 from public.participants where id=p_target_participant_id) then
   raise exception '找不到這份禮物';
 end if;
 if exists(select 1 from public.gift_votes where participant_id=p_participant_id and target_participant_id=p_target_participant_id) then
   raise exception '你已經投過這份禮物，不能重複投票';
 end if;
 select count(*) into v_count from public.gift_votes where participant_id=p_participant_id;
 if v_count>=3 then raise exception '每人只有 3 票，你的票數已用完'; end if;
 insert into public.gift_votes(participant_id,target_participant_id)
 values(p_participant_id,p_target_participant_id);
 return json_build_object('success',true,'remaining_votes',2-v_count);
end $$;

drop function if exists public.my_votes(uuid);
create function public.my_votes(p_participant_id uuid)
returns table(target_participant_id uuid)
language sql security definer set search_path=public as $$
 select v.target_participant_id from public.gift_votes v
 where v.participant_id=p_participant_id
 order by v.created_at,v.target_participant_id;
$$;

drop function if exists public.admin_vote_counts(text);
create function public.admin_vote_counts(p_password text)
returns table(target_participant_id uuid,display_name text,draw_number integer,submitted_gift text,vote_count bigint)
language plpgsql security definer set search_path=public,extensions as $$
begin
 if not coalesce(public.admin_check(p_password),false) then raise exception '管理員密碼錯誤'; end if;
 return query
 select p.id,p.display_name,p.draw_number,p.submitted_gift,count(v.id)::bigint
 from public.participants p
 left join public.gift_votes v on v.target_participant_id=p.id
 group by p.id,p.display_name,p.draw_number,p.submitted_gift
 order by p.draw_number;
end $$;

create or replace function public.admin_reset_event(p_password text)
returns boolean language plpgsql security definer set search_path=public,extensions as $$
begin
 perform pg_advisory_xact_lock(817263);
 if not coalesce(public.admin_check(p_password),false) then raise exception '管理員密碼錯誤'; end if;
 delete from public.participants;
 update public.gift_numbers set gift_name='',updated_at=now();
 update public.event_settings set draw_completed=false where id=true;
 return true;
end $$;

revoke all on function public.public_revealed_participants() from public;
revoke all on function public.admin_complete_draw(text) from public;
revoke all on function public.draw_number(text,uuid,text) from public;
revoke all on function public.cast_gift_vote(uuid,uuid) from public;
revoke all on function public.my_votes(uuid) from public;
revoke all on function public.admin_vote_counts(text) from public;
revoke all on function public.admin_list_voters(text) from public;
revoke all on function public.admin_reset_event(text) from public;
grant execute on function public.public_revealed_participants() to anon,authenticated;
grant execute on function public.admin_complete_draw(text) to anon,authenticated;
grant execute on function public.draw_number(text,uuid,text) to anon,authenticated;
grant execute on function public.cast_gift_vote(uuid,uuid) to anon,authenticated;
grant execute on function public.my_votes(uuid) to anon,authenticated;
grant execute on function public.admin_vote_counts(text) to anon,authenticated;
grant execute on function public.admin_list_voters(text) to anon,authenticated;
grant execute on function public.admin_reset_event(text) to anon,authenticated;

-- Remove obsolete endpoints and signatures from the numbered-gift version.
revoke all on function public.public_vote_counts() from public,anon,authenticated;
revoke all on function public.cast_gift_vote(uuid,integer) from public,anon,authenticated;
revoke all on function public.draw_number(text,uuid) from public,anon,authenticated;
-- Remove public access to the obsolete numbered-gift API.
revoke all on function public.public_gifts() from public,anon,authenticated;
revoke all on function public.admin_set_gift(text,integer,text) from public,anon,authenticated;

commit;
