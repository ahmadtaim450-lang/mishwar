-- ═══════════════════════════════════════════════════════════════════
-- مشوار: نظام الخرائط
--  · PostGIS + فهارس مكانية (GIST) على المدن ونقاط التجمع والرحلات
--  · نقاط تجمع/كراجات بتديرها الإدارة (بثلاث لغات)
--  · أماكن محفوظة لكل مستخدم (البيت، الشغل...)
--  · نقطة انطلاق ونزول دقيقة للرحلة يحددها السائق على الخريطة
--  · رحلات ضمن حدود الخريطة الظاهرة أو ضمن مسافة (مع نفس قواعد البحث)
--  · بحث جغرافي بالعربي/الإنكليزي/الألماني مرتب حسب القرب
--  · نشاط المدن (للطبقة الحرارية)
--  · سياج جغرافي: إشعار للراكب لما السائق يقرب من نقطة صعودو
--  · كاش وحدود استعمال لخدمات الخرائط الخارجية (بتستعملها دالة geo)
-- ═══════════════════════════════════════════════════════════════════

create extension if not exists postgis with schema extensions;

-- نقطة جغرافية من خط عرض/طول
create or replace function public._pt(p_lat double precision, p_lon double precision)
returns extensions.geography
language sql immutable parallel safe set search_path = public, extensions as $$
  select extensions.st_setsrid(extensions.st_makepoint(p_lon, p_lat), 4326)::extensions.geography;
$$;

-- حدود سوريا التقريبية (مع هامش صغير)
create or replace function public._in_syria(p_lat double precision, p_lon double precision) returns boolean
language sql immutable parallel safe as $$
  select p_lat between 32.2 and 37.4 and p_lon between 35.5 and 42.5;
$$;

-- توحيد الكتابة للبحث (نفس منطق التطبيق): أ/إ/آ=ا، ة=ه، ى=ي، بلا تشكيل، بلا "ال" بأول الكلمة
create or replace function public._norm(s text) returns text
language sql immutable parallel safe as $$
  select regexp_replace(
           translate(regexp_replace(lower(trim(coalesce(s, ''))), '[ًٌٍَُِّْـ]', '', 'g'), 'أإآةى', 'اااهي'),
           '(^|\s)ال', '\1', 'g');
$$;

-- ── المدن: موقع جغرافي وأسماء بلغات تانية ──────────────────────────
alter table public.cities
  add column if not exists name_en text,
  add column if not exists name_de text,
  add column if not exists loc extensions.geography(Point, 4326);
update public.cities set loc = public._pt(lat, lon);
create or replace function public._city_loc() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  new.loc := public._pt(new.lat, new.lon);
  return new;
end $$;
create trigger cities_loc before insert or update of lat, lon on public.cities for each row execute function public._city_loc();
create index if not exists cities_loc_idx on public.cities using gist (loc);

update public.cities c set name_en = v.en, name_de = v.de from (values
  ('damascus', 'Damascus', 'Damaskus'), ('aleppo', 'Aleppo', 'Aleppo'), ('latakia', 'Latakia', 'Latakia'),
  ('homs', 'Homs', 'Homs'), ('tartus', 'Tartus', 'Tartus'), ('hama', 'Hama', 'Hama'),
  ('jableh', 'Jableh', 'Dschabla'), ('daraa', 'Daraa', 'Daraa'), ('banias', 'Baniyas', 'Baniyas'),
  ('idlib', 'Idlib', 'Idlib'), ('raqqa', 'Raqqa', 'Rakka'), ('deir_ez_zor', 'Deir ez-Zor', 'Deir ez-Zor'),
  ('hasakah', 'Al-Hasakah', 'Hasaka'), ('qamishli', 'Qamishli', 'Qamischli'), ('sweida', 'As-Suwayda', 'Suwaida'),
  ('palmyra', 'Palmyra', 'Palmyra'), ('salamiyah', 'Salamiyah', 'Salamiyya'), ('safita', 'Safita', 'Safita'),
  ('qardaha', 'Qardaha', 'Qardaha'), ('manbij', 'Manbij', 'Manbidsch'), ('quneitra', 'Quneitra', 'Quneitra'),
  ('nabk', 'An-Nabk', 'an-Nabk')
) as v(id, en, de) where c.id = v.id;

