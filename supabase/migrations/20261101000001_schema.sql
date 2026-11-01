-- ═══════════════════════════════════════════════════════════════════
-- مشوار: البنية الأساسية لقاعدة البيانات
-- كل الكتابة الحساسة بتمرق من دوال RPC (02_functions)، والجداول محمية بـ RLS.
-- ═══════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- ── الأنواع ────────────────────────────────────────────────────────
create type public.gender as enum ('male', 'female');
create type public.app_role as enum ('user', 'moderator', 'admin');
create type public.driver_status as enum ('none', 'reviewing', 'interview', 'approved', 'rejected', 'suspended');
create type public.application_status as enum ('submitted', 'reviewing', 'interview', 'approved', 'rejected', 'cancelled');
create type public.document_kind as enum ('selfie', 'id_front', 'id_back', 'license', 'record', 'car_front', 'car_side', 'car_inside', 'mechanic');
create type public.ride_kind as enum ('men', 'women', 'family');
create type public.trip_status as enum ('scheduled', 'in_progress', 'completed', 'cancelled');
create type public.booking_status as enum ('pending', 'confirmed', 'rejected', 'cancelled', 'completed');
create type public.report_status as enum ('open', 'reviewed', 'dismissed');

-- ── المدن ──────────────────────────────────────────────────────────
create table public.cities (
  id text primary key check (id ~ '^[a-z_]{2,30}$'),
  name_ar text not null unique,
  lat double precision not null check (lat between 32 and 38),
  lon double precision not null check (lon between 35 and 43),
  spots text[] not null default '{}',
  active boolean not null default true
);

-- ── الملف الشخصي ───────────────────────────────────────────────────
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '' check (char_length(full_name) <= 80),
  gender public.gender,
  avatar_path text check (avatar_path is null or char_length(avatar_path) <= 200),
  role public.app_role not null default 'user',
  driver_status public.driver_status not null default 'none',
  rating_avg numeric(3, 2) not null default 0 check (rating_avg between 0 and 5),
  rating_count integer not null default 0 check (rating_count >= 0),
  trips_count integer not null default 0 check (trips_count >= 0),
  music_pref text check (music_pref in ('music', 'no_music', 'ask')),
  suspended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- بيانات خاصة (رقم الموبايل) منفصلة لحتى ما تنقرا مع الملف العام.
create table public.profile_private (
  id uuid primary key references public.profiles (id) on delete cascade,
  phone text check (phone is null or phone ~ '^\+?[0-9]{8,15}$'),
  emergency_contacts jsonb not null default '[]'::jsonb check (jsonb_typeof(emergency_contacts) = 'array'),
  updated_at timestamptz not null default now()
);

-- ── السيارات ───────────────────────────────────────────────────────
create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  make_model text not null check (char_length(make_model) between 2 and 60),
  year smallint not null check (year between 2005 and 2100),
  color text not null check (char_length(color) between 2 and 30),
  plate text not null check (char_length(plate) between 4 and 30),
  seats smallint not null default 4 check (seats between 1 and 7),
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  unique (plate)
);
create index vehicles_owner_idx on public.vehicles (owner_id);

