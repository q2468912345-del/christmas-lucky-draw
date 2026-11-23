-- Christmas Lucky Draw: gift images, final vote submission, admin reopen, and result publication
begin;

alter table public.participants
  add column if not exists gift_image_url text not null default '',
  add column if not exists vote_submitted boolean not null default false;

alter table public.event_settings
  add column if not exists votes_published boolean not null default false;

-- Public image bucket for participant gift photos. Uploads are limited by the app to image files <= 5 MB.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('christmas-gift-images','christmas-gift-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "Anyone can upload Christmas gift images" on storage.objects;
create policy "Anyone can upload Christmas gift images"
on storage.objects for insert to anon,authenticated
with check (bucket_id='christmas-gift-images');

drop policy if exists "Anyone can view Christmas gift images" on storage.objects;
create policy "Anyone can view Christmas gift images"
on storage.objects for select to anon,authenticated
using (bucket_id='christmas-gift-images');

-- New registration signature includes the optional gift image URL.
drop function if exists public.draw_number(text,uuid,text);
drop function if exists public.draw_number(text,uuid,text,text);
create function public.draw_number(p_name text,p_participant_id uuid,p_submitted_gift text,p_gift_image_url text default '')
returns json language plpgsql security definer set search_path=public,extensions as $$
declare v_number integer; v_limit integer; v_name text; v_gift text; v_image text;
begin
 perform pg_advisory_xact_lock(817263);
 select participant_limit into v_limit from public.event_settings where id=true;
 if v_limit is null then raise exception '活動尚未初始化'; end if;
 select display_name,draw_number,submitted_gift,gift_image_url into v_name,v_number,v_gift,v_image
 from public.participants where id=p_participant_id;
 if v_number is not null then
   return json_build_object('number',v_number,'name',v_name,'gift',v_gift,'gift_image_url',v_image);
 end if;
 if coalesce((select draw_completed from public.event_settings where id=true),false) then raise exception '抽選已完畢，不能再登記'; end if;
 if length(trim(coalesce(p_name,'')))=0 then raise exception '請輸入姓名'; end if;
 if length(trim(coalesce(p_submitted_gift,'')))=0 then raise exception '請輸入你準備的禮物'; end if;
 if exists(select 1 from public.participants where name_key=lower(trim(p_name))) then raise exception '這個姓名已經登記'; end if;
 if (select count(*) from public.participants)>=v_limit then raise exception '登記名額已滿'; end if;
 select n into v_number from generate_series(1,v_limit) n
 where not exists(select 1 from public.participants p where p.draw_number=n)
 order by random() limit 1;
 insert into public.participants(id,display_name,name_key,draw_number,submitted_gift,gift_image_url)
 values(p_participant_id,trim(p_name),lower(trim(p_name)),v_number,trim(p_submitted_gift),coalesce(p_gift_image_url,''));
 return json_build_object('number',v_number,'name',trim(p_name),'gift',trim(p_submitted_gift),'gift_image_url',coalesce(p_gift_image_url,''));
end $$;

drop function if exists public.my_draw(uuid);
create function public.my_draw(p_participant_id uuid)
returns table(number integer,name text,submitted_gift text,gift_image_url text,vote_submitted boolean)
language sql security definer set search_path=public as $$
 select p.draw_number,p.display_name,p.submitted_gift,p.gift_image_url,p.vote_submitted
 from public.participants p where p.id=p_participant_id;
$$;

drop function if exists public.public_revealed_participants();
create function public.public_revealed_participants()
returns table(participant_id uuid,display_name text,draw_number integer,submitted_gift text,gift_image_url text)
language plpgsql security definer set search_path=public,extensions as $$
begin
 if not coalesce((select draw_completed from public.event_settings where id=true),false) then raise exception '管理員尚未宣布抽選完畢'; end if;
 return query select p.id,p.display_name,p.draw_number,p.submitted_gift,p.gift_image_url
 from public.participants p order by p.draw_number;
end $$;

drop function if exists public.admin_list_voters(text);
create function public.admin_list_voters(p_password text)
returns table(participant_id uuid,display_name text,draw_number integer,submitted_gift text,vote_count bigint,vote_submitted boolean)
language plpgsql security definer set search_path=public,extensions as $$
begin
 if not coalesce(public.admin_check(p_password),false) then raise exception '管理員密碼錯誤'; end if;
 return query
 select p.id,p.display_name,p.draw_number,p.submitted_gift,count(v.id)::bigint,p.vote_submitted
 from public.participants p left join public.gift_votes v on v.participant_id=p.id
 group by p.id,p.display_name,p.draw_number,p.submitted_gift,p.vote_submitted order by p.draw_number;
end $$;

create or replace function public.public_event()
returns json language sql security definer set search_path=public,extensions as $$
 select json_build_object(
   'participant_limit',participant_limit,
   'participant_count',(select count(*) from public.participants),
   'draw_completed',draw_completed,
   'votes_submitted_count',(select count(*) from public.participants where vote_submitted),
   'votes_all_submitted',(select count(*) from public.participants)>0 and (select count(*) from public.participants where vote_submitted)=(select count(*) from public.participants),
   'votes_published',votes_published
 ) from public.event_settings where id=true;
$$;

-- A participant submits 0-3 selected targets once. Empty submissions are rejected.
create or replace function public.submit_gift_votes(p_participant_id uuid,p_target_participant_ids uuid[])
returns json language plpgsql security definer set search_path=public,extensions as $$
declare v_count integer; v_target_count integer;
begin
 perform pg_advisory_xact_lock(817264);
 if not coalesce((select draw_completed from public.event_settings where id=true),false) then raise exception '投票尚未開放'; end if;
 if coalesce((select votes_published from public.event_settings where id=true),false) then raise exception '投票結果已公布，不能再送出'; end if;
 if not exists(select 1 from public.participants where id=p_participant_id) then raise exception '找不到參加者'; end if;
 if (select vote_submitted from public.participants where id=p_participant_id) then raise exception '你已送出投票，不能自行修改'; end if;
 v_target_count:=coalesce(array_length(p_target_participant_ids,1),0);
 if v_target_count<1 or v_target_count>3 then raise exception '請選擇 1 至 3 份禮物再送出'; end if;
 if (select count(distinct x) from unnest(p_target_participant_ids) x)<>v_target_count then raise exception '不可重複投給同一份禮物'; end if;
 if p_participant_id=any(p_target_participant_ids) then raise exception '不能投給自己的禮物'; end if;
 if exists(select 1 from unnest(p_target_participant_ids) x where not exists(select 1 from public.participants p where p.id=x)) then raise exception '投票目標不存在'; end if;
 insert into public.gift_votes(participant_id,target_participant_id)
 select p_participant_id,x from unnest(p_target_participant_ids) x;
 update public.participants set vote_submitted=true where id=p_participant_id;
 return json_build_object('success',true,'submitted_count',v_target_count);
end $$;

-- Admin may reopen one participant: their previous submitted votes are removed and they can submit again.
create or replace function public.admin_reopen_voting(p_password text,p_participant_id uuid)
returns boolean language plpgsql security definer set search_path=public,extensions as $$
begin
 if not coalesce(public.admin_check(p_password),false) then raise exception '管理員密碼錯誤'; end if;
 if coalesce((select votes_published from public.event_settings where id=true),false) then raise exception '投票結果公布後不能重新開放投票'; end if;
 delete from public.gift_votes where participant_id=p_participant_id;
 update public.participants set vote_submitted=false where id=p_participant_id;
 if not found then raise exception '找不到參加者'; end if;
 return true;
end $$;

create or replace function public.admin_publish_votes(p_password text)
returns boolean language plpgsql security definer set search_path=public,extensions as $$
declare v_total integer; v_submitted integer;
begin
 if not coalesce(public.admin_check(p_password),false) then raise exception '管理員密碼錯誤'; end if;
 select count(*),count(*) filter(where vote_submitted) into v_total,v_submitted from public.participants;
 if v_total=0 or v_total<>v_submitted then raise exception '尚有參加者未送出投票，不能公布'; end if;
 update public.event_settings set votes_published=true where id=true;
 return true;
end $$;

create or replace function public.admin_reset_event(p_password text)
returns boolean language plpgsql security definer set search_path=public,extensions as $$
begin
 perform pg_advisory_xact_lock(817263);
 if not coalesce(public.admin_check(p_password),false) then raise exception '管理員密碼錯誤'; end if;
 delete from public.participants where true;
 update public.gift_numbers set gift_name='',updated_at=now() where true;
 update public.event_settings set draw_completed=false,votes_published=false where id=true;
 return true;
end $$;

revoke all on function public.submit_gift_votes(uuid,uuid[]) from public;
revoke all on function public.admin_reopen_voting(text,uuid) from public;
revoke all on function public.admin_publish_votes(text) from public;
grant execute on function public.submit_gift_votes(uuid,uuid[]) to anon,authenticated;
grant execute on function public.admin_reopen_voting(text,uuid) to anon,authenticated;
grant execute on function public.admin_publish_votes(text) to anon,authenticated;

commit;