-- ── نقاط التجمع والكراجات (بتضيفها الإدارة من لوحة التحكم) ─────────
create type public.place_kind as enum ('garage', 'meeting_point', 'landmark');
create table public.places (
  id uuid primary key default gen_random_uuid(),
  city_id text not null references public.cities (id),
  name_ar text not null check (char_length(name_ar) between 2 and 80),
  name_en text check (name_en is null or char_length(name_en) <= 80),
  name_de text check (name_de is null or char_length(name_de) <= 80),
  kind public.place_kind not null default 'meeting_point',
  lat double precision not null,
  lon double precision not null,
  loc extensions.geography(Point, 4326),
  active boolean not null default true,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  check (public._in_syria(lat, lon))
);
create trigger places_loc before insert or update of lat, lon on public.places for each row execute function public._city_loc();
create index places_loc_idx on public.places using gist (loc);
create index places_city_idx on public.places (city_id) where active;
alter table public.places enable row level security;
create policy places_read on public.places for select to authenticated using (active or public.is_staff());
revoke all on public.places from anon, authenticated;
grant select on public.places to authenticated;

-- ── الأماكن المحفوظة لكل مستخدم ────────────────────────────────────
create table public.saved_places (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  label text not null check (char_length(label) between 1 and 40),
  kind text not null default 'other' check (kind in ('home', 'work', 'other')),
  lat double precision not null,
  lon double precision not null,
  loc extensions.geography(Point, 4326),
  address text check (address is null or char_length(address) <= 200),
  created_at timestamptz not null default now(),
  check (lat between -90 and 90 and lon between -180 and 180),
  unique (user_id, label)
);
create trigger saved_places_loc before insert or update of lat, lon on public.saved_places for each row execute function public._city_loc();
create index saved_places_user_idx on public.saved_places (user_id);
-- بيت واحد وشغل واحد لكل مستخدم
create unique index saved_places_one_home on public.saved_places (user_id, kind) where kind in ('home', 'work');
alter table public.saved_places enable row level security;
create policy saved_places_own on public.saved_places for select to authenticated using (user_id = auth.uid());
revoke all on public.saved_places from anon, authenticated;
grant select on public.saved_places to authenticated;

-- ── نقطة الانطلاق والنزول الدقيقة للرحلة ───────────────────────────
alter table public.trips
  add column if not exists pickup_lat double precision,
  add column if not exists pickup_lon double precision,
  add column if not exists dropoff_lat double precision,
  add column if not exists dropoff_lon double precision,
  add column if not exists pickup_loc extensions.geography(Point, 4326),
  add column if not exists dropoff_loc extensions.geography(Point, 4326);
alter table public.trips
  add constraint trips_pickup_pair check ((pickup_lat is null) = (pickup_lon is null)),
  add constraint trips_dropoff_pair check ((dropoff_lat is null) = (dropoff_lon is null));
create or replace function public._trip_locs() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  new.pickup_loc := case when new.pickup_lat is null then null else public._pt(new.pickup_lat, new.pickup_lon) end;
  new.dropoff_loc := case when new.dropoff_lat is null then null else public._pt(new.dropoff_lat, new.dropoff_lon) end;
  return new;
end $$;
create trigger trips_locs before insert or update of pickup_lat, pickup_lon, dropoff_lat, dropoff_lon on public.trips
  for each row execute function public._trip_locs();
create index trips_pickup_idx on public.trips using gist (pickup_loc) where status = 'scheduled';
create index trips_upcoming_idx on public.trips (departure_at) where status = 'scheduled';
grant select (pickup_lat, pickup_lon, dropoff_lat, dropoff_lon) on public.trips to authenticated;

-- إشعار "السائق قرّب" مرة وحدة لكل حجز
alter table public.bookings add column if not exists near_notified_at timestamptz;