-- ── طلبات الانضمام كسائق ───────────────────────────────────────────
create table public.driver_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  city_id text not null references public.cities (id),
  status public.application_status not null default 'submitted',
  interview_at timestamptz,
  interview_place text check (interview_place is null or char_length(interview_place) <= 200),
  agreed_rules_at timestamptz not null,
  admin_note text check (admin_note is null or char_length(admin_note) <= 1000),
  reviewed_by uuid references public.profiles (id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- طلب فعّال واحد بس لكل مستخدم
create unique index driver_applications_one_active
  on public.driver_applications (user_id)
  where status in ('submitted', 'reviewing', 'interview');
create index driver_applications_status_idx on public.driver_applications (status, created_at);

create table public.application_documents (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.driver_applications (id) on delete cascade,
  kind public.document_kind not null,
  storage_path text not null check (char_length(storage_path) <= 300),
  created_at timestamptz not null default now(),
  unique (application_id, kind)
);

-- ── الرحلات ────────────────────────────────────────────────────────
create table public.trips (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles (id) on delete cascade,
  vehicle_id uuid not null references public.vehicles (id),
  from_city text not null references public.cities (id),
  to_city text not null references public.cities (id),
  from_spot text not null check (char_length(from_spot) between 2 and 100),
  to_spot text not null check (char_length(to_spot) between 2 and 100),
  departure_at timestamptz not null,
  arrival_at timestamptz not null,
  price_syp integer not null check (price_syp between 1000 and 2000000),
  seats_total smallint not null check (seats_total between 1 and 7),
  seats_available smallint not null,
  kind public.ride_kind not null,
  instant boolean not null default false,
  prefs text[] not null default '{}' check (cardinality(prefs) <= 12),
  note text check (note is null or char_length(note) <= 500),
  status public.trip_status not null default 'scheduled',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (from_city <> to_city),
  check (arrival_at > departure_at),
  check (seats_available between 0 and seats_total)
);
create index trips_search_idx on public.trips (from_city, to_city, departure_at) where status = 'scheduled';
create index trips_driver_idx on public.trips (driver_id, departure_at desc);

create table public.trip_stops (
  trip_id uuid not null references public.trips (id) on delete cascade,
  position smallint not null check (position between 1 and 6),
  city_id text not null references public.cities (id),
  primary key (trip_id, position)
);

-- ── الحجوزات ───────────────────────────────────────────────────────
create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  rider_id uuid not null references public.profiles (id) on delete cascade,
  seats smallint not null check (seats between 1 and 7),
  family boolean not null default false,
  status public.booking_status not null default 'pending',
  pin char(4) not null check (pin ~ '^[0-9]{4}$'),
  message text check (message is null or char_length(message) <= 500),
  cancel_reason text check (cancel_reason is null or char_length(cancel_reason) <= 200),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  cancelled_at timestamptz
);
-- ما في حجزين فعّالين لنفس الراكب على نفس الرحلة
create unique index bookings_one_active on public.bookings (trip_id, rider_id) where status in ('pending', 'confirmed');
create index bookings_rider_idx on public.bookings (rider_id, created_at desc);
create index bookings_trip_idx on public.bookings (trip_id, status);

-- ── التقييمات والبلاغات ────────────────────────────────────────────
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  stars smallint not null check (stars between 1 and 5),
  tags text[] not null default '{}' check (cardinality(tags) <= 8),
  comment text check (comment is null or char_length(comment) <= 500),
  created_at timestamptz not null default now(),
  check (author_id <> target_id)
);
create index reviews_target_idx on public.reviews (target_id, created_at desc);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  trip_id uuid references public.trips (id) on delete set null,
  reason text not null check (char_length(reason) between 2 and 60),
  details text check (details is null or char_length(details) <= 1000),
  status public.report_status not null default 'open',
  created_at timestamptz not null default now(),
  check (reporter_id <> target_id)
);
create index reports_target_idx on public.reports (target_id, status, created_at);

-- ── الرسائل والإشعارات ─────────────────────────────────────────────
create table public.messages (
  id bigint generated always as identity primary key,
  booking_id uuid not null references public.bookings (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index messages_booking_idx on public.messages (booking_id, created_at);

create table public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null default '',
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

-- ── التتبع ومشاركة الموقع ───────────────────────────────────────────
create table public.live_locations (
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  lat double precision not null check (lat between -90 and 90),
  lon double precision not null check (lon between -180 and 180),
  accuracy real check (accuracy is null or accuracy >= 0),
  heading real,
  updated_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);

create table public.share_links (
  token text primary key default encode(gen_random_bytes(18), 'hex'),
  booking_id uuid not null references public.bookings (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete cascade,
  expires_at timestamptz not null,
  revoked boolean not null default false,
  created_at timestamptz not null default now()
);
create index share_links_booking_idx on public.share_links (booking_id);

-- ── سجل العمليات المهمة ─────────────────────────────────────────────
create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  entity text not null,
  entity_id text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_log_entity_idx on public.audit_log (entity, entity_id);

-- ═══════════════════════════════════════════════════════════════════
-- مساعدات عامة
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();
create trigger trips_touch before update on public.trips for each row execute function public.touch_updated_at();
create trigger applications_touch before update on public.driver_applications for each row execute function public.touch_updated_at();

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('moderator', 'admin'));
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- إنشاء الملف تلقائياً مع كل مستخدم جديد
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name) values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;
  insert into public.profile_private (id, phone) values (new.id, new.phone)
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

-- ═══════════════════════════════════════════════════════════════════
-- الصلاحيات: ما في كتابة مباشرة على الجداول، كلشي عن طريق RPC
-- ═══════════════════════════════════════════════════════════════════
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

alter table public.cities enable row level security;
alter table public.profiles enable row level security;
alter table public.profile_private enable row level security;
alter table public.vehicles enable row level security;
alter table public.driver_applications enable row level security;
alter table public.application_documents enable row level security;
alter table public.trips enable row level security;
alter table public.trip_stops enable row level security;
alter table public.bookings enable row level security;
alter table public.reviews enable row level security;
alter table public.reports enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;
alter table public.live_locations enable row level security;
alter table public.share_links enable row level security;
alter table public.audit_log enable row level security;

-- المدن: قراءة للجميع
grant select on public.cities to anon, authenticated;
create policy cities_read on public.cities for select using (active or public.is_staff());

-- الملفات: الاسم والتقييم مقروءين للمسجلين، والتعديل لحقول محددة بس
grant select on public.profiles to authenticated;
grant update (full_name, avatar_path, music_pref) on public.profiles to authenticated;
create policy profiles_read on public.profiles for select to authenticated using (true);
create policy profiles_update_self on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

grant select on public.profile_private to authenticated;
grant update (emergency_contacts) on public.profile_private to authenticated;
create policy private_self on public.profile_private for select to authenticated using (id = auth.uid() or public.is_staff());
create policy private_update_self on public.profile_private for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- السيارات: صاحبها والإدارة بس (الركاب بيشوفوا الرقم عن طريق RPC بعد التأكيد)
grant select on public.vehicles to authenticated;
create policy vehicles_read on public.vehicles for select to authenticated using (owner_id = auth.uid() or public.is_staff());

-- طلبات السائقين ووثائقها
grant select on public.driver_applications, public.application_documents to authenticated;
create policy applications_read on public.driver_applications for select to authenticated using (user_id = auth.uid() or public.is_staff());
create policy documents_read on public.application_documents for select to authenticated using (
  public.is_staff() or exists (select 1 from public.driver_applications a where a.id = application_id and a.user_id = auth.uid())
);

-- دوال مساعدة (security definer) لحتى ما تصير حلقة بين سياسات الرحلات والحجوزات
create or replace function public.is_trip_driver(p_trip uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.trips where id = p_trip and driver_id = auth.uid());
$$;

create or replace function public.has_booking_on(p_trip uuid, p_confirmed_only boolean default false) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.bookings
    where trip_id = p_trip and rider_id = auth.uid()
      and (not p_confirmed_only or status in ('confirmed', 'completed'))
  );
