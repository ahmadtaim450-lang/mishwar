-- ═══════════════════════════════════════════════════════════════════
-- مشوار: إشعارات الموبايل (FCM). كل إشعار بينحفظ بالجدول، وبينبعت push
-- عن طريق Edge Function "push" إذا كانت مفاتيحها مضبوطة بالـ Vault.
-- ═══════════════════════════════════════════════════════════════════

create table public.device_tokens (
  token text primary key check (char_length(token) between 20 and 4096),
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform text not null check (platform in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);
alter table public.device_tokens enable row level security;
revoke all on public.device_tokens from anon, authenticated;
grant select on public.device_tokens to authenticated;
create policy device_tokens_self on public.device_tokens for select to authenticated using (user_id = auth.uid());

create or replace function public.register_device(p_token text, p_platform text) returns void
language plpgsql security definer set search_path = public as $$
declare u uuid := public._uid();
begin
  if p_token is null or char_length(p_token) < 20 or p_platform not in ('android', 'ios', 'web') then perform public._fail('INVALID_INPUT'); end if;
  -- نفس الجهاز ممكن ينتقل لحساب تاني: التوكن بيصير للحساب الجديد
  insert into public.device_tokens (token, user_id, platform) values (p_token, u, p_platform)
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
  -- حد أعلى 5 أجهزة لكل حساب
  delete from public.device_tokens where user_id = u and token not in (
    select token from public.device_tokens where user_id = u order by updated_at desc limit 5);
end $$;

create or replace function public.unregister_device(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from public.device_tokens where token = p_token and user_id = auth.uid();
$$;

revoke execute on function public.register_device(text, text), public.unregister_device(text) from public, anon;
grant execute on function public.register_device(text, text), public.unregister_device(text) to authenticated;

-- مع كل إشعار جديد: نادِ دالة push (بدون ما يوقف الإدخال إذا ما في إعداد)
create or replace function public.dispatch_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_url text;
  v_key text;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then return new; end if;
  if not exists (select 1 from information_schema.tables where table_schema = 'vault' and table_name = 'decrypted_secrets') then return new; end if;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'functions_url'$q$ into v_url;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'push_secret'$q$ into v_key;
  if v_url is null or v_key is null then return new; end if;
  if not exists (select 1 from public.device_tokens where user_id = new.user_id) then return new; end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using v_url || '/push',
          jsonb_build_object('notification_id', new.id),
          jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_key);
  return new;
exception when others then
  -- الإشعار داخل التطبيق أهم من الـ push: ما منوقف شي
  return new;
end $$;

create trigger notifications_dispatch_push after insert on public.notifications
for each row execute function public.dispatch_push();

-- المراجع ما بتمنع حذف حساب المشرف
alter table public.driver_applications drop constraint if exists driver_applications_reviewed_by_fkey;
alter table public.driver_applications add constraint driver_applications_reviewed_by_fkey
  foreign key (reviewed_by) references public.profiles (id) on delete set null;
