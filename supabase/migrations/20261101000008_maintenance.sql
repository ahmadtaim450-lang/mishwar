-- ═══════════════════════════════════════════════════════════════════
-- مشوار: صيانة دورية (كل نص ساعة إذا pg_cron متاح)
--  · الرحلات اللي السائق نسي ينهيها بتخلص لحالها بعد 12 ساعة من الوصول
--  · الطلبات اللي ما انرد عليها لحد الانطلاق بتنلغى
--  · تنظيف المواقع الحية والروابط المنتهية والإشعارات القديمة
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.maintenance() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_trips int := 0; v_expired int := 0;
  r record;
begin
  -- طلبات معلّقة والرحلة انطلقت
  with x as (
    update public.bookings b set status = 'cancelled', cancelled_at = now(), cancel_reason = 'ما انرد عالطلب'
    from public.trips t
    where b.trip_id = t.id and b.status = 'pending' and t.departure_at < now()
    returning b.rider_id, b.id
  )
  select count(*) into v_expired from (
    select public._notify(rider_id, 'booking.expired', 'ما انرد على طلبك', 'الرحلة انطلقت. دوّر على رحلة تانية', jsonb_build_object('booking_id', id)) from x
  ) n;

  -- رحلات خلصت والسائق ما سكّرها
  for r in select id, driver_id from public.trips
           where status in ('scheduled', 'in_progress') and arrival_at < now() - interval '12 hours' loop
    update public.trips set status = 'completed' where id = r.id;
    update public.profiles set trips_count = trips_count + 1
    where id = r.driver_id or id in (select rider_id from public.bookings where trip_id = r.id and status = 'confirmed');
    perform public._notify(b.rider_id, 'trip.completed', 'كيف كانت رحلتك؟', 'قيّم السائق لتساعد غيرك', jsonb_build_object('booking_id', b.id))
    from public.bookings b where b.trip_id = r.id and b.status = 'confirmed';
    update public.bookings set status = 'completed' where trip_id = r.id and status = 'confirmed';
    v_trips := v_trips + 1;
  end loop;

  delete from public.live_locations l using public.trips t where l.trip_id = t.id and (t.status in ('completed', 'cancelled') or t.arrival_at < now() - interval '6 hours');
  delete from public.share_links where expires_at < now() - interval '7 days';
  delete from public.notifications where created_at < now() - interval '90 days';
  if v_trips > 0 or v_expired > 0 then
    insert into public.audit_log (actor_id, action, entity, entity_id, meta)
    values (null, 'maintenance', 'system', null, jsonb_build_object('trips_completed', v_trips, 'requests_expired', v_expired));
  end if;
  return jsonb_build_object('trips_completed', v_trips, 'requests_expired', v_expired);
end $$;

revoke execute on function public.maintenance() from public, anon, authenticated;

-- الجدولة (Supabase فيه pg_cron)
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('mishwar-maintenance', '*/30 * * * *', 'select public.maintenance()');
  end if;
exception when others then
  raise notice 'pg_cron غير متاح، الصيانة بتشتغل يدوياً: select public.maintenance()';
end $$;
