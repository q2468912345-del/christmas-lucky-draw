-- Sequential, admin-controlled public reveal: 3rd -> 2nd -> 1st
begin;

alter table public.event_settings
  add column if not exists published_rank integer not null default 0;

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
    'votes_publish_at', votes_publish_at,
    'published_rank', published_rank
  )
  from public.event_settings
  where id = true;
$$;

create or replace function public.admin_publish_rank(p_password text, p_rank integer)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  current_rank integer;
begin
  if not coalesce(public.admin_check(p_password), false) then
    raise exception '管理員密碼錯誤';
  end if;

  if p_rank not in (1, 2, 3) then
    raise exception '名次只允許 3、2、1 名';
  end if;

  select published_rank into current_rank
  from public.event_settings
  where id = true
  for update;

  if not coalesce((select votes_published from public.event_settings where id = true), false) then
    raise exception '請先啟動公布流程並完成同步倒數';
  end if;

  if p_rank <> current_rank - 1 and not (current_rank = 0 and p_rank = 3) then
    raise exception '請依序公布第 3 名、第 2 名、第 1 名';
  end if;

  update public.event_settings
  set published_rank = p_rank
  where id = true;

  return p_rank;
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
      votes_publish_at = null,
      published_rank = 0
  where id = true;

  return true;
end;
$$;

revoke all on function public.admin_publish_rank(text, integer) from public;
grant execute on function public.admin_publish_rank(text, integer) to anon, authenticated;

commit;
