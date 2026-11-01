-- ═══════════════════════════════════════════════════════════════════
-- مشوار: محفظة السائق (نفس نظام يانغو / يلا غو)
--  · الراكب بيدفع للسائق كاش، والعمولة بتنخصم من رصيد السائق لحظة تأكيد الحجز
--  · الحجز اللي بينلغى قبل الانطلاق بترجع عمولتو
--  · الرصيد ما بيكفي = ما بيقدر يقبل حجوزات، والحجز الفوري بيتسكّر لحالو
--  · الشحن: طلب شحن (شام كاش، سيريتل كاش، MTN كاش) بتوافق عليه الإدارة، أو عند وكيل معتمد
--  · كل حركة بسجل (ledger) ما بينعدّل ولا بينحذف، والرصيد محسوب منو
--  · جاهز للدفع أونلاين لاحقاً: أرباح بتدخل للرصيد، وتسوية (payout) بتطلع منو
-- ═══════════════════════════════════════════════════════════════════

-- ── الإعدادات (بتتغير من لوحة الإدارة) ─────────────────────────────
create table public.app_settings (
  key text primary key check (key ~ '^[a-z_]{2,40}$'),
  value jsonb not null,
  updated_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;
create policy app_settings_read on public.app_settings for select to authenticated using (true);
revoke all on public.app_settings from anon, authenticated;
grant select on public.app_settings to authenticated;

insert into public.app_settings (key, value) values
  ('commission_pct', '8'),          -- نسبة العمولة من سعر المقاعد
  ('commission_min_syp', '2000'),   -- أقل عمولة للحجز
  ('credit_limit_syp', '0'),        -- قديش مسموح الرصيد ينزل تحت الصفر
  ('topup_min_syp', '10000'),
  ('topup_max_syp', '5000000'),
  ('payment_accounts', '{}')        -- أرقام محافظ مشوار للشحن: {"sham_cash": "...", "syriatel_cash": "...", "mtn_cash": "..."}
on conflict (key) do nothing;

create or replace function public._setting_int(p_key text, p_default int) returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::int from public.app_settings where key = p_key), p_default);
$$;

-- ── المحفظة والسجل ────────────────────────────────────────────────
create type public.wallet_entry_kind as enum ('topup', 'commission', 'refund', 'adjustment', 'earning', 'payout');
create type public.topup_method as enum ('sham_cash', 'syriatel_cash', 'mtn_cash', 'agent', 'office');

create table public.wallets (
  driver_id uuid primary key references public.profiles (id) on delete cascade,
  balance_syp bigint not null default 0,
  updated_at timestamptz not null default now()
);

create table public.wallet_ledger (
  id bigint generated always as identity primary key,
  driver_id uuid not null references public.profiles (id) on delete cascade,
  kind public.wallet_entry_kind not null,
  amount_syp bigint not null check (amount_syp <> 0 and abs(amount_syp) <= 100000000),
  balance_after bigint not null,
  booking_id uuid references public.bookings (id) on delete set null,
  topup_id uuid,
  note text check (note is null or char_length(note) <= 300),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  check ((kind in ('topup', 'refund', 'earning') and amount_syp > 0) or (kind in ('commission', 'payout') and amount_syp < 0) or kind = 'adjustment')
);
create index wallet_ledger_driver_idx on public.wallet_ledger (driver_id, created_at desc);
create index wallet_ledger_booking_idx on public.wallet_ledger (booking_id) where booking_id is not null;
-- عمولة وحدة واسترجاع واحد بالكتير لكل حجز
create unique index wallet_ledger_one_commission on public.wallet_ledger (booking_id) where kind = 'commission';
create unique index wallet_ledger_one_refund on public.wallet_ledger (booking_id) where kind = 'refund';

-- السجل ما بيتعدّل ولا بينحذف (حتى من الإدارة): التصحيح بحركة جديدة
create or replace function public._ledger_immutable() returns trigger language plpgsql as $$
begin
  raise exception 'LEDGER_IMMUTABLE' using errcode = 'P0001';
end $$;
create trigger wallet_ledger_no_update before update or delete on public.wallet_ledger for each row execute function public._ledger_immutable();

