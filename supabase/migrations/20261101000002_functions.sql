-- ═══════════════════════════════════════════════════════════════════
-- مشوار: منطق الأعمال (RPC). كل دالة بتتحقق من الهوية والصلاحية والمدخلات.
-- الأخطاء بترجع كرمز ثابت (مثلاً NOT_ENOUGH_SEATS) والتطبيق بيترجمو للعربي.
-- ═══════════════════════════════════════════════════════════════════

-- ── أدوات داخلية ───────────────────────────────────────────────────
create or replace function public._fail(p_code text) returns void
language plpgsql as $$
begin
  raise exception '%', p_code using errcode = 'P0001';
end $$;

create or replace function public._uid() returns uuid
language plpgsql stable as $$
declare u uuid := auth.uid();
begin
  if u is null then perform public._fail('NOT_AUTHENTICATED'); end if;
  return u;
end $$;

create or replace function public._audit(p_action text, p_entity text, p_entity_id text, p_meta jsonb default '{}'::jsonb) returns void
language sql security definer set search_path = public as $$
  insert into public.audit_log (actor_id, action, entity, entity_id, meta) values (auth.uid(), p_action, p_entity, p_entity_id, coalesce(p_meta, '{}'::jsonb));
$$;

create or replace function public._notify(p_user uuid, p_kind text, p_title text, p_body text, p_data jsonb default '{}'::jsonb) returns void
language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, kind, title, body, data) values (p_user, p_kind, p_title, coalesce(p_body, ''), coalesce(p_data, '{}'::jsonb));
$$;

create or replace function public._city_name(p_id text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select name_ar from public.cities where id = p_id), p_id);
$$;

create or replace function public._clean(p_text text, p_max int) returns text
language sql immutable as $$
  select nullif(left(btrim(regexp_replace(coalesce(p_text, ''), '[[:cntrl:]]', ' ', 'g')), p_max), '');
$$;

-- ── الملف الشخصي ───────────────────────────────────────────────────
create or replace function public.complete_profile(p_full_name text, p_gender public.gender, p_music text default null)
returns public.profiles
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  v_name text := public._clean(p_full_name, 80);
  r public.profiles;
begin
  if v_name is null or char_length(v_name) < 3 then perform public._fail('INVALID_NAME'); end if;
  if p_gender is null then perform public._fail('INVALID_INPUT'); end if;
  if p_music is not null and p_music not in ('music', 'no_music', 'ask') then perform public._fail('INVALID_INPUT'); end if;
  select * into r from public.profiles where id = u for update;
  if not found then perform public._fail('PROFILE_NOT_FOUND'); end if;
  if r.gender is not null and r.gender <> p_gender then perform public._fail('GENDER_LOCKED'); end if;
  update public.profiles set full_name = v_name, gender = p_gender, music_pref = coalesce(p_music, music_pref)
  where id = u returning * into r;
  return r;
end $$;

create or replace function public.my_profile() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'full_name', p.full_name, 'gender', p.gender, 'avatar_path', p.avatar_path, 'role', p.role,
    'driver_status', p.driver_status, 'rating_avg', p.rating_avg, 'rating_count', p.rating_count,
    'trips_count', p.trips_count, 'music_pref', p.music_pref, 'phone', pp.phone, 'created_at', p.created_at,
    'vehicle', (select to_jsonb(v) from public.vehicles v where v.owner_id = p.id and v.verified order by v.created_at desc limit 1)
  )
  from public.profiles p left join public.profile_private pp on pp.id = p.id
  where p.id = auth.uid();
$$;