-- السائق بيحدد نقطة التجمع والنزول على الخريطة (لازم تكون قريبة من المدينة)
create or replace function public.set_trip_points(p_trip uuid,
  p_pickup_lat double precision default null, p_pickup_lon double precision default null,
  p_dropoff_lat double precision default null, p_dropoff_lon double precision default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  t public.trips;
begin
  select * into t from public.trips where id = p_trip for update;
  if not found then perform public._fail('TRIP_NOT_FOUND'); end if;
  if t.driver_id <> public._uid() then perform public._fail('FORBIDDEN'); end if;
  if t.status <> 'scheduled' then perform public._fail('INVALID_STATE'); end if;
  if (p_pickup_lat is null) <> (p_pickup_lon is null) or (p_dropoff_lat is null) <> (p_dropoff_lon is null) then
    perform public._fail('INVALID_INPUT');
  end if;
  if p_pickup_lat is not null and not exists (select 1 from public.cities c where c.id = t.from_city
      and extensions.st_dwithin(c.loc, public._pt(p_pickup_lat, p_pickup_lon), 25000)) then
    perform public._fail('POINT_TOO_FAR');
  end if;
  if p_dropoff_lat is not null and not exists (select 1 from public.cities c where c.id = t.to_city
      and extensions.st_dwithin(c.loc, public._pt(p_dropoff_lat, p_dropoff_lon), 25000)) then
    perform public._fail('POINT_TOO_FAR');
  end if;
  update public.trips set pickup_lat = p_pickup_lat, pickup_lon = p_pickup_lon,
    dropoff_lat = p_dropoff_lat, dropoff_lon = p_dropoff_lon, updated_at = now() where id = t.id;
end $$;

-- نقطة التجمع والنزول لرحلة (لأي حدا بيشوف الرحلة بالبحث، أو أطراف الحجز)
create or replace function public.trip_points(p_trip uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  t public.trips;
begin
  select * into t from public.trips where id = p_trip;
  if not found then perform public._fail('TRIP_NOT_FOUND'); end if;
  if not (t.driver_id = auth.uid() or public.has_booking_on(t.id) or public.is_staff()
          or (t.status = 'scheduled' and exists (select 1 from public.profiles p where p.id = t.driver_id and p.driver_status = 'approved'))) then
    perform public._fail('FORBIDDEN');
  end if;
  return jsonb_build_object(
    'pickup', case when t.pickup_lat is null then null else jsonb_build_object('lat', t.pickup_lat, 'lon', t.pickup_lon) end,
    'dropoff', case when t.dropoff_lat is null then null else jsonb_build_object('lat', t.dropoff_lat, 'lon', t.dropoff_lon) end);
end $$;

-- ── الرحلات على الخريطة ────────────────────────────────────────────
-- كل نقطة صعود (الانطلاق أو وقفة) بتطلع كصف لحالها، مع سعر ووقت الجزء لآخر الطريق.
-- نفس قواعد البحث: سائق موثّق، مقاعد، رحلة جاية، وفلترة الجنس.
create or replace function public._map_trips(
  p_min_lat double precision, p_min_lon double precision, p_max_lat double precision, p_max_lon double precision,
  p_lat double precision, p_lon double precision, p_radius_km double precision,
  p_date date, p_to text, p_kinds public.ride_kind[], p_seats int, p_max_price int, p_limit int)
returns table (
  trip_id uuid, board_city text, board_name text, to_city text, to_name text, lat double precision, lon double precision,
  exact boolean, departure_at timestamptz, arrival_at timestamptz, price_syp int, seats_available smallint,
  kind public.ride_kind, instant boolean, driver_name text, driver_rating numeric, distance_km double precision)
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_gender public.gender := (select gender from public.profiles where profiles.id = auth.uid());
  v_env extensions.geometry;
  v_me extensions.geography;
begin
  if p_seats is null or p_seats < 1 or p_seats > 7 then perform public._fail('INVALID_INPUT'); end if;
  if p_min_lat is not null then
    if p_max_lat is null or p_min_lon is null or p_max_lon is null or p_min_lat > p_max_lat or p_min_lon > p_max_lon
       or p_min_lat < -90 or p_max_lat > 90 or p_min_lon < -180 or p_max_lon > 180 then
      perform public._fail('INVALID_INPUT');
    end if;
    v_env := extensions.st_makeenvelope(p_min_lon, p_min_lat, p_max_lon, p_max_lat, 4326);
  end if;
  if (p_lat is null) <> (p_lon is null) or (p_lat is not null and (p_lat not between -90 and 90 or p_lon not between -180 and 180)) then
    perform public._fail('INVALID_INPUT');
  end if;
  if p_radius_km is not null and (p_lat is null or p_radius_km <= 0 or p_radius_km > 500) then perform public._fail('INVALID_INPUT'); end if;
  if p_lat is not null then v_me := public._pt(p_lat, p_lon); end if;

  return query
  with b as (
    select t.id, r.city as board, t.to_city as dest, r.pos,
           case when r.city = t.from_city and t.pickup_loc is not null then t.pickup_loc else c.loc end as pt,
           (r.city = t.from_city and t.pickup_loc is not null) as is_exact,
           t.seats_available, t.kind, t.instant, p.full_name, p.rating_avg, c.name_ar as bname
    from public.trips t
    join public.profiles p on p.id = t.driver_id
    cross join lateral unnest(public._route(t.id)) with ordinality as r(city, pos)
    join public.cities c on c.id = r.city
    where t.status = 'scheduled'
      and r.city <> t.to_city
      and t.departure_at < now() + interval '15 days'
      and t.seats_available >= p_seats
      and p.driver_status = 'approved'
      and (p_kinds is null or t.kind = any (p_kinds))
      and (p_to is null or t.to_city = p_to or exists (select 1 from public.trip_stops s where s.trip_id = t.id and s.city_id = p_to))
      and (v_gender is null
           or (v_gender = 'male' and t.kind in ('men', 'family'))
           or (v_gender = 'female' and t.kind in ('women', 'family')))
  )
  select b.id, b.board, b.bname, coalesce(p_to, b.dest), (select c2.name_ar from public.cities c2 where c2.id = coalesce(p_to, b.dest)),
         extensions.st_y(b.pt::extensions.geometry), extensions.st_x(b.pt::extensions.geometry), b.is_exact,
         sg.dep, sg.arr, sg.price, b.seats_available, b.kind, b.instant, b.full_name, b.rating_avg,
         case when v_me is null then null else round((extensions.st_distance(b.pt, v_me) / 1000)::numeric, 1)::double precision end
  from b
  cross join lateral public._segment(b.id, b.board, coalesce(p_to, b.dest)) sg
  where sg.ok and sg.dep > now()
    and (p_date is null or (sg.dep at time zone 'Asia/Damascus')::date = p_date)
    and (p_max_price is null or sg.price <= p_max_price)
    and (v_env is null or b.pt::extensions.geometry && v_env)
    and (p_radius_km is null or extensions.st_dwithin(b.pt, v_me, p_radius_km * 1000))
  order by case when v_me is null then 0 else extensions.st_distance(b.pt, v_me) end, sg.dep
  limit least(greatest(coalesce(p_limit, 300), 1), 500);
end $$;

-- الرحلات ضمن حدود الخريطة الظاهرة
create or replace function public.map_trips(
  p_min_lat double precision, p_min_lon double precision, p_max_lat double precision, p_max_lon double precision,
  p_date date default null, p_to text default null, p_kinds public.ride_kind[] default null,
  p_seats int default 1, p_max_price int default null, p_lat double precision default null, p_lon double precision default null)
returns table (
  trip_id uuid, board_city text, board_name text, to_city text, to_name text, lat double precision, lon double precision,
  exact boolean, departure_at timestamptz, arrival_at timestamptz, price_syp int, seats_available smallint,
  kind public.ride_kind, instant boolean, driver_name text, driver_rating numeric, distance_km double precision)
language sql stable security definer set search_path = public, extensions as $$
  select * from public._map_trips(p_min_lat, p_min_lon, p_max_lat, p_max_lon, p_lat, p_lon, null,
    p_date, p_to, p_kinds, p_seats, p_max_price, 300);
$$;

-- الرحلات القريبة من نقطة (مرتبة حسب المسافة)
create or replace function public.trips_near(p_lat double precision, p_lon double precision, p_radius_km double precision default 30,
  p_date date default null, p_to text default null, p_kinds public.ride_kind[] default null, p_seats int default 1)
returns table (
  trip_id uuid, board_city text, board_name text, to_city text, to_name text, lat double precision, lon double precision,
  exact boolean, departure_at timestamptz, arrival_at timestamptz, price_syp int, seats_available smallint,
  kind public.ride_kind, instant boolean, driver_name text, driver_rating numeric, distance_km double precision)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if p_lat is null or p_lon is null or p_radius_km is null then perform public._fail('INVALID_INPUT'); end if;
  return query select * from public._map_trips(null, null, null, null, p_lat, p_lon, p_radius_km,
    p_date, p_to, p_kinds, p_seats, null, 100);
end $$;

-- ── البحث الجغرافي المحلي (مدن + نقاط تجمع + أماكني) ───────────────
create or replace function public.search_places(p_q text, p_lat double precision default null, p_lon double precision default null,
  p_limit int default 10)
returns table (kind text, id text, name text, city_id text, city_name text, lat double precision, lon double precision, distance_km double precision)
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  q text := public._norm(p_q);
  v_me extensions.geography;
begin
  if p_q is null or char_length(p_q) > 80 then perform public._fail('INVALID_INPUT'); end if;
  if (p_lat is null) <> (p_lon is null) then perform public._fail('INVALID_INPUT'); end if;
  if p_lat is not null then v_me := public._pt(p_lat, p_lon); end if;
  return query
  with cand as (
    select 'city'::text as k, c.id::text as cid, c.name_ar as nm, c.id as city, c.name_ar as cname, c.loc,
           case when public._norm(c.name_ar) = q or lower(c.name_en) = q or lower(c.name_de) = q then 0
                when public._norm(c.name_ar) like q || '%' or lower(c.name_en) like q || '%' or lower(c.name_de) like q || '%' then 1
                when public._norm(c.name_ar) like '%' || q || '%' or lower(c.name_en) like '%' || q || '%' then 2
                else 9 end as score
    from public.cities c where c.active
    union all
    select pl.kind::text, pl.id::text, pl.name_ar, pl.city_id, c.name_ar, pl.loc,
           case when public._norm(pl.name_ar) = q or lower(pl.name_en) = q or lower(pl.name_de) = q then 1
                when public._norm(pl.name_ar) like q || '%' or lower(pl.name_en) like q || '%' or lower(pl.name_de) like q || '%' then 2
                when public._norm(pl.name_ar) like '%' || q || '%' or lower(pl.name_en) like '%' || q || '%'
                     or lower(pl.name_de) like '%' || q || '%' or public._norm(c.name_ar) = q then 3
                else 9 end
    from public.places pl join public.cities c on c.id = pl.city_id where pl.active
    union all
    select 'saved', s.id::text, s.label, null, s.address, s.loc,
           case when public._norm(s.label) like q || '%' then 0 when public._norm(s.label) like '%' || q || '%' then 2 else 9 end
    from public.saved_places s where s.user_id = auth.uid()
  )
  select cand.k, cand.cid, cand.nm, cand.city, cand.cname,
         extensions.st_y(cand.loc::extensions.geometry), extensions.st_x(cand.loc::extensions.geometry),
         case when v_me is null then null else round((extensions.st_distance(cand.loc, v_me) / 1000)::numeric, 1)::double precision end
  from cand
  where q = '' or cand.score < 9
  order by case when q = '' then 0 else cand.score end,
           case when v_me is null then 0 else extensions.st_distance(cand.loc, v_me) end, cand.nm
  limit least(greatest(coalesce(p_limit, 10), 1), 30);
end $$;

-- أقرب مدينة لنقطة (للموقع الحالي أو نقطة على الخريطة)
create or replace function public.nearest_city(p_lat double precision, p_lon double precision)
returns table (id text, name text, distance_km double precision)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 then perform public._fail('INVALID_INPUT'); end if;
  return query
  select c.id, c.name_ar, round((extensions.st_distance(c.loc, public._pt(p_lat, p_lon)) / 1000)::numeric, 1)::double precision
  from public.cities c where c.active
  order by c.loc operator(extensions.<->) public._pt(p_lat, p_lon)
  limit 1;
end $$;

-- نقاط التجمع بمدينة
create or replace function public.city_places(p_city text)
returns table (id uuid, name text, kind public.place_kind, lat double precision, lon double precision)
language sql stable security definer set search_path = public, extensions as $$
  select pl.id, pl.name_ar, pl.kind, pl.lat, pl.lon from public.places pl
  where pl.city_id = p_city and pl.active order by pl.kind, pl.name_ar limit 50;
$$;

-- نشاط المدن بالأيام الجاية (عدد نقاط الصعود) للطبقة الحرارية
create or replace function public.city_activity(p_days int default 7)
returns table (city_id text, name text, lat double precision, lon double precision, departures bigint)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if p_days is null or p_days < 1 or p_days > 30 then perform public._fail('INVALID_INPUT'); end if;
  return query
  select c.id, c.name_ar, c.lat, c.lon, count(*)
  from public.trips t
  join public.profiles p on p.id = t.driver_id
  cross join lateral unnest(public._route(t.id)) as r(city)
  join public.cities c on c.id = r.city
  where t.status = 'scheduled' and r.city <> t.to_city and t.seats_available > 0 and p.driver_status = 'approved'
    and t.departure_at > now() and t.departure_at < now() + make_interval(days => p_days)
  group by c.id, c.name_ar, c.lat, c.lon
  order by count(*) desc;
end $$;

-- ── الأماكن المحفوظة ───────────────────────────────────────────────
create or replace function public.save_place(p_label text, p_lat double precision, p_lon double precision,
  p_kind text default 'other', p_address text default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  u uuid := public._uid();
  v_label text := public._clean(p_label, 40);
  v_id uuid;
begin
  if v_label is null or char_length(v_label) not between 1 and 40 then perform public._fail('INVALID_INPUT'); end if;
  if p_kind not in ('home', 'work', 'other') then perform public._fail('INVALID_INPUT'); end if;
  if p_lat is null or p_lon is null or not public._in_syria(p_lat, p_lon) then perform public._fail('OUTSIDE_SYRIA'); end if;
  if p_kind in ('home', 'work') then
    delete from public.saved_places where user_id = u and kind = p_kind;
  end if;
  insert into public.saved_places (user_id, label, kind, lat, lon, address)
  values (u, v_label, p_kind, p_lat, p_lon, public._clean(p_address, 200))
  on conflict (user_id, label) do update set lat = excluded.lat, lon = excluded.lon, kind = excluded.kind, address = excluded.address
  returning id into v_id;
  if (select count(*) from public.saved_places where user_id = u) > 20 then perform public._fail('LIMIT_REACHED'); end if;
  return v_id;
end $$;

create or replace function public.delete_place(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.saved_places where id = p_id and user_id = public._uid();
  if not found then perform public._fail('NOT_FOUND'); end if;
end $$;

create or replace function public.my_places()
returns table (id uuid, label text, kind text, lat double precision, lon double precision, address text)
language sql stable security definer set search_path = public as $$
  select s.id, s.label, s.kind, s.lat, s.lon, s.address from public.saved_places s
  where s.user_id = auth.uid() order by case s.kind when 'home' then 0 when 'work' then 1 else 2 end, s.created_at;
$$;

-- ── إدارة نقاط التجمع ──────────────────────────────────────────────
create or replace function public.admin_upsert_place(p_id uuid, p_city text, p_name_ar text, p_kind public.place_kind,
  p_lat double precision, p_lon double precision, p_name_en text default null, p_name_de text default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid;
begin
  if not public.is_admin() then perform public._fail('FORBIDDEN'); end if;
  if p_lat is null or p_lon is null or not public._in_syria(p_lat, p_lon) then perform public._fail('OUTSIDE_SYRIA'); end if;
  if not exists (select 1 from public.cities c where c.id = p_city and extensions.st_dwithin(c.loc, public._pt(p_lat, p_lon), 40000)) then
    perform public._fail('POINT_TOO_FAR');
  end if;
  if p_id is null then
    insert into public.places (city_id, name_ar, name_en, name_de, kind, lat, lon, created_by)
    values (p_city, public._clean(p_name_ar, 80), nullif(public._clean(p_name_en, 80), ''), nullif(public._clean(p_name_de, 80), ''), p_kind, p_lat, p_lon, auth.uid())
    returning id into v_id;
  else
    update public.places set city_id = p_city, name_ar = public._clean(p_name_ar, 80), name_en = nullif(public._clean(p_name_en, 80), ''),
      name_de = nullif(public._clean(p_name_de, 80), ''), kind = p_kind, lat = p_lat, lon = p_lon
    where id = p_id returning id into v_id;
    if v_id is null then perform public._fail('NOT_FOUND'); end if;
  end if;
  perform public._audit('place.upsert', 'place', v_id::text, jsonb_build_object('city', p_city));
  return v_id;
end $$;

create or replace function public.admin_set_place_active(p_id uuid, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then perform public._fail('FORBIDDEN'); end if;
  update public.places set active = coalesce(p_active, false) where id = p_id;
  if not found then perform public._fail('NOT_FOUND'); end if;
  perform public._audit('place.active', 'place', p_id::text, jsonb_build_object('active', p_active));
end $$;

-- ── التتبع الحي + سياج جغرافي (السائق قرّب من نقطة الصعود) ─────────
create or replace function public.update_live_location(p_trip uuid, p_lat double precision, p_lon double precision,
  p_accuracy real default null, p_heading real default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  u uuid := public._uid();
  t public.trips;
  r record;
begin
  select * into t from public.trips where id = p_trip;
  if not found then perform public._fail('TRIP_NOT_FOUND'); end if;
  if t.driver_id <> u and not exists (select 1 from public.bookings where trip_id = t.id and rider_id = u and status = 'confirmed') then
    perform public._fail('FORBIDDEN');
  end if;
  if t.status not in ('scheduled', 'in_progress') or now() < t.departure_at - interval '2 hours' or now() > t.arrival_at + interval '6 hours' then
    perform public._fail('TRACKING_CLOSED');
  end if;
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 then perform public._fail('INVALID_INPUT'); end if;
  if p_accuracy is not null and (p_accuracy < 0 or p_accuracy > 100000) then perform public._fail('INVALID_INPUT'); end if;
  insert into public.live_locations (trip_id, user_id, lat, lon, accuracy, heading, updated_at)
  values (t.id, u, p_lat, p_lon, p_accuracy, p_heading, now())
  on conflict (trip_id, user_id) do update set lat = excluded.lat, lon = excluded.lon, accuracy = excluded.accuracy, heading = excluded.heading, updated_at = now();

  -- السائق ضمن 3 كم من نقطة صعود راكب مؤكد (وقراءة الموقع مقبولة الدقة) → إشعار مرة وحدة
  if u = t.driver_id and coalesce(p_accuracy, 0) <= 500 then
    for r in
      select b.id, b.rider_id, c.name_ar
      from public.bookings b
      join public.cities c on c.id = coalesce(b.from_city, t.from_city)
      where b.trip_id = t.id and b.status = 'confirmed' and b.near_notified_at is null
        and extensions.st_dwithin(
              case when coalesce(b.from_city, t.from_city) = t.from_city and t.pickup_loc is not null then t.pickup_loc else c.loc end,
              public._pt(p_lat, p_lon), 3000)
      for update of b
    loop
      update public.bookings set near_notified_at = now() where id = r.id;
      perform public._notify(r.rider_id, 'driver_near', 'السائق صار قريب', 'السائق على بعد أقل من 3 كم من ' || r.name_ar || '، خلّيك جاهز',
        jsonb_build_object('booking_id', r.id, 'trip_id', t.id));
    end loop;
  end if;
end $$;

-- ── كاش وحدود استعمال خدمات الخرائط الخارجية (للدالة geo فقط) ──────
create table public.geo_cache (
  key text primary key check (char_length(key) <= 300),
  body jsonb not null,
  created_at timestamptz not null default now()
);
create index geo_cache_age_idx on public.geo_cache (created_at);
create table public.geo_usage (
  user_id uuid not null,
  bucket timestamptz not null,
  hits int not null default 0,
  primary key (user_id, bucket)
);
alter table public.geo_cache enable row level security;
alter table public.geo_usage enable row level security;
revoke all on public.geo_cache, public.geo_usage from anon, authenticated;

-- بيحسب طلب ويرجّع إذا لسا ضمن الحد بالساعة
create or replace function public.geo_take(p_user uuid, p_limit int default 120) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v int;
begin
  insert into public.geo_usage (user_id, bucket, hits) values (p_user, date_trunc('hour', now()), 1)
  on conflict (user_id, bucket) do update set hits = public.geo_usage.hits + 1
  returning hits into v;
  return v <= p_limit;
end $$;

create or replace function public.geo_maintenance() returns jsonb
language plpgsql security definer set search_path = public as $$
declare a int; b int;
begin
  delete from public.geo_cache where created_at < now() - interval '30 days'; get diagnostics a = row_count;
  delete from public.geo_usage where bucket < now() - interval '2 days'; get diagnostics b = row_count;
  return jsonb_build_object('cache', a, 'usage', b);
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mishwar-geo-maintenance', '17 3 * * *', 'select public.geo_maintenance()');
  end if;
exception when others then
  raise notice 'pg_cron غير متاح: select public.geo_maintenance()';
end $$;

-- ── الصلاحيات ─────────────────────────────────────────────────────
revoke execute on function public._map_trips(double precision, double precision, double precision, double precision, double precision,
  double precision, double precision, date, text, public.ride_kind[], int, int, int),
  public.geo_take(uuid, int), public.geo_maintenance(), public._city_loc(), public._trip_locs()
  from public, anon, authenticated;
grant execute on function public.geo_take(uuid, int), public.geo_maintenance() to service_role;
revoke execute on function
  public.set_trip_points(uuid, double precision, double precision, double precision, double precision),
  public.map_trips(double precision, double precision, double precision, double precision, date, text, public.ride_kind[], int, int, double precision, double precision),
  public.trips_near(double precision, double precision, double precision, date, text, public.ride_kind[], int),
  public.search_places(text, double precision, double precision, int),
  public.nearest_city(double precision, double precision),
  public.city_places(text), public.city_activity(int), public.trip_points(uuid),
  public.save_place(text, double precision, double precision, text, text), public.delete_place(uuid), public.my_places(),
  public.admin_upsert_place(uuid, text, text, public.place_kind, double precision, double precision, text, text),
  public.admin_set_place_active(uuid, boolean)
  from public, anon;
grant execute on function
  public.set_trip_points(uuid, double precision, double precision, double precision, double precision),
  public.map_trips(double precision, double precision, double precision, double precision, date, text, public.ride_kind[], int, int, double precision, double precision),
  public.trips_near(double precision, double precision, double precision, date, text, public.ride_kind[], int),
  public.search_places(text, double precision, double precision, int),
  public.nearest_city(double precision, double precision),
  public.city_places(text), public.city_activity(int), public.trip_points(uuid),
  public.save_place(text, double precision, double precision, text, text), public.delete_place(uuid), public.my_places(),
  public.admin_upsert_place(uuid, text, text, public.place_kind, double precision, double precision, text, text),
  public.admin_set_place_active(uuid, boolean)
  to authenticated;
