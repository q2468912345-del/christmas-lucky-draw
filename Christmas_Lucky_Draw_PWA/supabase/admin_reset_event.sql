-- Add admin-only full reset for Christmas Lucky Draw.
-- Clears all participant records and gift names.
-- Preserves event_settings (participant_limit and admin_password_hash) and gift number rows.
create or replace function public.admin_reset_event(p_password text)
returns boolean
language plpgsql
security definer
set search_path=public,extensions
as $$
begin
  -- Serialize reset against concurrent draws and other reset operations.
  perform pg_advisory_xact_lock(817263);

  if not coalesce(public.admin_check(p_password), false) then
    raise exception '管理員密碼錯誤';
  end if;

  delete from public.participants where true;
  update public.gift_numbers
     set gift_name = '',
         updated_at = now();

  return true;
end;
$$;

revoke all on function public.admin_reset_event(text) from public;
grant execute on function public.admin_reset_event(text) to anon, authenticated;