-- الوكلاء المعتمدين (محل أو مكتب كراج بيقبض كاش وبيشحن للسائقين)
create table public.wallet_agents (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  label text not null check (char_length(label) between 2 and 80),
  city_id text references public.cities (id),
  daily_limit_syp bigint not null default 2000000 check (daily_limit_syp > 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- طلبات الشحن (تحويل لمحفظة مشوار وبعدين الإدارة بتتأكد وبتوافق)
create type public.topup_status as enum ('pending', 'approved', 'rejected');
create table public.topup_requests (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles (id) on delete cascade,
  amount_syp bigint not null check (amount_syp > 0),
  method public.topup_method not null,
  reference text not null check (char_length(reference) between 3 and 80),
  status public.topup_status not null default 'pending',
  review_note text check (review_note is null or char_length(review_note) <= 300),
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index topup_requests_status_idx on public.topup_requests (status, created_at);
create index topup_requests_driver_idx on public.topup_requests (driver_id, created_at desc);
-- نفس رقم العملية ما بينستعمل مرتين (منع الشحن المكرر)
create unique index topup_requests_reference_once on public.topup_requests (method, lower(reference)) where status <> 'rejected';

alter table public.wallets enable row level security;
alter table public.wallet_ledger enable row level security;
alter table public.wallet_agents enable row level security;
alter table public.topup_requests enable row level security;
create policy wallets_read on public.wallets for select to authenticated using (driver_id = auth.uid() or public.is_staff());
create policy wallet_ledger_read on public.wallet_ledger for select to authenticated using (driver_id = auth.uid() or public.is_staff());
create policy wallet_agents_read on public.wallet_agents for select to authenticated using (user_id = auth.uid() or public.is_staff());
create policy topup_requests_read on public.topup_requests for select to authenticated using (driver_id = auth.uid() or public.is_staff());
revoke all on public.wallets, public.wallet_ledger, public.wallet_agents, public.topup_requests from anon, authenticated;
grant select on public.wallets, public.wallet_ledger, public.wallet_agents, public.topup_requests to authenticated;

-- ── الحركة الأساسية: كل تغيير بالرصيد بيمرق من هون ────────────────
create or replace function public._wallet_post(p_driver uuid, p_kind public.wallet_entry_kind, p_amount bigint,
  p_booking uuid default null, p_topup uuid default null, p_note text default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_balance bigint;
  v_limit int := public._setting_int('credit_limit_syp', 0);
begin
  insert into public.wallets (driver_id) values (p_driver) on conflict (driver_id) do nothing;
  select balance_syp into v_balance from public.wallets where driver_id = p_driver for update;
  v_balance := v_balance + p_amount;
  update public.wallets set balance_syp = v_balance, updated_at = now() where driver_id = p_driver;
  insert into public.wallet_ledger (driver_id, kind, amount_syp, balance_after, booking_id, topup_id, note, created_by)
  values (p_driver, p_kind, p_amount, v_balance, p_booking, p_topup, public._clean(p_note, 300), auth.uid());

  -- الرصيد ما عاد بيكفي لعمولة حجز: منسكّر الحجز الفوري ومنبلّغ السائق مرة وحدة
  if p_amount < 0 and v_balance - public._setting_int('commission_min_syp', 2000) < -v_limit then
    update public.trips set instant = false, updated_at = now() where driver_id = p_driver and status = 'scheduled' and instant;
    if v_balance - p_amount - public._setting_int('commission_min_syp', 2000) >= -v_limit then
      perform public._notify(p_driver, 'wallet.low', 'رصيدك خلص تقريباً', 'اشحن رصيدك لحتى تقدر تقبل حجوزات جديدة', jsonb_build_object('balance', v_balance));
    end if;
  end if;
  return v_balance;
end $$;

-- عمولة الحجز: نسبة من سعر المقاعد، مع حد أدنى
create or replace function public._commission(p_booking uuid) returns bigint
language sql stable security definer set search_path = public as $$
  select greatest(public._setting_int('commission_min_syp', 2000)::bigint,
                  round(coalesce(b.price_syp, t.price_syp) * b.seats * public._setting_int('commission_pct', 8) / 100.0)::bigint)
  from public.bookings b join public.trips t on t.id = b.trip_id where b.id = p_booking;
$$;

-- هل الرصيد بيكفي لعمولة معيّنة؟
create or replace function public._wallet_can_pay(p_driver uuid, p_amount bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select balance_syp from public.wallets where driver_id = p_driver), 0) - p_amount >= -public._setting_int('credit_limit_syp', 0);
$$;

-- ── ربط الحجوزات بالمحفظة (بالتريغر: ما بيهم من وين انأكّد الحجز) ─
create or replace function public._booking_wallet_check() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_driver uuid;
  v_fee bigint;
begin
  if new.status = 'confirmed' and (tg_op = 'INSERT' or old.status is distinct from 'confirmed') then
    select driver_id into v_driver from public.trips where id = new.trip_id;
    v_fee := greatest(public._setting_int('commission_min_syp', 2000)::bigint,
                      round(coalesce(new.price_syp, (select price_syp from public.trips where id = new.trip_id)) * new.seats * public._setting_int('commission_pct', 8) / 100.0)::bigint);
    if not public._wallet_can_pay(v_driver, v_fee) then perform public._fail('WALLET_LOW'); end if;
  end if;
  return new;
end $$;

create or replace function public._booking_wallet_post() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  t public.trips;
  v_fee bigint;
begin
  select * into t from public.trips where id = new.trip_id;
  -- تأكيد: عمولة
  if new.status = 'confirmed' and (tg_op = 'INSERT' or old.status is distinct from 'confirmed') then
    if not exists (select 1 from public.wallet_ledger where booking_id = new.id and kind = 'commission') then
      perform public._wallet_post(t.driver_id, 'commission', -public._commission(new.id), new.id, null,
        'حجز ' || new.seats || ' مقعد · ' || public._city_name(coalesce(new.from_city, t.from_city)) || ' ← ' || public._city_name(coalesce(new.to_city, t.to_city)));
    end if;
  end if;
  -- إلغاء حجز مؤكد قبل الانطلاق: العمولة بترجع
  if tg_op = 'UPDATE' and old.status = 'confirmed' and new.status = 'cancelled' and now() < t.departure_at + interval '30 minutes' then
    select -amount_syp into v_fee from public.wallet_ledger where booking_id = new.id and kind = 'commission';
    if v_fee is not null and not exists (select 1 from public.wallet_ledger where booking_id = new.id and kind = 'refund') then
      perform public._wallet_post(t.driver_id, 'refund', v_fee, new.id, null, 'استرجاع عمولة حجز ملغى');
    end if;
  end if;
  return null;
end $$;

create trigger bookings_wallet_check before insert or update of status on public.bookings
  for each row execute function public._booking_wallet_check();
create trigger bookings_wallet_post after insert or update of status on public.bookings
  for each row execute function public._booking_wallet_post();

-- الحجز الفوري بيشتغل بس إذا الرصيد بيكفي لعمولة مقعد واحد عالأقل
create or replace function public._trip_instant_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.instant and new.status = 'scheduled'
     and not public._wallet_can_pay(new.driver_id, greatest(public._setting_int('commission_min_syp', 2000)::bigint,
                                                             round(new.price_syp * public._setting_int('commission_pct', 8) / 100.0)::bigint)) then
    new.instant := false;
  end if;
  return new;
end $$;
create trigger trips_instant_guard before insert or update of instant on public.trips
  for each row execute function public._trip_instant_guard();

-- ── للسائق ────────────────────────────────────────────────────────
create or replace function public.my_wallet() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  u uuid := public._uid();
  v_balance bigint := coalesce((select balance_syp from public.wallets where driver_id = u), 0);
  v_min int := public._setting_int('commission_min_syp', 2000);
  v_limit int := public._setting_int('credit_limit_syp', 0);
begin
  return jsonb_build_object(
    'balance', v_balance,
    'commission_pct', public._setting_int('commission_pct', 8),
    'commission_min', v_min,
    'credit_limit', v_limit,
    'can_accept', v_balance - v_min >= -v_limit,
    'topup_min', public._setting_int('topup_min_syp', 10000),
    'topup_max', public._setting_int('topup_max_syp', 5000000),
    'accounts', coalesce((select value from public.app_settings where key = 'payment_accounts'), '{}'::jsonb),
    'month_commission', coalesce((select -sum(amount_syp) from public.wallet_ledger where driver_id = u and kind = 'commission'
                                   and created_at >= date_trunc('month', now() at time zone 'Asia/Damascus') at time zone 'Asia/Damascus'), 0)
                        - coalesce((select sum(amount_syp) from public.wallet_ledger where driver_id = u and kind = 'refund'
                                   and created_at >= date_trunc('month', now() at time zone 'Asia/Damascus') at time zone 'Asia/Damascus'), 0),
    'entries', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'kind', l.kind, 'amount', l.amount_syp, 'balance', l.balance_after,
                                  'note', l.note, 'at', l.created_at, 'booking_id', l.booking_id) order by l.created_at desc, l.id desc)
                         from (select * from public.wallet_ledger where driver_id = u order by created_at desc, id desc limit 50) l), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'amount', r.amount_syp, 'method', r.method, 'reference', r.reference,
                                  'status', r.status, 'note', r.review_note, 'at', r.created_at) order by r.created_at desc)
                          from (select * from public.topup_requests where driver_id = u order by created_at desc limit 20) r), '[]'::jsonb)
  );
