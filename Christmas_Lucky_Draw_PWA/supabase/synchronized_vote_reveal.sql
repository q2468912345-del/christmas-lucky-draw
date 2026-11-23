-- Synchronized 10-second public winner reveal for Christmas Lucky Draw
begin;

alter table public.event_settings
  add column if not exists votes_published boolean not null default false,
  add column if not exists votes_publish_at timestamptz;

create or replace function public.public_event()
returns json
language sql
security definer
set search_path = public, extensions
as $$
  select json_build_object(
    'participant_limit', participant_limit,
    'participant_count', (select count(*) from public.participants),
    'draw_completed', draw_completed,
    'votes_published', votes_published,
    'votes_publish_at', votes_publish_at
  )
  from public.event_settings
  where id = true;
$$;

create or replace function public.admin_publish_votes(p_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not coalesce(public.admin_check(p_password), false) then
    raise exception '管理員密碼錯誤';
  end if;

  if not coalesce((select draw_completed from public.event_settings where id = true), false) then
    raise exception '請先完成抽籤並開放投票';
  end if;

  if coalesce((select votes_published from public.event_settings where id = true), false) then
    return true;
  end if;

  update public.event_settings
  set votes_published = true,
      votes_publish_at = now()
  where id = true;

  return true;
end;
$$;

create or replace function public.public_top_three()
returns table(
  rank integer,
  participant_id uuid,
  display_name text,
  draw_number integer,
  submitted_gift text,
  vote_count bigint
)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not coalesce((select votes_published from public.event_settings where id = true), false) then
    raise exception '投票結果尚未公布';
  end if;

  return query
  select
    row_number() over(order by count(v.id) desc, p.draw_number)::integer,
    p.id,
    p.display_name,
    p.draw_number,
    p.submitted_gift,
    count(v.id)::bigint
  from public.participants p
  left join public.gift_votes v on v.target_participant_id = p.id
  group by p.id, p.display_name, p.draw_number, p.submitted_gift
  order by count(v.id) desc, p.draw_number
  limit 3;
end;
$$;

create or replace function public.admin_reset_event(p_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform pg_advisory_xact_lock(817263);

  if not coalesce(public.admin_check(p_password), false) then
    raise exception '管理員密碼錯誤';
  end if;

  delete from public.participants where true;

  update public.gift_numbers
  set gift_name = '',
      updated_at = now()
  where true;

  update public.event_settings
  set draw_completed = false,
      votes_published = false,
      votes_publish_at = null
  where id = true;

  return true;
end;
$$;

revoke all on function public.public_top_three() from public;
revoke all on function public.admin_publish_votes(text) from public;
grant execute on function public.public_top_three() to anon, authenticated;
grant execute on function public.admin_publish_votes(text) to anon, authenticated;

commit;
