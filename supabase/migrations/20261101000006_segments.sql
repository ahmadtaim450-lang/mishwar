-- ═══════════════════════════════════════════════════════════════════
-- مشوار: الحجز على جزء من الطريق. رحلة اللاذقية ← دمشق عبر طرطوس وحمص
-- بتظهر كمان لمين رايح من طرطوس لحمص، بسعر ووقت محسوبين حسب المسافة.
-- (المقعد بينحجز لكل الرحلة، أبسط وأوضح للسائق.)
-- ═══════════════════════════════════════════════════════════════════

alter table public.bookings
  add column if not exists from_city text references public.cities (id),
  add column if not exists to_city text references public.cities (id),
  add column if not exists price_syp integer check (price_syp is null or price_syp between 1000 and 2000000);

-- المسافة التقريبية بين مدينتين (كم)
create or replace function public._km(a text, b text) returns double precision
language sql stable security definer set search_path = public as $$
  select 6371 * 2 * asin(sqrt(
    power(sin(radians(c2.lat - c1.lat) / 2), 2) + cos(radians(c1.lat)) * cos(radians(c2.lat)) * power(sin(radians(c2.lon - c1.lon) / 2), 2)))
  from public.cities c1, public.cities c2 where c1.id = a and c2.id = b;
$$;

-- مسار الرحلة كامل: [الانطلاق، الوقفات...، الوصول]
create or replace function public._route(p_trip uuid) returns text[]
language sql stable security definer set search_path = public as $$
  select array[t.from_city] || coalesce((select array_agg(s.city_id order by s.position) from public.trip_stops s where s.trip_id = t.id), '{}') || array[t.to_city]
  from public.trips t where t.id = p_trip;
$$;

-- وقت وسعر جزء من الطريق حسب نسبة المسافة
create or replace function public._segment(p_trip uuid, p_from text, p_to text,
  out dep timestamptz, out arr timestamptz, out price int, out ok boolean)
language plpgsql stable security definer set search_path = public as $$
declare
  t public.trips;
  r text[] := public._route(p_trip);
  i int; j int; k int;
  total double precision := 0; before double precision := 0; seg double precision := 0; leg double precision;
begin
  select * into t from public.trips where id = p_trip;
  i := array_position(r, p_from); j := array_position(r, p_to);
  ok := i is not null and j is not null and i < j;
  if not ok then return; end if;
  for k in 1 .. array_length(r, 1) - 1 loop
    leg := coalesce(public._km(r[k], r[k + 1]), 0);
    total := total + leg;
    if k < i then before := before + leg; elsif k < j then seg := seg + leg; end if;
  end loop;
  if total <= 0 then total := 1; end if;
  dep := t.departure_at + (t.arrival_at - t.departure_at) * (before / total);
  arr := t.departure_at + (t.arrival_at - t.departure_at) * ((before + seg) / total);
  price := case when i = 1 and j = array_length(r, 1) then t.price_syp
                else greatest(1000, (round(t.price_syp * (seg / total) / 1000) * 1000)::int) end;
end $$;