end $$;

create or replace function public.request_topup(p_amount bigint, p_method public.topup_method, p_reference text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  v_ref text := public._clean(p_reference, 80);
  v_id uuid;
begin
  if (select driver_status from public.profiles where id = u) not in ('approved', 'suspended') then perform public._fail('NOT_APPROVED_DRIVER'); end if;
  if p_method not in ('sham_cash', 'syriatel_cash', 'mtn_cash') then perform public._fail('INVALID_INPUT'); end if;
  if p_amount is null or p_amount < public._setting_int('topup_min_syp', 10000) or p_amount > public._setting_int('topup_max_syp', 5000000) then
    perform public._fail('INVALID_AMOUNT');
  end if;
  if v_ref is null or char_length(v_ref) < 3 then perform public._fail('INVALID_INPUT'); end if;
  if (select count(*) from public.topup_requests where driver_id = u and status = 'pending') >= 3 then perform public._fail('TOPUP_PENDING_LIMIT'); end if;
  if exists (select 1 from public.topup_requests where method = p_method and lower(reference) = lower(v_ref) and status <> 'rejected') then
    perform public._fail('DUPLICATE_REFERENCE');
  end if;
  insert into public.topup_requests (driver_id, amount_syp, method, reference) values (u, p_amount, p_method, v_ref) returning id into v_id;
  perform public._audit('wallet.topup_request', 'topup', v_id::text, jsonb_build_object('amount', p_amount, 'method', p_method));
  return v_id;
end $$;

-- ── للإدارة ───────────────────────────────────────────────────────
create or replace function public.admin_review_topup(p_request uuid, p_approve boolean, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.topup_requests;
begin
  if not public.is_admin() then perform public._fail('FORBIDDEN'); end if;
  select * into r from public.topup_requests where id = p_request for update;
  if not found then perform public._fail('NOT_FOUND'); end if;
  if r.status <> 'pending' then perform public._fail('INVALID_STATE'); end if;
  update public.topup_requests set status = case when p_approve then 'approved'::public.topup_status else 'rejected'::public.topup_status end,
    review_note = public._clean(p_note, 300), reviewed_by = auth.uid(), reviewed_at = now() where id = r.id;
  if p_approve then
    perform public._wallet_post(r.driver_id, 'topup', r.amount_syp, null, r.id, 'شحن ' || r.method || ' · ' || r.reference);
    perform public._notify(r.driver_id, 'wallet.topup', 'انشحن رصيدك', 'انضاف ' || r.amount_syp || ' ل.س لرصيدك', jsonb_build_object('request_id', r.id));
  else
    perform public._notify(r.driver_id, 'wallet.topup_rejected', 'ما انقبل طلب الشحن', coalesce(public._clean(p_note, 300), 'تأكد من رقم العملية والمبلغ'), jsonb_build_object('request_id', r.id));
  end if;
  perform public._audit(case when p_approve then 'wallet.topup_approve' else 'wallet.topup_reject' end, 'topup', r.id::text, jsonb_build_object('amount', r.amount_syp));
end $$;

-- حركة يدوية: شحن بالمكتب، تصحيح، أرباح، أو تسوية
create or replace function public.admin_wallet_entry(p_driver uuid, p_kind public.wallet_entry_kind, p_amount bigint, p_note text) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v bigint;
begin
  if not public.is_admin() then perform public._fail('FORBIDDEN'); end if;
  if p_kind not in ('topup', 'adjustment', 'earning', 'payout') then perform public._fail('INVALID_INPUT'); end if;
  if p_amount is null or p_amount = 0 or abs(p_amount) > 100000000 then perform public._fail('INVALID_AMOUNT'); end if;
  if public._clean(p_note, 300) is null then perform public._fail('INVALID_INPUT'); end if;
  if not exists (select 1 from public.profiles where id = p_driver and driver_status <> 'none') then perform public._fail('NOT_FOUND'); end if;
  v := public._wallet_post(p_driver, p_kind, case when p_kind in ('topup', 'earning') then abs(p_amount) when p_kind = 'payout' then -abs(p_amount) else p_amount end,
    null, null, p_note);
  perform public._audit('wallet.entry', 'profile', p_driver::text, jsonb_build_object('kind', p_kind, 'amount', p_amount));
  return v;
end $$;

create or replace function public.admin_set_setting(p_key text, p_value jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then perform public._fail('FORBIDDEN'); end if;
  if p_key in ('commission_pct') and ((p_value #>> '{}')::numeric not between 0 and 30) then perform public._fail('INVALID_INPUT'); end if;
  if p_key in ('commission_min_syp', 'credit_limit_syp', 'topup_min_syp', 'topup_max_syp') and ((p_value #>> '{}')::numeric not between 0 and 100000000) then
    perform public._fail('INVALID_INPUT');
  end if;
  if p_key = 'payment_accounts' and jsonb_typeof(p_value) <> 'object' then perform public._fail('INVALID_INPUT'); end if;
  update public.app_settings set value = p_value, updated_by = auth.uid(), updated_at = now() where key = p_key;
  if not found then perform public._fail('NOT_FOUND'); end if;
  perform public._audit('settings.update', 'setting', p_key, jsonb_build_object('value', p_value));
end $$;

create or replace function public.admin_set_agent(p_user uuid, p_label text, p_city text, p_daily_limit bigint, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then perform public._fail('FORBIDDEN'); end if;
  if public._clean(p_label, 80) is null or coalesce(p_daily_limit, 0) <= 0 then perform public._fail('INVALID_INPUT'); end if;
  insert into public.wallet_agents (user_id, label, city_id, daily_limit_syp, active)
  values (p_user, public._clean(p_label, 80), p_city, p_daily_limit, coalesce(p_active, true))
  on conflict (user_id) do update set label = excluded.label, city_id = excluded.city_id, daily_limit_syp = excluded.daily_limit_syp, active = excluded.active;
  perform public._audit('wallet.agent', 'profile', p_user::text, jsonb_build_object('active', p_active, 'limit', p_daily_limit));
end $$;

-- إيرادات العمولات وأرقام المحفظة للوحة الإدارة
create or replace function public.admin_wallet_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m timestamptz := date_trunc('month', now() at time zone 'Asia/Damascus') at time zone 'Asia/Damascus';
begin
  if not public.is_staff() then perform public._fail('FORBIDDEN'); end if;
  return jsonb_build_object(
    'commission_month', coalesce((select -sum(amount_syp) from public.wallet_ledger where kind = 'commission' and created_at >= m), 0)
                        - coalesce((select sum(amount_syp) from public.wallet_ledger where kind = 'refund' and created_at >= m), 0),
    'topups_month', coalesce((select sum(amount_syp) from public.wallet_ledger where kind = 'topup' and created_at >= m), 0),
    'balances_total', coalesce((select sum(balance_syp) from public.wallets), 0),
    'drivers_low', (select count(*) from public.profiles p left join public.wallets w on w.driver_id = p.id
                    where p.driver_status = 'approved' and coalesce(w.balance_syp, 0) - public._setting_int('commission_min_syp', 2000) < -public._setting_int('credit_limit_syp', 0)),
    'pending_topups', (select count(*) from public.topup_requests where status = 'pending'),
    'agents', coalesce((select jsonb_agg(jsonb_build_object('user_id', a.user_id, 'label', a.label, 'city', a.city_id, 'active', a.active,
                 'month_total', coalesce((select sum(amount_syp) from public.wallet_ledger l where l.created_by = a.user_id and l.kind = 'topup' and l.created_at >= m), 0)))
               from public.wallet_agents a), '[]'::jsonb)
  );
end $$;

-- ── للوكيل المعتمد: بيقبض كاش من السائق وبيشحنلو فوراً ─────────────
create or replace function public.agent_topup(p_driver_phone text, p_amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  a public.wallet_agents;
  v_driver uuid;
  v_today bigint;
  v_balance bigint;
begin
  select * into a from public.wallet_agents where user_id = u and active;
  if not found then perform public._fail('FORBIDDEN'); end if;
  if p_amount is null or p_amount < public._setting_int('topup_min_syp', 10000) or p_amount > public._setting_int('topup_max_syp', 5000000) then
    perform public._fail('INVALID_AMOUNT');
  end if;
  select pp.id into v_driver from public.profile_private pp join public.profiles p on p.id = pp.id
  where regexp_replace(pp.phone, '[^0-9]', '', 'g') = regexp_replace(coalesce(p_driver_phone, ''), '[^0-9]', '', 'g')
    and char_length(regexp_replace(coalesce(p_driver_phone, ''), '[^0-9]', '', 'g')) >= 8
    and p.driver_status in ('approved', 'suspended');
  if v_driver is null then perform public._fail('DRIVER_NOT_FOUND'); end if;
  select coalesce(sum(amount_syp), 0) into v_today from public.wallet_ledger
  where created_by = u and kind = 'topup' and created_at >= date_trunc('day', now() at time zone 'Asia/Damascus') at time zone 'Asia/Damascus';
  if v_today + p_amount > a.daily_limit_syp then perform public._fail('AGENT_LIMIT'); end if;
  v_balance := public._wallet_post(v_driver, 'topup', p_amount, null, null, 'شحن عند الوكيل · ' || a.label);
  perform public._notify(v_driver, 'wallet.topup', 'انشحن رصيدك', 'انضاف ' || p_amount || ' ل.س عند ' || a.label, '{}'::jsonb);
  perform public._audit('wallet.agent_topup', 'profile', v_driver::text, jsonb_build_object('amount', p_amount));
  return jsonb_build_object('driver', (select full_name from public.profiles where id = v_driver), 'amount', p_amount);
end $$;

-- ── الصلاحيات ─────────────────────────────────────────────────────
revoke execute on function public._setting_int(text, int), public._wallet_post(uuid, public.wallet_entry_kind, bigint, uuid, uuid, text),
  public._commission(uuid), public._wallet_can_pay(uuid, bigint), public._booking_wallet_check(), public._booking_wallet_post(),
  public._trip_instant_guard(), public._ledger_immutable()
  from public, anon, authenticated;
revoke execute on function public.my_wallet(), public.request_topup(bigint, public.topup_method, text),
  public.admin_review_topup(uuid, boolean, text), public.admin_wallet_entry(uuid, public.wallet_entry_kind, bigint, text),
  public.admin_set_setting(text, jsonb), public.admin_set_agent(uuid, text, text, bigint, boolean), public.admin_wallet_stats(),
  public.agent_topup(text, bigint)
  from public, anon;
grant execute on function public.my_wallet(), public.request_topup(bigint, public.topup_method, text),
  public.admin_review_topup(uuid, boolean, text), public.admin_wallet_entry(uuid, public.wallet_entry_kind, bigint, text),
  public.admin_set_setting(text, jsonb), public.admin_set_agent(uuid, text, text, bigint, boolean), public.admin_wallet_stats(),
  public.agent_topup(text, bigint)
  to authenticated;
