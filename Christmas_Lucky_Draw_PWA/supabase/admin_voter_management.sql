-- Admin-only participant list and per-person vote reset.
-- Clearing votes restores that participant's three voting chances without changing their draw.
create or replace function public.admin_list_voters(p_password text)
returns table(
  participant_id uuid,
  display_name text,
  draw_number integer,
  vote_count bigint
)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not coalesce(public.admin_check(p_password), false) then
    raise exception '管理員密碼錯誤';
  end if;

  return query
  select p.id, p.display_name, p.draw_number, count(v.id)::bigint
  from public.participants p
  left join public.gift_votes v on v.participant_id = p.id
  group by p.id, p.display_name, p.draw_number
  order by p.draw_number;
end;
$$;

create or replace function public.admin_reset_participant_votes(
  p_password text,
  p_participant_id uuid
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_name text;
  v_deleted integer;
begin
  if not coalesce(public.admin_check(p_password), false) then
    raise exception '管理員密碼錯誤';
  end if;

  select display_name into v_name
  from public.participants
  where id = p_participant_id;

  if v_name is null then
    raise exception '找不到這位參加者';
  end if;

  delete from public.gift_votes
  where participant_id = p_participant_id;

  get diagnostics v_deleted = row_count;

  return json_build_object(
    'success', true,
    'participant_name', v_name,
    'deleted_votes', v_deleted,
    'remaining_votes', 3
  );
end;
$$;

revoke all on function public.admin_list_voters(text) from public;
revoke all on function public.admin_reset_participant_votes(text, uuid) from public;
grant execute on function public.admin_list_voters(text) to anon, authenticated;
grant execute on function public.admin_reset_participant_votes(text, uuid) to anon, authenticated;