-- ── البحث: الرحلة كاملة أو أي جزء منها ─────────────────────────────
drop function if exists public.search_trips(text, text, date, int);
create function public.search_trips(p_from text, p_to text, p_date date, p_seats int default 1)
returns table (
  id uuid, from_city text, to_city text, from_spot text, to_spot text,
  departure_at timestamptz, arrival_at timestamptz, price_syp int, seats_total smallint, seats_available smallint,
  kind public.ride_kind, instant boolean, prefs text[], note text, stops text[],
  driver_id uuid, driver_name text, driver_avatar text, driver_rating numeric, driver_reviews int, driver_trips int,
  car text, full_from text, full_to text
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_gender public.gender := (select gender from public.profiles where profiles.id = auth.uid());
begin
  if p_from is null or p_to is null or p_from = p_to or p_date is null then perform public._fail('INVALID_INPUT'); end if;
  if p_seats is null or p_seats < 1 or p_seats > 7 then perform public._fail('INVALID_INPUT'); end if;
  return query
  select t.id, p_from, p_to,
         case when p_from = t.from_city then t.from_spot else coalesce((select c.spots[1] from public.cities c where c.id = p_from), 'على الطريق') end,
         case when p_to = t.to_city then t.to_spot else coalesce((select c.spots[1] from public.cities c where c.id = p_to), 'على الطريق') end,
         sg.dep, sg.arr, sg.price, t.seats_total, t.seats_available, t.kind, t.instant, t.prefs, t.note,
         coalesce((select array_agg(s.city_id order by s.position) from public.trip_stops s where s.trip_id = t.id), '{}'),
         p.id, p.full_name, p.avatar_path, p.rating_avg, p.rating_count, p.trips_count,
         v.make_model || ' · ' || v.color, t.from_city, t.to_city
  from public.trips t
  join public.profiles p on p.id = t.driver_id
  join public.vehicles v on v.id = t.vehicle_id
  cross join lateral public._segment(t.id, p_from, p_to) sg
  where t.status = 'scheduled'
    and (t.from_city = p_from or exists (select 1 from public.trip_stops s where s.trip_id = t.id and s.city_id = p_from))
    and (t.to_city = p_to or exists (select 1 from public.trip_stops s where s.trip_id = t.id and s.city_id = p_to))
    and sg.ok
    and (sg.dep at time zone 'Asia/Damascus')::date = p_date
    and sg.dep > now()
    and t.seats_available >= p_seats
    and p.driver_status = 'approved'
    and (v_gender is null
         or (v_gender = 'male' and t.kind in ('men', 'family'))
         or (v_gender = 'female' and t.kind in ('women', 'family')))
  order by sg.dep
  limit 100;
end $$;

create or replace function public.destination_stats(p_from text, p_date date)
returns table (to_city text, trips bigint, min_price int)
language sql stable security definer set search_path = public as $$
  select dest, count(distinct t.id), min(sg.price)
  from public.trips t
  join public.profiles p on p.id = t.driver_id
  cross join lateral unnest(public._route(t.id)) with ordinality as r(dest, pos)
  cross join lateral public._segment(t.id, p_from, r.dest) sg
  where t.status = 'scheduled' and t.seats_available > 0 and p.driver_status = 'approved'
    and sg.ok and (sg.dep at time zone 'Asia/Damascus')::date = p_date and sg.dep > now()
  group by dest;
$$;

-- ── الحجز على جزء ──────────────────────────────────────────────────
drop function if exists public.request_booking(uuid, int, boolean, text);
create function public.request_booking(p_trip uuid, p_seats int, p_family boolean default false, p_message text default null,
  p_from text default null, p_to text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  me public.profiles;
  t public.trips;
  sg record;
  v_from text; v_to text;
  v_status public.booking_status;
  b public.bookings;
begin
  select * into me from public.profiles where id = u;
  if me.gender is null or char_length(me.full_name) < 3 then perform public._fail('PROFILE_INCOMPLETE'); end if;
  if me.suspended_at is not null then perform public._fail('ACCOUNT_SUSPENDED'); end if;
  if p_seats is null or p_seats < 1 or p_seats > 7 then perform public._fail('INVALID_SEATS'); end if;

  select * into t from public.trips where id = p_trip for update;
  if not found then perform public._fail('TRIP_NOT_FOUND'); end if;
  v_from := coalesce(p_from, t.from_city);
  v_to := coalesce(p_to, t.to_city);
  select * into sg from public._segment(t.id, v_from, v_to);
  if not sg.ok then perform public._fail('INVALID_ROUTE'); end if;
  if t.status <> 'scheduled' or sg.dep <= now() then perform public._fail('TRIP_NOT_BOOKABLE'); end if;
  if t.driver_id = u then perform public._fail('OWN_TRIP'); end if;
  if (t.kind = 'women' and me.gender <> 'female') or (t.kind = 'men' and me.gender <> 'male') then perform public._fail('GENDER_RESTRICTED'); end if;
  if t.kind = 'family' and not coalesce(p_family, false) then perform public._fail('FAMILY_ONLY'); end if;
  if p_seats > t.seats_available then perform public._fail('NOT_ENOUGH_SEATS'); end if;
  if exists (select 1 from public.bookings where trip_id = t.id and rider_id = u and status in ('pending', 'confirmed')) then perform public._fail('ALREADY_BOOKED'); end if;
  if (select count(*) from public.bookings where rider_id = u and created_at > now() - interval '1 hour') >= 10 then perform public._fail('RATE_LIMITED'); end if;

  v_status := case when t.instant then 'confirmed' else 'pending' end;
  insert into public.bookings (trip_id, rider_id, seats, family, status, pin, message, decided_at, from_city, to_city, price_syp)
  values (t.id, u, p_seats, coalesce(p_family, false), v_status, lpad((floor(random() * 10000))::int::text, 4, '0'),
          public._clean(p_message, 500), case when t.instant then now() end, v_from, v_to, sg.price)
  returning * into b;

  if t.instant then
    update public.trips set seats_available = seats_available - p_seats where id = t.id;
  end if;
  perform public._notify(t.driver_id, case when t.instant then 'booking.confirmed' else 'booking.requested' end,
    case when t.instant then 'حجز جديد' else 'طلب حجز جديد' end,
    me.full_name || ' · ' || p_seats || ' مقعد · ' || public._city_name(v_from) || ' ← ' || public._city_name(v_to),
    jsonb_build_object('booking_id', b.id, 'trip_id', t.id));
  perform public._audit('booking.request', 'booking', b.id::text, jsonb_build_object('trip', t.id, 'seats', p_seats, 'status', v_status, 'from', v_from, 'to', v_to));
  return jsonb_build_object('id', b.id, 'status', b.status, 'pin', b.pin);
end $$;

-- ── تفاصيل الحجز حسب جزء الراكب ─────────────────────────────────────
create or replace function public.booking_details(p_booking uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  u uuid := public._uid();
  b public.bookings;
  t public.trips;
  v public.vehicles;
  d public.profiles;
  r public.profiles;
  sg record;
  is_rider boolean;
  shown boolean;
  v_from text; v_to text; v_price int;
begin
  select * into b from public.bookings where id = p_booking;
  if not found then perform public._fail('BOOKING_NOT_FOUND'); end if;
  select * into t from public.trips where id = b.trip_id;
  if b.rider_id <> u and t.driver_id <> u and not public.is_staff() then perform public._fail('FORBIDDEN'); end if;
  is_rider := b.rider_id = u;
  shown := b.status in ('confirmed', 'completed');
  v_from := coalesce(b.from_city, t.from_city);
  v_to := coalesce(b.to_city, t.to_city);
  select * into sg from public._segment(t.id, v_from, v_to);
  v_price := coalesce(b.price_syp, t.price_syp);
  select * into v from public.vehicles where id = t.vehicle_id;
  select * into d from public.profiles where id = t.driver_id;
  select * into r from public.profiles where id = b.rider_id;
  return jsonb_build_object(
    'id', b.id, 'status', b.status, 'seats', b.seats, 'family', b.family, 'created_at', b.created_at,
    'pin', case when is_rider and shown then b.pin end,
    'total', b.seats * v_price,
    'trip', jsonb_build_object('id', t.id, 'from_city', v_from, 'to_city', v_to,
      'from_spot', case when v_from = t.from_city then t.from_spot else coalesce((select c.spots[1] from public.cities c where c.id = v_from), 'على الطريق') end,
      'to_spot', case when v_to = t.to_city then t.to_spot else coalesce((select c.spots[1] from public.cities c where c.id = v_to), 'على الطريق') end,
      'departure_at', coalesce(sg.dep, t.departure_at), 'arrival_at', coalesce(sg.arr, t.arrival_at), 'price_syp', v_price, 'status', t.status, 'kind', t.kind,
      'full_from', t.from_city, 'full_to', t.to_city,
      'stops', coalesce((select array_agg(s.city_id order by s.position) from public.trip_stops s where s.trip_id = t.id), '{}')),
    'driver', jsonb_build_object('id', d.id, 'full_name', d.full_name, 'avatar_path', d.avatar_path, 'rating_avg', d.rating_avg,
      'phone', case when shown then (select phone from public.profile_private where id = d.id) end),
    'rider', jsonb_build_object('id', r.id, 'full_name', r.full_name, 'rating_avg', r.rating_avg,
      'phone', case when shown and not is_rider then (select phone from public.profile_private where id = r.id) end),
    'vehicle', jsonb_build_object('make_model', v.make_model, 'color', v.color, 'plate', case when shown or not is_rider then v.plate end),
    'reviewed', exists (select 1 from public.reviews where booking_id = b.id)
  );
end $$;

-- السائق بيشوف وين بيطلع وبينزل كل راكب
create or replace function public.my_driver_trips() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'from_city', t.from_city, 'to_city', t.to_city, 'from_spot', t.from_spot, 'to_spot', t.to_spot,
    'departure_at', t.departure_at, 'arrival_at', t.arrival_at, 'price_syp', t.price_syp,
    'seats_total', t.seats_total, 'seats_available', t.seats_available, 'status', t.status, 'kind', t.kind, 'instant', t.instant,
    'stops', coalesce((select array_agg(s.city_id order by s.position) from public.trip_stops s where s.trip_id = t.id), '{}'),
    'bookings', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'status', b.status, 'seats', b.seats, 'family', b.family,
        'message', b.message, 'rider_id', p.id, 'rider_name', p.full_name, 'rider_rating', p.rating_avg,
        'from_city', coalesce(b.from_city, t.from_city), 'to_city', coalesce(b.to_city, t.to_city), 'price_syp', coalesce(b.price_syp, t.price_syp)) order by b.created_at)
      from public.bookings b join public.profiles p on p.id = b.rider_id where b.trip_id = t.id and b.status in ('pending', 'confirmed', 'completed')), '[]'::jsonb)
  ) order by t.departure_at), '[]'::jsonb)
  from public.trips t
  where t.driver_id = auth.uid() and (t.status in ('scheduled', 'in_progress') or t.departure_at > now() - interval '30 days');
$$;

revoke execute on function public._km(text, text), public._route(uuid), public._segment(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.search_trips(text, text, date, int), public.request_booking(uuid, int, boolean, text, text, text) from public, anon;
grant execute on function public.search_trips(text, text, date, int), public.request_booking(uuid, int, boolean, text, text, text),
  public.destination_stats(text, date), public.booking_details(uuid), public.my_driver_trips() to authenticated;