-- ── البحث ──────────────────────────────────────────────────────────
-- الرجال بيشوفوا رحلات الرجال والعائلات، والنساء بيشوفوا النسائية والعائلية.
create or replace function public.search_trips(p_from text, p_to text, p_date date, p_seats int default 1)
returns table (
  id uuid, from_city text, to_city text, from_spot text, to_spot text,
  departure_at timestamptz, arrival_at timestamptz, price_syp int, seats_total smallint, seats_available smallint,
  kind public.ride_kind, instant boolean, prefs text[], note text, stops text[],
  driver_id uuid, driver_name text, driver_avatar text, driver_rating numeric, driver_reviews int, driver_trips int,
  car text
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_gender public.gender := (select gender from public.profiles where profiles.id = auth.uid());
begin
  if p_from is null or p_to is null or p_from = p_to or p_date is null then perform public._fail('INVALID_INPUT'); end if;
  if p_seats is null or p_seats < 1 or p_seats > 7 then perform public._fail('INVALID_INPUT'); end if;
  return query
  select t.id, t.from_city, t.to_city, t.from_spot, t.to_spot, t.departure_at, t.arrival_at, t.price_syp,
         t.seats_total, t.seats_available, t.kind, t.instant, t.prefs, t.note,
         coalesce((select array_agg(s.city_id order by s.position) from public.trip_stops s where s.trip_id = t.id), '{}'),
         p.id, p.full_name, p.avatar_path, p.rating_avg, p.rating_count, p.trips_count,
         v.make_model || ' · ' || v.color
  from public.trips t
  join public.profiles p on p.id = t.driver_id
  join public.vehicles v on v.id = t.vehicle_id
  where t.status = 'scheduled'
    and t.from_city = p_from and t.to_city = p_to
    and (t.departure_at at time zone 'Asia/Damascus')::date = p_date
    and t.departure_at > now()
    and t.seats_available >= p_seats
    and p.driver_status = 'approved'
    and (v_gender is null
         or (v_gender = 'male' and t.kind in ('men', 'family'))
         or (v_gender = 'female' and t.kind in ('women', 'family')))
  order by t.departure_at
  limit 100;
end $$;

-- عدد الرحلات وأقل سعر لكل وجهة من مدينة، ليوم معيّن (لخريطة الوجهات)
create or replace function public.destination_stats(p_from text, p_date date)
returns table (to_city text, trips bigint, min_price int)
language sql stable security definer set search_path = public as $$
  select t.to_city, count(*), min(t.price_syp)
  from public.trips t join public.profiles p on p.id = t.driver_id
  where t.status = 'scheduled' and t.from_city = p_from and t.seats_available > 0
    and (t.departure_at at time zone 'Asia/Damascus')::date = p_date and t.departure_at > now()
    and p.driver_status = 'approved'
  group by t.to_city;
$$;

-- ── نشر رحلة (للسائق الموثّق بس) ───────────────────────────────────
create or replace function public.publish_trip(
  p_vehicle uuid, p_from text, p_to text, p_from_spot text, p_to_spot text,
  p_departure timestamptz, p_duration_min int, p_price int, p_seats int,
  p_kind public.ride_kind, p_instant boolean default false, p_prefs text[] default '{}',
  p_note text default null, p_stops text[] default '{}'
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  me public.profiles;
  v public.vehicles;
  v_id uuid;
  i int;
begin
  select * into me from public.profiles where id = u;
  if me.driver_status <> 'approved' or me.suspended_at is not null then perform public._fail('NOT_APPROVED_DRIVER'); end if;
  select * into v from public.vehicles where id = p_vehicle and owner_id = u;
  if not found or not v.verified then perform public._fail('VEHICLE_NOT_VERIFIED'); end if;
  if p_from = p_to or not exists (select 1 from public.cities where id = p_from and active) or not exists (select 1 from public.cities where id = p_to and active) then
    perform public._fail('INVALID_ROUTE');
  end if;
  if p_departure < now() + interval '30 minutes' or p_departure > now() + interval '60 days' then perform public._fail('INVALID_DEPARTURE'); end if;
  if p_duration_min is null or p_duration_min < 10 or p_duration_min > 1440 then perform public._fail('INVALID_INPUT'); end if;
  if p_price is null or p_price < 1000 or p_price > 2000000 then perform public._fail('INVALID_PRICE'); end if;
  if p_seats is null or p_seats < 1 or p_seats > v.seats then perform public._fail('INVALID_SEATS'); end if;
  if (p_kind = 'women' and me.gender <> 'female') or (p_kind = 'men' and me.gender <> 'male') then perform public._fail('GENDER_RESTRICTED'); end if;
  if coalesce(cardinality(p_stops), 0) > 6 then perform public._fail('INVALID_ROUTE'); end if;
  if exists (select 1 from unnest(coalesce(p_stops, '{}')) s where s in (p_from, p_to) or not exists (select 1 from public.cities c where c.id = s))
     or (select count(distinct s) from unnest(coalesce(p_stops, '{}')) s) <> coalesce(cardinality(p_stops), 0) then
    perform public._fail('INVALID_ROUTE');
  end if;
  if (select count(*) from public.trips where driver_id = u and created_at > now() - interval '24 hours') >= 6 then perform public._fail('RATE_LIMITED'); end if;
  if exists (select 1 from public.trips where driver_id = u and status in ('scheduled', 'in_progress')
             and tstzrange(departure_at, arrival_at) && tstzrange(p_departure, p_departure + make_interval(mins => p_duration_min))) then
    perform public._fail('TRIP_OVERLAP');
  end if;

  insert into public.trips (driver_id, vehicle_id, from_city, to_city, from_spot, to_spot, departure_at, arrival_at,
                            price_syp, seats_total, seats_available, kind, instant, prefs, note)
  values (u, v.id, p_from, p_to, coalesce(public._clean(p_from_spot, 100), public._city_name(p_from)), coalesce(public._clean(p_to_spot, 100), public._city_name(p_to)),
          p_departure, p_departure + make_interval(mins => p_duration_min), p_price, p_seats, p_seats, p_kind, coalesce(p_instant, false),
          coalesce((select array_agg(public._clean(x, 40)) from unnest(p_prefs) x where public._clean(x, 40) is not null), '{}'), public._clean(p_note, 500))
  returning id into v_id;

  if coalesce(cardinality(p_stops), 0) > 0 then
    for i in 1 .. cardinality(p_stops) loop
      insert into public.trip_stops (trip_id, position, city_id) values (v_id, i, p_stops[i]);
    end loop;
  end if;

  perform public._audit('trip.publish', 'trip', v_id::text, jsonb_build_object('from', p_from, 'to', p_to, 'seats', p_seats));
  return v_id;
end $$;

-- ── الحجز ──────────────────────────────────────────────────────────
create or replace function public.request_booking(p_trip uuid, p_seats int, p_family boolean default false, p_message text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  me public.profiles;
  t public.trips;
  v_status public.booking_status;
  b public.bookings;
begin
  select * into me from public.profiles where id = u;
  if me.gender is null or char_length(me.full_name) < 3 then perform public._fail('PROFILE_INCOMPLETE'); end if;
  if me.suspended_at is not null then perform public._fail('ACCOUNT_SUSPENDED'); end if;
  if p_seats is null or p_seats < 1 or p_seats > 7 then perform public._fail('INVALID_SEATS'); end if;

  -- قفل صف الرحلة لحتى ما ينحجز نفس المقعد مرتين
  select * into t from public.trips where id = p_trip for update;
  if not found then perform public._fail('TRIP_NOT_FOUND'); end if;
  if t.status <> 'scheduled' or t.departure_at <= now() then perform public._fail('TRIP_NOT_BOOKABLE'); end if;
  if t.driver_id = u then perform public._fail('OWN_TRIP'); end if;
  if (t.kind = 'women' and me.gender <> 'female') or (t.kind = 'men' and me.gender <> 'male') then perform public._fail('GENDER_RESTRICTED'); end if;
  if t.kind = 'family' and not coalesce(p_family, false) then perform public._fail('FAMILY_ONLY'); end if;
  if p_seats > t.seats_available then perform public._fail('NOT_ENOUGH_SEATS'); end if;
  if exists (select 1 from public.bookings where trip_id = t.id and rider_id = u and status in ('pending', 'confirmed')) then perform public._fail('ALREADY_BOOKED'); end if;
  if (select count(*) from public.bookings where rider_id = u and created_at > now() - interval '1 hour') >= 10 then perform public._fail('RATE_LIMITED'); end if;

  v_status := case when t.instant then 'confirmed' else 'pending' end;
  insert into public.bookings (trip_id, rider_id, seats, family, status, pin, message, decided_at)
  values (t.id, u, p_seats, coalesce(p_family, false), v_status, lpad((floor(random() * 10000))::int::text, 4, '0'),
          public._clean(p_message, 500), case when t.instant then now() end)
  returning * into b;

  if t.instant then
    update public.trips set seats_available = seats_available - p_seats where id = t.id;
    perform public._notify(t.driver_id, 'booking.confirmed', 'حجز جديد', me.full_name || ' حجز ' || p_seats || ' مقعد', jsonb_build_object('booking_id', b.id, 'trip_id', t.id));
  else
    perform public._notify(t.driver_id, 'booking.requested', 'طلب حجز جديد', me.full_name || ' بدو ' || p_seats || ' مقعد', jsonb_build_object('booking_id', b.id, 'trip_id', t.id));
  end if;
  perform public._audit('booking.request', 'booking', b.id::text, jsonb_build_object('trip', t.id, 'seats', p_seats, 'status', v_status));
  return jsonb_build_object('id', b.id, 'status', b.status, 'pin', b.pin);
end $$;

create or replace function public.respond_booking(p_booking uuid, p_accept boolean)
returns public.booking_status
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  b public.bookings;
  t public.trips;
begin
  select * into b from public.bookings where id = p_booking for update;
  if not found then perform public._fail('BOOKING_NOT_FOUND'); end if;
  select * into t from public.trips where id = b.trip_id for update;
  if t.driver_id <> u then perform public._fail('FORBIDDEN'); end if;
  if b.status <> 'pending' then perform public._fail('INVALID_STATE'); end if;

  if p_accept then
    if t.status <> 'scheduled' then perform public._fail('TRIP_NOT_BOOKABLE'); end if;
    if b.seats > t.seats_available then perform public._fail('NOT_ENOUGH_SEATS'); end if;
    update public.trips set seats_available = seats_available - b.seats where id = t.id;
    update public.bookings set status = 'confirmed', decided_at = now() where id = b.id;
    perform public._notify(b.rider_id, 'booking.confirmed', 'انقبل حجزك', 'رحلة ' || public._city_name(t.from_city) || ' ← ' || public._city_name(t.to_city), jsonb_build_object('booking_id', b.id));
  else
    update public.bookings set status = 'rejected', decided_at = now() where id = b.id;
    perform public._notify(b.rider_id, 'booking.rejected', 'ما انقبل حجزك', 'فيك تدوّر على رحلة تانية بنفس الطريق', jsonb_build_object('booking_id', b.id));
  end if;
  perform public._audit(case when p_accept then 'booking.accept' else 'booking.reject' end, 'booking', b.id::text);
  return case when p_accept then 'confirmed'::public.booking_status else 'rejected'::public.booking_status end;
end $$;

create or replace function public.cancel_booking(p_booking uuid, p_reason text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  b public.bookings;
  t public.trips;
begin
  select * into b from public.bookings where id = p_booking for update;
  if not found then perform public._fail('BOOKING_NOT_FOUND'); end if;
  select * into t from public.trips where id = b.trip_id for update;
  if b.rider_id <> u and t.driver_id <> u then perform public._fail('FORBIDDEN'); end if;
  if b.status not in ('pending', 'confirmed') then perform public._fail('INVALID_STATE'); end if;
  if t.status <> 'scheduled' then perform public._fail('TRIP_NOT_BOOKABLE'); end if;

  if b.status = 'confirmed' then
    update public.trips set seats_available = least(seats_total, seats_available + b.seats) where id = t.id;
  end if;
  update public.bookings set status = 'cancelled', cancelled_at = now(), cancel_reason = public._clean(p_reason, 200) where id = b.id;
  perform public._notify(case when u = b.rider_id then t.driver_id else b.rider_id end, 'booking.cancelled', 'انلغى حجز',
    'رحلة ' || public._city_name(t.from_city) || ' ← ' || public._city_name(t.to_city), jsonb_build_object('booking_id', b.id));
  perform public._audit('booking.cancel', 'booking', b.id::text, jsonb_build_object('by', case when u = b.rider_id then 'rider' else 'driver' end));
end $$;

-- ── إدارة الرحلة للسائق ─────────────────────────────────────────────
create or replace function public.cancel_trip(p_trip uuid, p_reason text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  t public.trips;
  r record;
begin
  select * into t from public.trips where id = p_trip for update;
  if not found then perform public._fail('TRIP_NOT_FOUND'); end if;
  if t.driver_id <> u then perform public._fail('FORBIDDEN'); end if;
  if t.status <> 'scheduled' then perform public._fail('INVALID_STATE'); end if;
  for r in select id, rider_id from public.bookings where trip_id = t.id and status in ('pending', 'confirmed') loop
    update public.bookings set status = 'cancelled', cancelled_at = now(), cancel_reason = 'الرحلة انلغت' where id = r.id;
    perform public._notify(r.rider_id, 'trip.cancelled', 'السائق لغى الرحلة', coalesce(public._clean(p_reason, 200), 'دوّر على رحلة تانية بنفس الطريق'), jsonb_build_object('booking_id', r.id));
  end loop;
  update public.trips set status = 'cancelled', seats_available = seats_total where id = t.id;
  perform public._audit('trip.cancel', 'trip', t.id::text);
end $$;

create or replace function public.start_trip(p_trip uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  t public.trips;
begin
  select * into t from public.trips where id = p_trip for update;
  if not found then perform public._fail('TRIP_NOT_FOUND'); end if;
  if t.driver_id <> u then perform public._fail('FORBIDDEN'); end if;
  if t.status <> 'scheduled' then perform public._fail('INVALID_STATE'); end if;
  if now() < t.departure_at - interval '2 hours' then perform public._fail('TOO_EARLY'); end if;
  update public.trips set status = 'in_progress' where id = t.id;
  perform public._notify(b.rider_id, 'trip.started', 'الرحلة بلّشت', 'شارك موقعك مع أهلك من التذكرة', jsonb_build_object('trip_id', t.id))
  from public.bookings b where b.trip_id = t.id and b.status = 'confirmed';
  perform public._audit('trip.start', 'trip', t.id::text);
end $$;

create or replace function public.complete_trip(p_trip uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  t public.trips;
begin
  select * into t from public.trips where id = p_trip for update;
  if not found then perform public._fail('TRIP_NOT_FOUND'); end if;
  if t.driver_id <> u then perform public._fail('FORBIDDEN'); end if;
  if t.status not in ('scheduled', 'in_progress') then perform public._fail('INVALID_STATE'); end if;
  if now() < t.departure_at then perform public._fail('TOO_EARLY'); end if;
  update public.trips set status = 'completed' where id = t.id;
  update public.profiles set trips_count = trips_count + 1
  where id = t.driver_id or id in (select rider_id from public.bookings where trip_id = t.id and status = 'confirmed');
  perform public._notify(b.rider_id, 'trip.completed', 'وصلت بالسلامة', 'قيّم رحلتك مع السائق', jsonb_build_object('booking_id', b.id))
  from public.bookings b where b.trip_id = t.id and b.status = 'confirmed';
  update public.bookings set status = 'completed' where trip_id = t.id and status = 'confirmed';
  update public.bookings set status = 'cancelled', cancelled_at = now(), cancel_reason = 'ما انرد عالطلب' where trip_id = t.id and status = 'pending';
  delete from public.live_locations where trip_id = t.id;
  perform public._audit('trip.complete', 'trip', t.id::text);
end $$;

-- ── تفاصيل الحجز (الرقم والرمز بس بعد التأكيد) ──────────────────────
create or replace function public.booking_details(p_booking uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  u uuid := public._uid();
  b public.bookings;
  t public.trips;
  v public.vehicles;
  d public.profiles;
  r public.profiles;
  is_rider boolean;
  shown boolean;
begin
  select * into b from public.bookings where id = p_booking;
  if not found then perform public._fail('BOOKING_NOT_FOUND'); end if;
  select * into t from public.trips where id = b.trip_id;
  if b.rider_id <> u and t.driver_id <> u and not public.is_staff() then perform public._fail('FORBIDDEN'); end if;
  is_rider := b.rider_id = u;
  shown := b.status in ('confirmed', 'completed');
  select * into v from public.vehicles where id = t.vehicle_id;
  select * into d from public.profiles where id = t.driver_id;
  select * into r from public.profiles where id = b.rider_id;
  return jsonb_build_object(
    'id', b.id, 'status', b.status, 'seats', b.seats, 'family', b.family, 'created_at', b.created_at,
    'pin', case when is_rider and shown then b.pin end,
    'total', b.seats * t.price_syp,
    'trip', jsonb_build_object('id', t.id, 'from_city', t.from_city, 'to_city', t.to_city, 'from_spot', t.from_spot, 'to_spot', t.to_spot,
      'departure_at', t.departure_at, 'arrival_at', t.arrival_at, 'price_syp', t.price_syp, 'status', t.status, 'kind', t.kind,
      'stops', coalesce((select array_agg(s.city_id order by s.position) from public.trip_stops s where s.trip_id = t.id), '{}')),
    'driver', jsonb_build_object('id', d.id, 'full_name', d.full_name, 'avatar_path', d.avatar_path, 'rating_avg', d.rating_avg,
      'phone', case when shown then (select phone from public.profile_private where id = d.id) end),
    'rider', jsonb_build_object('id', r.id, 'full_name', r.full_name, 'rating_avg', r.rating_avg,
      'phone', case when shown and not is_rider then (select phone from public.profile_private where id = r.id) end),
    'vehicle', jsonb_build_object('make_model', v.make_model, 'color', v.color, 'plate', case when shown or not is_rider then v.plate end),
    'reviewed', exists (select 1 from public.reviews where booking_id = b.id)
  );
end $$;

create or replace function public.my_bookings() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.booking_details(b.id) order by t.departure_at), '[]'::jsonb)
  from public.bookings b join public.trips t on t.id = b.trip_id
  where b.rider_id = auth.uid() and (b.status in ('pending', 'confirmed') or (b.status = 'completed' and t.departure_at > now() - interval '90 days'));
$$;

create or replace function public.my_driver_trips() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'from_city', t.from_city, 'to_city', t.to_city, 'from_spot', t.from_spot, 'to_spot', t.to_spot,
    'departure_at', t.departure_at, 'arrival_at', t.arrival_at, 'price_syp', t.price_syp,
    'seats_total', t.seats_total, 'seats_available', t.seats_available, 'status', t.status, 'kind', t.kind, 'instant', t.instant,
    'bookings', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'status', b.status, 'seats', b.seats, 'family', b.family,
        'message', b.message, 'rider_id', p.id, 'rider_name', p.full_name, 'rider_rating', p.rating_avg) order by b.created_at)
      from public.bookings b join public.profiles p on p.id = b.rider_id where b.trip_id = t.id and b.status in ('pending', 'confirmed', 'completed')), '[]'::jsonb)
  ) order by t.departure_at), '[]'::jsonb)
  from public.trips t
  where t.driver_id = auth.uid() and (t.status in ('scheduled', 'in_progress') or t.departure_at > now() - interval '30 days');
