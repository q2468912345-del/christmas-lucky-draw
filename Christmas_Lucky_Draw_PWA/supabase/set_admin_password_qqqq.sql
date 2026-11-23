-- Set the Christmas Lucky Draw administrator password to qqqq.
-- Run this once in Supabase SQL Editor. Existing participants, gifts, votes and settings are preserved.
begin;

update public.event_settings
set admin_password_hash = extensions.crypt('qqqq', extensions.gen_salt('bf'))
where id = true;

do $$
begin
  if not exists (select 1 from public.event_settings where id = true) then
    raise exception '找不到活動設定資料，未能更新管理員密碼';
  end if;
end $$;

commit;
