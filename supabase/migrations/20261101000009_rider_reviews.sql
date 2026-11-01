-- ═══════════════════════════════════════════════════════════════════
-- مشوار: تقييم بالاتجاهين. السائق كمان بيقيّم الركاب بعد الرحلة،
-- فالسائقين بيشوفوا تقييم الراكب قبل ما يقبلوا طلبو.
-- ═══════════════════════════════════════════════════════════════════

alter table public.reviews drop constraint if exists reviews_booking_id_key;
create unique index if not exists reviews_booking_author on public.reviews (booking_id, author_id);

create or replace function public.submit_rider_review(p_booking uuid, p_stars int, p_tags text[] default '{}', p_comment text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  u uuid := public._uid();
  b public.bookings;
  t public.trips;
begin
  select * into b from public.bookings where id = p_booking;
  if not found then perform public._fail('BOOKING_NOT_FOUND'); end if;
  select * into t from public.trips where id = b.trip_id;
  if t.driver_id <> u then perform public._fail('FORBIDDEN'); end if;
  if b.status <> 'completed' then perform public._fail('INVALID_STATE'); end if;
  if p_stars is null or p_stars < 1 or p_stars > 5 then perform public._fail('INVALID_INPUT'); end if;
  begin
    insert into public.reviews (booking_id, author_id, target_id, stars, tags, comment)
    values (b.id, u, b.rider_id, p_stars,
            coalesce((select array_agg(public._clean(x, 30)) from unnest(p_tags) x where public._clean(x, 30) is not null), '{}'),
            public._clean(p_comment, 500));
  exception when unique_violation then
    perform public._fail('ALREADY_REVIEWED');
  end;
end $$;

-- تقييم الراكب نفسو للسائق: مخصص لمراجعات الركاب عن السائق بس
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

-- السائق بيعرف مين قيّم من ركابو
create or replace function public.my_driver_trips() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'from_city', t.from_city, 'to_city', t.to_city, 'from_spot', t.from_spot, 'to_spot', t.to_spot,
    'departure_at', t.departure_at, 'arrival_at', t.arrival_at, 'price_syp', t.price_syp,
    'seats_total', t.seats_total, 'seats_available', t.seats_available, 'status', t.status, 'kind', t.kind, 'instant', t.instant,
    'stops', coalesce((select array_agg(s.city_id order by s.position) from public.trip_stops s where s.trip_id = t.id), '{}'),
    'bookings', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'status', b.status, 'seats', b.seats, 'family', b.family,
        'message', b.message, 'rider_id', p.id, 'rider_name', p.full_name, 'rider_rating', p.rating_avg, 'rider_reviews', p.rating_count,
        'from_city', coalesce(b.from_city, t.from_city), 'to_city', coalesce(b.to_city, t.to_city), 'price_syp', coalesce(b.price_syp, t.price_syp),
        'reviewed', exists (select 1 from public.reviews r where r.booking_id = b.id and r.author_id = t.driver_id)) order by b.created_at)
      from public.bookings b join public.profiles p on p.id = b.rider_id where b.trip_id = t.id and b.status in ('pending', 'confirmed', 'completed')), '[]'::jsonb)
  ) order by t.departure_at), '[]'::jsonb)
  from public.trips t
  where t.driver_id = auth.uid() and (t.status in ('scheduled', 'in_progress') or t.departure_at > now() - interval '30 days');
$$;

-- reviewed بتفاصيل الحجز = الراكب قيّم (مو السائق)
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
    'reviewed', exists (select 1 from public.reviews where booking_id = b.id and author_id = b.rider_id),
    'driver_reviewed', exists (select 1 from public.reviews where booking_id = b.id and author_id = t.driver_id)
  );
end $$;

create or replace function public.rider_reviewed(p_booking uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.reviews r join public.bookings b on b.id = r.booking_id where r.booking_id = p_booking and r.author_id = b.rider_id);
$$;

revoke execute on function public.submit_rider_review(uuid, int, text[], text), public.rider_reviewed(uuid) from public, anon;
grant execute on function public.submit_rider_review(uuid, int, text[], text), public.submit_review(uuid, int, text[], text), public.my_driver_trips() to authenticated;
revoke execute on function public.rider_reviewed(uuid) from authenticated;
