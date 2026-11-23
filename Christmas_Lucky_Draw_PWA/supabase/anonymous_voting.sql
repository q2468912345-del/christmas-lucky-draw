-- Anonymous 3-vote system for Christmas Lucky Draw.
-- Each participant may vote for up to 3 distinct gifts. Votes are never exposed by voter.
create table if not exists public.gift_votes (
  id bigint generated always as identity primary key,
  participant_id uuid not null references public.participants(id) on delete cascade,
  gift_number integer not null references public.gift_numbers(number) on delete cascade,
  created_at timestamptz not null default now(),
  constraint gift_votes_one_vote_per_gift unique (participant_id, gift_number)
);

create index if not exists gift_votes_gift_number_idx
  on public.gift_votes(gift_number);

alter table public.gift_votes enable row level security;
revoke all on public.gift_votes from anon, authenticated, public;

create or replace function public.public_vote_counts()
returns table(gift_number integer, vote_count bigint)
language sql
security definer
set search_path = public
as $$
  select g.number, count(v.id)::bigint
  from public.gift_numbers g
  left join public.gift_votes v on v.gift_number = g.number
  group by g.number
  order by g.number;
$$;

create or replace function public.my_votes(p_participant_id uuid)
returns table(gift_number integer)
language sql
security definer
set search_path = public
as $$
  select v.gift_number
  from public.gift_votes v
  where v.participant_id = p_participant_id
  order by v.created_at, v.gift_number;
$$;

create or replace function public.cast_gift_vote(
  p_participant_id uuid,
  p_gift_number integer
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vote_count integer;
  v_limit integer;
  v_gift_name text;
begin
  -- Serialize vote writes so simultaneous requests cannot exceed 3 votes.
  perform pg_advisory_xact_lock(817264);

  if not exists (
    select 1 from public.participants where id = p_participant_id
  ) then
    raise exception '請先完成抽籤，再進行投票';
  end if;

  select participant_limit into v_limit
  from public.event_settings where id = true;

  select gift_name into v_gift_name
  from public.gift_numbers
  where number = p_gift_number
    and number between 1 and v_limit;

  if v_gift_name is null or btrim(v_gift_name) = '' then
    raise exception '這份禮物尚未設定，暫時不能投票';
  end if;

  if exists (
    select 1 from public.gift_votes
    where participant_id = p_participant_id
      and gift_number = p_gift_number
  ) then
    raise exception '你已經投過這份禮物，不能重複投票';
  end if;

  select count(*) into v_vote_count
  from public.gift_votes
  where participant_id = p_participant_id;

  if v_vote_count >= 3 then
    raise exception '每人只有 3 票，你的票數已用完';
  end if;

  insert into public.gift_votes(participant_id, gift_number)
  values (p_participant_id, p_gift_number);

  return json_build_object(
    'success', true,
    'remaining_votes', 2 - v_vote_count
  );
end;
$$;

revoke all on function public.public_vote_counts() from public;
revoke all on function public.my_votes(uuid) from public;
revoke all on function public.cast_gift_vote(uuid, integer) from public;

grant execute on function public.public_vote_counts() to anon, authenticated;
grant execute on function public.my_votes(uuid) to anon, authenticated;
grant execute on function public.cast_gift_vote(uuid, integer) to anon, authenticated;
