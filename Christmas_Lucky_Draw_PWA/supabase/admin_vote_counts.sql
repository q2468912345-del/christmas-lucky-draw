-- Hide vote totals from public clients.
-- Only callers who provide the valid admin password can retrieve totals.
create or replace function public.admin_vote_counts(p_password text)
returns table(gift_number integer, vote_count bigint)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not coalesce(public.admin_check(p_password), false) then
    raise exception '管理員密碼錯誤';
  end if;

  return query
  select g.number, count(v.id)::bigint
  from public.gift_numbers g
  left join public.gift_votes v on v.gift_number = g.number
  group by g.number
  order by g.number;
end;
$$;

-- Prevent anonymous users from calling the old public count endpoint.
revoke all on function public.public_vote_counts() from public, anon, authenticated;
revoke all on function public.admin_vote_counts(text) from public;
grant execute on function public.admin_vote_counts(text) to anon, authenticated;