$$;

-- الرحلات: المجدولة مقروءة، والرحلات الخاصة بالسائق أو بحجوزاتي
grant select on public.trips, public.trip_stops to authenticated;
create policy trips_read on public.trips for select to authenticated using (
  status = 'scheduled' or driver_id = auth.uid() or public.is_staff() or public.has_booking_on(id)
);
create policy stops_read on public.trip_stops for select to authenticated using (
  exists (select 1 from public.trips t where t.id = trip_id)
);

-- الحجوزات: الراكب، وسائق الرحلة، والإدارة
grant select on public.bookings to authenticated;
create policy bookings_read on public.bookings for select to authenticated using (
  rider_id = auth.uid() or public.is_staff() or public.is_trip_driver(trip_id)
);

-- التقييمات: مقروءة للمسجلين
grant select on public.reviews to authenticated;
create policy reviews_read on public.reviews for select to authenticated using (true);

-- البلاغات: صاحب البلاغ والإدارة
grant select on public.reports to authenticated;
create policy reports_read on public.reports for select to authenticated using (reporter_id = auth.uid() or public.is_staff());

-- الرسائل: طرفي الحجز بس
create or replace function public.is_booking_party(p_booking uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.bookings b join public.trips t on t.id = b.trip_id
    where b.id = p_booking and (b.rider_id = auth.uid() or t.driver_id = auth.uid())
  );
$$;

grant select, insert on public.messages to authenticated;
create policy messages_read on public.messages for select to authenticated using (public.is_booking_party(booking_id) or public.is_staff());
create policy messages_insert on public.messages for insert to authenticated with check (
  sender_id = auth.uid() and public.is_booking_party(booking_id)
  and exists (select 1 from public.bookings b where b.id = booking_id and b.status in ('pending', 'confirmed', 'completed'))
);

-- الإشعارات: لصاحبها، وبس حقل "انقرأت" قابل للتعديل
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
create policy notifications_read on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- المواقع الحية: طرفي الرحلة
grant select on public.live_locations to authenticated;
create policy live_read on public.live_locations for select to authenticated using (
  public.is_trip_driver(trip_id) or public.has_booking_on(trip_id, true)
);

grant select on public.share_links to authenticated;
create policy share_read on public.share_links for select to authenticated using (created_by = auth.uid());

grant select on public.audit_log to authenticated;
create policy audit_read on public.audit_log for select to authenticated using (public.is_admin());

-- الرسائل والمواقع والإشعارات بالـ Realtime
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.messages, public.notifications, public.live_locations, public.bookings;
  end if;
end $$;