$$;

-- ── التقييم ────────────────────────────────────────────────────────
create or replace function public.submit_review(p_booking uuid, p_stars int, p_tags text[] default '{}', p_comment text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  b public.bookings;
  t public.trips;
begin
  select * into b from public.bookings where id = p_booking;
  if not found then perform public._fail('BOOKING_NOT_FOUND'); end if;
  if b.rider_id <> u then perform public._fail('FORBIDDEN'); end if;
  if b.status <> 'completed' then perform public._fail('INVALID_STATE'); end if;
  if p_stars is null or p_stars < 1 or p_stars > 5 then perform public._fail('INVALID_INPUT'); end if;
  select * into t from public.trips where id = b.trip_id;
  begin
    insert into public.reviews (booking_id, author_id, target_id, stars, tags, comment)
    values (b.id, u, t.driver_id, p_stars,
            coalesce((select array_agg(public._clean(x, 30)) from unnest(p_tags) x where public._clean(x, 30) is not null), '{}'),
            public._clean(p_comment, 500));
  exception when unique_violation then
    perform public._fail('ALREADY_REVIEWED');
  end;
end $$;

create or replace function public.refresh_rating() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles p set
    rating_avg = coalesce((select round(avg(stars)::numeric, 2) from public.reviews where target_id = new.target_id), 0),
    rating_count = (select count(*) from public.reviews where target_id = new.target_id)
  where p.id = new.target_id;
  return new;
end $$;
create trigger reviews_refresh_rating after insert on public.reviews for each row execute function public.refresh_rating();

-- ── البلاغات (بعد بلاغين من شخصين مختلفين: إيقاف للمراجعة) ─────────
create or replace function public.submit_report(p_target uuid, p_trip uuid, p_reason text, p_details text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  v_id uuid;
begin
  if p_target is null or p_target = u or not exists (select 1 from public.profiles where id = p_target) then perform public._fail('INVALID_INPUT'); end if;
  if public._clean(p_reason, 60) is null then perform public._fail('INVALID_INPUT'); end if;
  if (select count(*) from public.reports where reporter_id = u and created_at > now() - interval '24 hours') >= 5 then perform public._fail('RATE_LIMITED'); end if;
  insert into public.reports (reporter_id, target_id, trip_id, reason, details)
  values (u, p_target, p_trip, public._clean(p_reason, 60), public._clean(p_details, 1000)) returning id into v_id;
  perform public._audit('report.create', 'profile', p_target::text, jsonb_build_object('report', v_id));
  return v_id;
end $$;

create or replace function public.auto_suspend() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(distinct reporter_id) from public.reports
      where target_id = new.target_id and status = 'open' and created_at > now() - interval '30 days') >= 2 then
    update public.profiles set driver_status = 'suspended', suspended_at = now()
    where id = new.target_id and driver_status = 'approved';
    if found then
      perform public._notify(new.target_id, 'driver.suspended', 'حسابك موقوف مؤقتاً', 'وصلنا أكتر من بلاغ، ورح نتواصل معك لنراجع', '{}'::jsonb);
      perform public._audit('driver.auto_suspend', 'profile', new.target_id::text);
      -- رحلاتو الجاية بتتلغى لحماية الركاب
      update public.bookings set status = 'cancelled', cancelled_at = now(), cancel_reason = 'السائق موقوف للمراجعة'
      where status in ('pending', 'confirmed') and trip_id in (select id from public.trips where driver_id = new.target_id and status = 'scheduled');
      update public.trips set status = 'cancelled' where driver_id = new.target_id and status = 'scheduled';
    end if;
  end if;
  return new;
end $$;
create trigger reports_auto_suspend after insert on public.reports for each row execute function public.auto_suspend();

-- ── الانضمام كسائق ─────────────────────────────────────────────────
create or replace function public.submit_driver_application(
  p_city text, p_make_model text, p_year int, p_color text, p_plate text, p_seats int, p_interview_at timestamptz
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  me public.profiles;
  v_vehicle uuid;
  v_app uuid;
begin
  select * into me from public.profiles where id = u for update;
  if me.gender is null or char_length(me.full_name) < 3 then perform public._fail('PROFILE_INCOMPLETE'); end if;
  if me.driver_status not in ('none', 'rejected') then perform public._fail('APPLICATION_ACTIVE'); end if;
  if not exists (select 1 from public.cities where id = p_city and active) then perform public._fail('INVALID_INPUT'); end if;
  if p_year is null or p_year < 2005 or p_year > extract(year from now())::int + 1 then perform public._fail('INVALID_VEHICLE'); end if;
  if public._clean(p_make_model, 60) is null or public._clean(p_color, 30) is null or char_length(coalesce(public._clean(p_plate, 30), '')) < 4 then perform public._fail('INVALID_VEHICLE'); end if;
  if p_seats is null or p_seats < 1 or p_seats > 7 then perform public._fail('INVALID_SEATS'); end if;
  if p_interview_at is null or p_interview_at < now() + interval '12 hours' or p_interview_at > now() + interval '30 days' then perform public._fail('INVALID_INTERVIEW'); end if;

  begin
    insert into public.vehicles (owner_id, make_model, year, color, plate, seats)
    values (u, public._clean(p_make_model, 60), p_year, public._clean(p_color, 30), upper(public._clean(p_plate, 30)), p_seats)
    returning id into v_vehicle;
  exception when unique_violation then
    perform public._fail('PLATE_TAKEN');
  end;

  insert into public.driver_applications (user_id, vehicle_id, city_id, interview_at, agreed_rules_at)
  values (u, v_vehicle, p_city, p_interview_at, now()) returning id into v_app;
  update public.profiles set driver_status = 'reviewing' where id = u;

  perform public._notify(p.id, 'admin.application', 'طلب سائق جديد', me.full_name || ' · ' || public._city_name(p_city), jsonb_build_object('application_id', v_app))
  from public.profiles p where p.role in ('moderator', 'admin');
  perform public._audit('application.submit', 'driver_application', v_app::text, jsonb_build_object('city', p_city));
  return v_app;
end $$;

create or replace function public.add_application_document(p_application uuid, p_kind public.document_kind, p_path text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  a public.driver_applications;
begin
  select * into a from public.driver_applications where id = p_application;
  if not found or a.user_id <> u then perform public._fail('FORBIDDEN'); end if;
  if a.status not in ('submitted', 'reviewing') then perform public._fail('INVALID_STATE'); end if;
  -- المسار لازم يكون جوا مجلد المستخدم والطلب: {uid}/{application}/...
  if p_path is null or p_path not like u::text || '/' || a.id::text || '/%' or p_path like '%..%' then perform public._fail('INVALID_INPUT'); end if;
  insert into public.application_documents (application_id, kind, storage_path) values (a.id, p_kind, p_path)
  on conflict (application_id, kind) do update set storage_path = excluded.storage_path, created_at = now();
end $$;

create or replace function public.cancel_driver_application()
returns void
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
begin
  update public.driver_applications set status = 'cancelled' where user_id = u and status in ('submitted', 'reviewing', 'interview');
  if not found then perform public._fail('INVALID_STATE'); end if;
  update public.profiles set driver_status = 'none' where id = u and driver_status in ('reviewing', 'interview');
  perform public._audit('application.cancel', 'profile', u::text);
end $$;

create or replace function public.my_application() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', a.id, 'status', a.status, 'city_id', a.city_id, 'interview_at', a.interview_at,
    'interview_place', a.interview_place, 'admin_note', a.admin_note, 'created_at', a.created_at,
    'vehicle', to_jsonb(v), 'documents', coalesce((select jsonb_agg(d.kind) from public.application_documents d where d.application_id = a.id), '[]'::jsonb))
  from public.driver_applications a join public.vehicles v on v.id = a.vehicle_id
  where a.user_id = auth.uid() order by a.created_at desc limit 1;
$$;

-- ── أدوات الإدارة ──────────────────────────────────────────────────
create or replace function public.admin_review_application(p_application uuid, p_status public.application_status, p_note text default null,
  p_interview_at timestamptz default null, p_place text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  a public.driver_applications;
  v_docs int;
begin
  if not public.is_staff() then perform public._fail('FORBIDDEN'); end if;
  select * into a from public.driver_applications where id = p_application for update;
  if not found then perform public._fail('NOT_FOUND'); end if;
  if not (
    (a.status in ('submitted', 'reviewing') and p_status in ('reviewing', 'interview', 'rejected'))
    or (a.status = 'interview' and p_status in ('approved', 'rejected', 'interview'))
  ) then perform public._fail('INVALID_STATE'); end if;
  select count(distinct kind) into v_docs from public.application_documents where application_id = a.id;
  if p_status in ('interview', 'approved') and v_docs < 9 then perform public._fail('DOCUMENTS_MISSING'); end if;

  update public.driver_applications set status = p_status, admin_note = public._clean(p_note, 1000),
    interview_at = coalesce(p_interview_at, interview_at), interview_place = coalesce(public._clean(p_place, 200), interview_place),
    reviewed_by = auth.uid(), reviewed_at = now()
  where id = a.id;

  update public.profiles set driver_status = case p_status
      when 'reviewing' then 'reviewing'::public.driver_status
      when 'interview' then 'interview'::public.driver_status
      when 'approved' then 'approved'::public.driver_status
      when 'rejected' then 'rejected'::public.driver_status end
  where id = a.user_id;
  if p_status = 'approved' then
    update public.vehicles set verified = true where id = a.vehicle_id;
  end if;

  perform public._notify(a.user_id, 'application.' || p_status::text,
    case p_status when 'interview' then 'موعد مقابلتك جاهز' when 'approved' then 'مبروك! صرت سائق موثّق' when 'rejected' then 'ما انقبل طلبك' else 'عم نراجع طلبك' end,
    coalesce(public._clean(p_note, 200), ''), jsonb_build_object('application_id', a.id));
  perform public._audit('application.' || p_status::text, 'driver_application', a.id::text, jsonb_build_object('note', public._clean(p_note, 200)));
end $$;

create or replace function public.admin_set_driver_status(p_user uuid, p_status public.driver_status, p_note text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff() then perform public._fail('FORBIDDEN'); end if;
  if p_status not in ('approved', 'suspended') then perform public._fail('INVALID_INPUT'); end if;
  update public.profiles set driver_status = p_status, suspended_at = case when p_status = 'suspended' then now() end where id = p_user;
  if not found then perform public._fail('NOT_FOUND'); end if;
  perform public._notify(p_user, 'driver.' || p_status::text, case when p_status = 'suspended' then 'حسابك موقوف' else 'رجع حسابك فعّال' end, coalesce(public._clean(p_note, 200), ''), '{}'::jsonb);
  perform public._audit('driver.' || p_status::text, 'profile', p_user::text, jsonb_build_object('note', public._clean(p_note, 200)));
end $$;

create or replace function public.admin_resolve_report(p_report uuid, p_status public.report_status)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff() then perform public._fail('FORBIDDEN'); end if;
  if p_status = 'open' then perform public._fail('INVALID_INPUT'); end if;
  update public.reports set status = p_status where id = p_report;
  if not found then perform public._fail('NOT_FOUND'); end if;
  perform public._audit('report.' || p_status::text, 'report', p_report::text);
end $$;

-- ── التتبع ومشاركة الموقع ───────────────────────────────────────────
create or replace function public.update_live_location(p_trip uuid, p_lat double precision, p_lon double precision,
  p_accuracy real default null, p_heading real default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  t public.trips;
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
  insert into public.live_locations (trip_id, user_id, lat, lon, accuracy, heading, updated_at)
  values (t.id, u, p_lat, p_lon, p_accuracy, p_heading, now())
  on conflict (trip_id, user_id) do update set lat = excluded.lat, lon = excluded.lon, accuracy = excluded.accuracy, heading = excluded.heading, updated_at = now();
end $$;

create or replace function public.create_share_link(p_booking uuid, p_hours int default 24)
returns text
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  b public.bookings;
  t public.trips;
  v_token text;
begin
  select * into b from public.bookings where id = p_booking;
  if not found or b.rider_id <> u then perform public._fail('FORBIDDEN'); end if;
  if b.status <> 'confirmed' then perform public._fail('INVALID_STATE'); end if;
  select * into t from public.trips where id = b.trip_id;
  insert into public.share_links (booking_id, created_by, expires_at)
  values (b.id, u, least(now() + make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 72))), t.arrival_at + interval '6 hours'))
  returning token into v_token;
  perform public._audit('share.create', 'booking', b.id::text);
  return v_token;
end $$;

create or replace function public.revoke_share_link(p_token text)
returns void
language sql security definer set search_path = public as $$
  update public.share_links set revoked = true where token = p_token and created_by = auth.uid();
$$;

-- صفحة الأهل (بلا تسجيل دخول): ملخص الرحلة وآخر موقع، بس إذا الرابط صالح.
create or replace function public.get_shared_trip(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s public.share_links;
  b public.bookings;
  t public.trips;
  v public.vehicles;
  loc public.live_locations;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{36}$' then return null; end if;
  select * into s from public.share_links where token = p_token;
  if not found or s.revoked or s.expires_at < now() then return null; end if;
  select * into b from public.bookings where id = s.booking_id;
  if b.status not in ('confirmed', 'completed') then return null; end if;
  select * into t from public.trips where id = b.trip_id;
  select * into v from public.vehicles where id = t.vehicle_id;
  select * into loc from public.live_locations where trip_id = t.id
  order by (user_id = t.driver_id) desc, updated_at desc limit 1;
  return jsonb_build_object(
    'from', public._city_name(t.from_city), 'to', public._city_name(t.to_city),
    'from_city', t.from_city, 'to_city', t.to_city,
    'departure_at', t.departure_at, 'arrival_at', t.arrival_at, 'status', t.status,
    'rider', split_part((select full_name from public.profiles where id = b.rider_id), ' ', 1),
    'driver', split_part((select full_name from public.profiles where id = t.driver_id), ' ', 1),
    'car', v.make_model || ' · ' || v.color, 'plate', v.plate,
    'location', case when loc.trip_id is null then null else jsonb_build_object('lat', loc.lat, 'lon', loc.lon, 'accuracy', loc.accuracy, 'updated_at', loc.updated_at) end,
    'expires_at', s.expires_at
  );
end $$;

-- ── الإشعارات ──────────────────────────────────────────────────────
create or replace function public.mark_notifications_read(p_ids bigint[] default null)
returns void
language sql security definer set search_path = public as $$
  update public.notifications set read_at = now()
  where user_id = auth.uid() and read_at is null and (p_ids is null or id = any (p_ids));
$$;

-- ═══════════════════════════════════════════════════════════════════
-- صلاحيات التنفيذ: ما حدا بيقدر يستدعي غير الدوال المسموحة
-- ═══════════════════════════════════════════════════════════════════
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.is_staff(), public.is_admin(), public.is_trip_driver(uuid), public.has_booking_on(uuid, boolean),
  public.is_booking_party(uuid) to anon, authenticated;

grant execute on function
  public.complete_profile(text, public.gender, text), public.my_profile(),
  public.search_trips(text, text, date, int), public.destination_stats(text, date),
  public.publish_trip(uuid, text, text, text, text, timestamptz, int, int, int, public.ride_kind, boolean, text[], text, text[]),
  public.request_booking(uuid, int, boolean, text), public.respond_booking(uuid, boolean), public.cancel_booking(uuid, text),
  public.cancel_trip(uuid, text), public.start_trip(uuid), public.complete_trip(uuid),
  public.booking_details(uuid), public.my_bookings(), public.my_driver_trips(),
  public.submit_review(uuid, int, text[], text), public.submit_report(uuid, uuid, text, text),
  public.submit_driver_application(text, text, int, text, text, int, timestamptz),
  public.add_application_document(uuid, public.document_kind, text), public.cancel_driver_application(), public.my_application(),
  public.admin_review_application(uuid, public.application_status, text, timestamptz, text),
  public.admin_set_driver_status(uuid, public.driver_status, text), public.admin_resolve_report(uuid, public.report_status),
  public.update_live_location(uuid, double precision, double precision, real, real),
  public.create_share_link(uuid, int), public.revoke_share_link(text),
  public.mark_notifications_read(bigint[])
to authenticated;

grant execute on function public.get_shared_trip(text) to anon, authenticated;
