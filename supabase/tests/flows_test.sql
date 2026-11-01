-- ═══════════════════════════════════════════════════════════════════
-- اختبارات قاعدة البيانات: الصلاحيات، والحجز، والتوثيق، والتتبع.
-- بتشتغل على Supabase المحلي (CI) أو على Postgres مع local_stubs.sql.
-- أي فشل بيوقّف السكربت برسالة واضحة.
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP 1
\set QUIET 1

begin;

create schema t;
grant usage on schema t to anon, authenticated;

-- بيتوقع إنو الأمر يفشل برمز معيّن (أو برفض صلاحية)
create function t.expect_error(p_sql text, p_code text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm = p_code or (p_code = 'DENIED_OR_CHECK' and sqlstate in ('23514', '42501')) or (p_code = 'DENIED' and (sqlstate in ('42501') or sqlerrm like '%row-level security%' or sqlerrm like '%permission denied%')) then
      return;
    end if;
    raise exception 'FAIL: % → expected %, got % (%)', p_sql, p_code, sqlerrm, sqlstate;
  end;
  raise exception 'FAIL: % → expected error %, but it succeeded', p_sql, p_code;
end $$;
create function t.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if p_cond is distinct from true then raise exception 'FAIL: %', p_msg; end if;
end $$;
grant execute on all functions in schema t to anon, authenticated;
create table t.ids (k text primary key, v uuid);
grant select, insert, update on t.ids to authenticated, anon;
create table t.vals (k text primary key, v text);
grant select, insert, update on t.vals to authenticated, anon;

-- المستخدمين
insert into auth.users (id, phone) values
  ('00000000-0000-0000-0000-00000000000a', '963900000001'),  -- إدارة
  ('00000000-0000-0000-0000-00000000000d', '963900000002'),  -- سائق
  ('00000000-0000-0000-0000-00000000000f', '963900000003'),  -- سائقة
  ('00000000-0000-0000-0000-000000000001', '963900000004'),  -- راكب
  ('00000000-0000-0000-0000-000000000002', '963900000005'),  -- راكب تاني
  ('00000000-0000-0000-0000-000000000003', '963900000006'),  -- راكبة
  ('00000000-0000-0000-0000-000000000009', '963900000007');  -- غريب
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000000a';

\echo '▶ الملف الشخصي والصلاحيات'
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select t.ok((select count(*) from public.profiles where id = auth.uid()) = 1, 'profile auto-created');
select t.expect_error($$select public.complete_profile('ا', 'male')$$, 'INVALID_NAME');
select public.complete_profile('سامي الراكب', 'male', 'no_music');
select t.expect_error($$select public.complete_profile('سامي الراكب', 'female')$$, 'GENDER_LOCKED');
select t.expect_error($$update public.profiles set role = 'admin' where id = auth.uid()$$, 'DENIED');
select t.expect_error($$update public.profiles set driver_status = 'approved' where id = auth.uid()$$, 'DENIED');
update public.profiles set full_name = 'سامي ر.' where id = auth.uid();
select t.expect_error($$insert into public.trips (driver_id) values (auth.uid())$$, 'DENIED');
select t.expect_error($$insert into public.bookings (trip_id) values (gen_random_uuid())$$, 'DENIED');
select t.ok((select count(*) from public.profile_private) = 1, 'sees only own private row');
select t.ok((select (public.my_profile() ->> 'phone')) = '963900000004', 'my_profile phone');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select public.complete_profile('رامي الراكب', 'male');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
select public.complete_profile('ريم الراكبة', 'female');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000009', true);
select public.complete_profile('غريب الغريب', 'male');

\echo '▶ طلب الانضمام كسائق'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
select t.expect_error($$select public.submit_driver_application('latakia', 'كيا ريو', 2015, 'فضي', 'LAT 123456', 4, now() + interval '2 days')$$, 'PROFILE_INCOMPLETE');
select public.complete_profile('سامر السائق', 'male');
select t.expect_error($$select public.submit_driver_application('latakia', 'كيا ريو', 1999, 'فضي', 'LAT 123456', 4, now() + interval '2 days')$$, 'INVALID_VEHICLE');
select t.expect_error($$select public.submit_driver_application('latakia', 'كيا ريو', 2015, 'فضي', 'LAT 123456', 4, now() + interval '1 hour')$$, 'INVALID_INTERVIEW');
insert into t.ids values ('app_d', public.submit_driver_application('latakia', 'كيا ريو', 2015, 'فضي', 'LAT 123456', 4, now() + interval '2 days'));
select t.expect_error($$select public.submit_driver_application('latakia', 'كيا ريو', 2016, 'أبيض', 'LAT 999999', 4, now() + interval '2 days')$$, 'APPLICATION_ACTIVE');
select t.ok((select driver_status from public.profiles where id = auth.uid()) = 'reviewing', 'status reviewing');
select t.ok((select count(*) from public.vehicles where owner_id = auth.uid() and not verified) = 1, 'vehicle unverified');
select t.expect_error(format($$select public.add_application_document(%L, 'selfie', 'someone-else/x.jpg')$$, (select v from t.ids where k = 'app_d')), 'INVALID_INPUT');
select t.expect_error(format($$select public.add_application_document(%L, 'selfie', %L)$$, (select v from t.ids where k = 'app_d'), auth.uid() || '/' || (select v from t.ids where k = 'app_d') || '/../x.jpg'), 'INVALID_INPUT');
select public.add_application_document((select v from t.ids where k = 'app_d'), k::public.document_kind, auth.uid() || '/' || (select v from t.ids where k = 'app_d') || '/' || k || '.jpg')
from unnest(array['selfie', 'id_front', 'id_back', 'license', 'record', 'car_front', 'car_side', 'car_inside']) k;
select t.expect_error($$select public.publish_trip(gen_random_uuid(), 'latakia', 'damascus', null, null, now() + interval '1 day', 240, 75000, 3, 'men')$$, 'NOT_APPROVED_DRIVER');

-- الراكب ما بيقدر يراجع طلبات
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select t.expect_error(format($$select public.admin_review_application(%L, 'approved')$$, (select v from t.ids where k = 'app_d')), 'FORBIDDEN');
select t.ok((select count(*) from public.driver_applications) = 0, 'rider cannot read applications');

\echo '▶ الإدارة: مراجعة ومقابلة وتفعيل'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', true);
select t.ok((select count(*) from public.driver_applications) = 1, 'admin reads applications');
select t.expect_error(format($$select public.admin_review_application(%L, 'interview')$$, (select v from t.ids where k = 'app_d')), 'DOCUMENTS_MISSING');
select t.expect_error(format($$select public.admin_review_application(%L, 'approved')$$, (select v from t.ids where k = 'app_d')), 'INVALID_STATE');
-- الوثيقة التاسعة
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
select public.add_application_document((select v from t.ids where k = 'app_d'), 'mechanic', auth.uid() || '/' || (select v from t.ids where k = 'app_d') || '/mechanic.jpg');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', true);
select public.admin_review_application((select v from t.ids where k = 'app_d'), 'interview', 'جيب الأوراق الأصلية', now() + interval '2 days', 'نقطة مشوار · اللاذقية');
select public.admin_review_application((select v from t.ids where k = 'app_d'), 'approved', 'أهلا فيك');
reset role;
select t.ok((select driver_status from public.profiles where id = '00000000-0000-0000-0000-00000000000d') = 'approved', 'driver approved');
select t.ok((select verified from public.vehicles where owner_id = '00000000-0000-0000-0000-00000000000d'), 'vehicle verified');
select t.ok((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-00000000000d' and kind = 'application.approved') = 1, 'approval notification');
insert into t.ids values ('veh_d', (select id from public.vehicles where owner_id = '00000000-0000-0000-0000-00000000000d'));

\echo '▶ نشر رحلة'
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
select t.expect_error(format($$select public.publish_trip(%L, 'latakia', 'damascus', null, null, now() + interval '1 day', 240, 75000, 3, 'women')$$, (select v from t.ids where k = 'veh_d')), 'GENDER_RESTRICTED');
select t.expect_error(format($$select public.publish_trip(%L, 'latakia', 'latakia', null, null, now() + interval '1 day', 240, 75000, 3, 'men')$$, (select v from t.ids where k = 'veh_d')), 'INVALID_ROUTE');
select t.expect_error(format($$select public.publish_trip(%L, 'latakia', 'damascus', null, null, now() + interval '10 minutes', 240, 75000, 3, 'men')$$, (select v from t.ids where k = 'veh_d')), 'INVALID_DEPARTURE');
select t.expect_error(format($$select public.publish_trip(%L, 'latakia', 'damascus', null, null, now() + interval '1 day', 240, 75000, 9, 'men')$$, (select v from t.ids where k = 'veh_d')), 'INVALID_SEATS');
select t.expect_error(format($$select public.publish_trip(%L, 'latakia', 'damascus', null, null, now() + interval '1 day', 240, 75000, 3, 'men', false, '{}', null, array['damascus'])$$, (select v from t.ids where k = 'veh_d')), 'INVALID_ROUTE');
insert into t.ids values ('trip', public.publish_trip((select v from t.ids where k = 'veh_d'), 'latakia', 'damascus', 'الكورنيش', 'البرامكة',
  date_trunc('day', now() at time zone 'Asia/Damascus') at time zone 'Asia/Damascus' + interval '1 day 10 hours', 240, 75000, 3, 'men', false, array['ممنوع التدخين'], 'السلام عليكم <script>', array['tartus', 'homs']));
select t.expect_error(format($$select public.publish_trip(%L, 'latakia', 'homs', null, null, %L::timestamptz + interval '1 hour', 120, 45000, 3, 'men')$$,
  (select v from t.ids where k = 'veh_d'), (select departure_at from public.trips where id = (select v from t.ids where k = 'trip'))), 'TRIP_OVERLAP');
insert into t.vals values ('day', ((select departure_at from public.trips where id = (select v from t.ids where k = 'trip')) at time zone 'Asia/Damascus')::date::text);

\echo '▶ البحث حسب الجنس'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
select t.ok((select count(*) from public.search_trips('latakia', 'damascus', (select v from t.vals where k = 'day')::date)) = 0, 'woman does not see men trip');
select t.expect_error(format($$select public.request_booking(%L, 1)$$, (select v from t.ids where k = 'trip')), 'GENDER_RESTRICTED');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select t.ok((select count(*) from public.search_trips('latakia', 'damascus', (select v from t.vals where k = 'day')::date)) = 1, 'man sees men trip');
select t.ok((select count(*) from public.search_trips('latakia', 'damascus', (select v from t.vals where k = 'day')::date, 4)) = 0, 'seat filter');
select t.ok((select stops from public.search_trips('latakia', 'damascus', (select v from t.vals where k = 'day')::date)) = array['tartus', 'homs'], 'stops ordered');
select t.ok((select trips from public.destination_stats('latakia', (select v from t.vals where k = 'day')::date) where to_city = 'damascus') = 1, 'destination stats');
select t.expect_error($$select * from public.search_trips('latakia', 'latakia', current_date)$$, 'INVALID_INPUT');

\echo '▶ الحجز على جزء من الطريق'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select t.ok((select count(*) from public.search_trips('tartus', 'homs', (select v from t.vals where k = 'day')::date)) = 1, 'segment tartus→homs found');
select t.ok((select count(*) from public.search_trips('homs', 'tartus', (select v from t.vals where k = 'day')::date)) = 0, 'reverse segment not found');
select t.ok((select price_syp from public.search_trips('tartus', 'homs', (select v from t.vals where k = 'day')::date)) < 75000, 'segment cheaper than full');
select t.ok((select departure_at from public.search_trips('tartus', 'homs', (select v from t.vals where k = 'day')::date))
            > (select departure_at from public.trips where id = (select v from t.ids where k = 'trip')), 'segment departs later');
select t.ok((select full_from from public.search_trips('tartus', 'homs', (select v from t.vals where k = 'day')::date)) = 'latakia', 'full route exposed');
select t.ok((select trips from public.destination_stats('tartus', (select v from t.vals where k = 'day')::date) where to_city = 'damascus') = 1, 'stats from a stop');
select t.expect_error(format($$select public.request_booking(%L, 1, false, null, 'homs', 'tartus')$$, (select v from t.ids where k = 'trip')), 'INVALID_ROUTE');
insert into t.ids values ('seg', (public.request_booking((select v from t.ids where k = 'trip'), 1, false, null, 'tartus', 'homs') ->> 'id')::uuid);
select t.ok((public.booking_details((select v from t.ids where k = 'seg')) -> 'trip' ->> 'from_city') = 'tartus', 'ticket shows rider segment');
select t.ok((public.booking_details((select v from t.ids where k = 'seg')) ->> 'total')::int < 75000, 'segment total');
select public.cancel_booking((select v from t.ids where k = 'seg'));
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

\echo '▶ الحجز والموافقة'
select t.expect_error(format($$select public.request_booking(%L, 4)$$, (select v from t.ids where k = 'trip')), 'NOT_ENOUGH_SEATS');
insert into t.ids values ('b1', (public.request_booking((select v from t.ids where k = 'trip'), 2, false, 'معي شنتاية صغيرة') ->> 'id')::uuid);
select t.expect_error(format($$select public.request_booking(%L, 1)$$, (select v from t.ids where k = 'trip')), 'ALREADY_BOOKED');
select t.ok((select status from public.bookings where id = (select v from t.ids where k = 'b1')) = 'pending', 'pending booking');
select t.ok((public.booking_details((select v from t.ids where k = 'b1')) ->> 'pin') is null, 'pin hidden while pending');
select t.ok((public.booking_details((select v from t.ids where k = 'b1')) -> 'vehicle' ->> 'plate') is null, 'plate hidden while pending');
select t.ok((public.booking_details((select v from t.ids where k = 'b1')) -> 'driver' ->> 'phone') is null, 'phone hidden while pending');
select t.expect_error(format($$select public.respond_booking(%L, true)$$, (select v from t.ids where k = 'b1')), 'FORBIDDEN');
select t.expect_error($$select public.complete_trip((select v from t.ids where k = 'trip'))$$, 'FORBIDDEN');

-- الغريب ما بيشوف شي
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000009', true);
select t.ok((select count(*) from public.bookings) = 0, 'stranger sees no bookings');
select t.expect_error(format($$select public.booking_details(%L)$$, (select v from t.ids where k = 'b1')), 'FORBIDDEN');
select t.expect_error(format($$insert into public.messages (booking_id, sender_id, body) values (%L, auth.uid(), 'مرحبا')$$, (select v from t.ids where k = 'b1')), 'DENIED');
select t.ok((select count(*) from public.vehicles) = 0, 'stranger cannot read vehicles');

-- السائق بيوافق
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
select t.ok(jsonb_array_length(public.my_driver_trips() -> 0 -> 'bookings') = 1, 'driver sees request');
select t.ok(public.respond_booking((select v from t.ids where k = 'b1'), true) = 'confirmed', 'accepted');
select t.expect_error(format($$select public.respond_booking(%L, true)$$, (select v from t.ids where k = 'b1')), 'INVALID_STATE');
select t.ok((select seats_available from public.trips where id = (select v from t.ids where k = 'trip')) = 1, 'seats decremented');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select t.expect_error(format($$select public.request_booking(%L, 2)$$, (select v from t.ids where k = 'trip')), 'NOT_ENOUGH_SEATS');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select t.ok((public.booking_details((select v from t.ids where k = 'b1')) ->> 'pin') ~ '^[0-9]{4}$', 'pin shown after confirm');
select t.ok((public.booking_details((select v from t.ids where k = 'b1')) -> 'vehicle' ->> 'plate') = 'LAT 123456', 'plate shown after confirm');
select t.ok((public.booking_details((select v from t.ids where k = 'b1')) -> 'driver' ->> 'phone') = '963900000002', 'driver phone after confirm');
select t.ok(jsonb_array_length(public.my_bookings()) = 1, 'my bookings');
insert into public.messages (booking_id, sender_id, body) values ((select v from t.ids where k = 'b1'), auth.uid(), 'وين نقطة الانطلاق بالزبط؟');
select t.expect_error(format($$insert into public.messages (booking_id, sender_id, body) values (%L, '00000000-0000-0000-0000-00000000000d', 'انتحال')$$, (select v from t.ids where k = 'b1')), 'DENIED');
select t.ok((select count(*) from public.notifications where kind = 'booking.confirmed') = 1, 'rider notified');

\echo '▶ مشاركة الموقع والتتبع'
insert into t.vals values ('token', public.create_share_link((select v from t.ids where k = 'b1'), 24));
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
select t.expect_error(format($$select public.update_live_location(%L, 35.5, 35.8)$$, (select v from t.ids where k = 'trip')), 'TRACKING_CLOSED');
reset role;
update public.trips set departure_at = now() + interval '1 hour', arrival_at = now() + interval '5 hours' where id = (select v from t.ids where k = 'trip');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
select public.update_live_location((select v from t.ids where k = 'trip'), 35.40, 35.90, 12, 180);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000009', true);
select t.expect_error(format($$select public.update_live_location(%L, 35.5, 35.8)$$, (select v from t.ids where k = 'trip')), 'FORBIDDEN');
select t.ok((select count(*) from public.live_locations) = 0, 'stranger cannot read locations');
reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select t.ok((public.get_shared_trip((select v from t.vals where k = 'token')) -> 'location' ->> 'lat')::float = 35.40, 'family sees live location');
select t.ok((public.get_shared_trip((select v from t.vals where k = 'token')) ->> 'driver') = 'سامر', 'family sees driver first name');
select t.ok(public.get_shared_trip(repeat('a', 36)) is null, 'bad token');
select t.ok(public.get_shared_trip('x'' or 1=1 --') is null, 'injection-shaped token');
select t.expect_error($$select public.my_bookings()$$, 'DENIED');
select t.expect_error($$select * from public.trips$$, 'DENIED');
reset role;

\echo '▶ الخرائط: نقطة التجمع والسياج الجغرافي'
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000009', true);
select t.expect_error(format($$select public.set_trip_points(%L, 35.515, 35.79)$$, (select v from t.ids where k = 'trip')), 'FORBIDDEN');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
select t.expect_error(format($$select public.set_trip_points(%L, 33.51, 36.27)$$, (select v from t.ids where k = 'trip')), 'POINT_TOO_FAR');
select t.expect_error(format($$select public.set_trip_points(%L, 35.515, null)$$, (select v from t.ids where k = 'trip')), 'INVALID_INPUT');
select public.set_trip_points((select v from t.ids where k = 'trip'), 35.5150, 35.7900, 33.5085, 36.2900);
-- قراءة ضعيفة الدقة ما بتطلق الإشعار
select public.update_live_location((select v from t.ids where k = 'trip'), 35.516, 35.791, 2000, 0);
select t.expect_error(format($$select public.update_live_location(%L, 35.516, 35.791, -1, 0)$$, (select v from t.ids where k = 'trip')), 'INVALID_INPUT');
reset role;
select t.ok((select count(*) from public.notifications where kind = 'driver_near') = 0, 'inaccurate fix: no geofence alert');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
select public.update_live_location((select v from t.ids where k = 'trip'), 35.520, 35.795, 15, 0);
select public.update_live_location((select v from t.ids where k = 'trip'), 35.518, 35.792, 15, 0);
reset role;
select t.ok((select count(*) from public.notifications where kind = 'driver_near' and user_id = '00000000-0000-0000-0000-000000000001') = 1, 'driver near → rider alerted once');
select t.ok((select near_notified_at is not null from public.bookings where id = (select v from t.ids where k = 'b1')), 'alert recorded');

\echo '▶ الخرائط: الرحلات ضمن حدود الخريطة وبالقرب'
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select t.ok((select count(*) from public.map_trips(35.3, 35.6, 35.7, 36.0)) = 1, 'trip boards inside latakia view');
select t.ok((select exact and abs(lat - 35.515) < 0.0001 from public.map_trips(35.3, 35.6, 35.7, 36.0)), 'exact pickup point used');
select t.ok((select count(*) from public.map_trips(36.0, 36.9, 36.4, 37.4)) = 0, 'nothing in aleppo view');
select t.ok((select board_city = 'homs' and to_city = 'damascus' and price_syp < 75000 and not exact from public.map_trips(34.6, 36.5, 34.9, 36.9)), 'boarding at a stop = segment price');
select t.ok((select count(*) from public.map_trips(32, 35, 37.5, 42.5)) = 3, 'one row per boarding point (latakia, tartus, homs)');
select t.ok((select to_city from public.map_trips(35.3, 35.6, 35.7, 36.0, p_to => 'homs')) = 'homs', 'destination filter → segment');
select t.ok((select count(*) from public.map_trips(32, 35, 37.5, 42.5, p_kinds => array['women']::public.ride_kind[])) = 0, 'kind filter');
select t.ok((select count(*) from public.map_trips(32, 35, 37.5, 42.5, p_seats => 5)) = 0, 'seats filter');
select t.ok((select count(*) from public.map_trips(32, 35, 37.5, 42.5, p_max_price => 30000)) < 3, 'price filter');
select t.ok((select distance_km < 2 from public.trips_near(35.52, 35.78, 10) limit 1), 'trips near me sorted by distance');
select t.ok((select count(*) from public.trips_near(36.20, 37.13, 20)) = 0, 'nothing near aleppo');
select t.ok((select array_agg(board_city order by distance_km) from public.map_trips(32, 35, 37.5, 42.5, p_lat => 34.73, p_lon => 36.71)) = array['homs', 'tartus', 'latakia'], 'ordered by distance from me');
select t.expect_error($$select * from public.map_trips(36, 35, 35, 36)$$, 'INVALID_INPUT');
select t.expect_error($$select * from public.trips_near(35.5, 35.8, 1000)$$, 'INVALID_INPUT');
select t.expect_error($$select * from public.map_trips(35, 35, 36, 36, p_seats => 0)$$, 'INVALID_INPUT');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
select t.ok((select count(*) from public.map_trips(32, 35, 37.5, 42.5)) = 0, 'woman does not see men trip on map');
select t.ok((select departures from public.city_activity(7) where city_id = 'latakia') = 1, 'city activity');

\echo '▶ الخرائط: البحث الجغرافي'
select t.ok((select id from public.search_places('حمص') limit 1) = 'homs', 'search arabic');
select t.ok((select id from public.search_places('Damaskus') limit 1) = 'damascus', 'search german');
select t.ok((select id from public.search_places('lat') limit 1) = 'latakia', 'search english prefix');
select t.ok((select id from public.search_places('اللاذقيه') limit 1) = 'latakia', 'search normalized ة/ال');
select t.ok((select id from public.search_places('', 35.36, 35.93) limit 1) = 'jableh', 'empty query → nearest first');
select t.ok((select count(*) from public.search_places('zzzz')) = 0, 'no match');
select t.ok((select id from public.nearest_city(35.40, 35.90)) = 'jableh', 'nearest city');
select t.expect_error($$select * from public.search_places(repeat('x', 81))$$, 'INVALID_INPUT');
select t.expect_error($$select * from public.nearest_city(null, 1)$$, 'INVALID_INPUT');

\echo '▶ الخرائط: الأماكن المحفوظة'
select public.save_place('البيت', 35.52, 35.79, 'home', 'الزراعة');
select public.save_place('بيت أهلي', 35.53, 35.80, 'home');
select t.ok((select count(*) from public.my_places() where kind = 'home') = 1, 'one home only');
select public.save_place('الجامعة', 35.54, 35.81);
select public.save_place('الجامعة', 35.55, 35.82);
select t.ok((select lat from public.my_places() where label = 'الجامعة') = 35.55, 'same label updates');
select t.ok((select kind from public.search_places('جامع') limit 1) = 'saved', 'saved places are searchable');
select t.expect_error($$select public.save_place('برلين', 52.5, 13.4)$$, 'OUTSIDE_SYRIA');
select t.expect_error($$select public.save_place('', 35.5, 35.8)$$, 'INVALID_INPUT');
select t.expect_error($$select public.save_place('x', 35.5, 35.8, 'castle')$$, 'INVALID_INPUT');
select t.expect_error($$insert into public.saved_places (user_id, label, lat, lon) values (auth.uid(), 'x', 35.5, 35.8)$$, 'DENIED');
insert into t.ids values ('place', (select id from public.my_places() where label = 'الجامعة'));
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000009', true);
select t.ok((select count(*) from public.my_places()) = 0, 'others cannot see my places');
select t.ok((select count(*) from public.saved_places) = 0, 'RLS on saved places');
select t.ok((select count(*) from public.search_places('جامع') where kind = 'saved') = 0, 'saved places private in search');
select t.expect_error(format($$select public.delete_place(%L)$$, (select v from t.ids where k = 'place')), 'NOT_FOUND');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
select public.delete_place((select v from t.ids where k = 'place'));
select t.ok((select count(*) from public.my_places()) = 1, 'deleted');

\echo '▶ الخرائط: نقاط التجمع (الإدارة)'
select t.expect_error($$select public.admin_upsert_place(null, 'homs', 'كراج تجريبي', 'garage', 34.73, 36.71)$$, 'FORBIDDEN');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', true);
select t.expect_error($$select public.admin_upsert_place(null, 'homs', 'كراج بعيد', 'garage', 33.51, 36.27)$$, 'POINT_TOO_FAR');
select t.expect_error($$select public.admin_upsert_place(null, 'homs', 'برّا', 'garage', 40, 30)$$, 'OUTSIDE_SYRIA');
insert into t.ids values ('poi', public.admin_upsert_place(null, 'homs', 'كراج الانطلاق الشمالي', 'garage', 34.745, 36.715, 'North Garage', 'Nordbusbahnhof'));
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select t.ok((select count(*) from public.city_places('homs')) = 1, 'city places');
select t.ok((select kind from public.search_places('Nordbus') limit 1) = 'garage', 'poi searchable in german');
select t.expect_error(format($$update public.places set name_ar = 'تخريب' where id = %L$$, (select v from t.ids where k = 'poi')), 'DENIED');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', true);
select public.admin_set_place_active((select v from t.ids where k = 'poi'), false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select t.ok((select count(*) from public.city_places('homs')) = 0, 'inactive place hidden');
select t.ok((select count(*) from public.places) = 0, 'inactive place hidden (RLS)');
select t.expect_error($$select public.geo_take(auth.uid())$$, 'DENIED');
reset role;
select t.ok((select count(*) from public.audit_log where action like 'place.%') = 2, 'place changes audited');
select t.ok(public.geo_take('00000000-0000-0000-0000-000000000001', 2) and public.geo_take('00000000-0000-0000-0000-000000000001', 2)
            and not public.geo_take('00000000-0000-0000-0000-000000000001', 2), 'geo rate limit');
set local role anon;
select t.expect_error($$select * from public.map_trips(32, 35, 37.5, 42.5)$$, 'DENIED');
select t.expect_error($$select * from public.search_places('حمص')$$, 'DENIED');
reset role;

\echo '▶ الإلغاء بيرجّع المقاعد'
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select public.cancel_booking((select v from t.ids where k = 'b1'), 'تغيّرت خطتي');
select t.ok((select seats_available from public.trips where id = (select v from t.ids where k = 'trip')) = 3, 'seats returned');
select t.expect_error(format($$select public.cancel_booking(%L)$$, (select v from t.ids where k = 'b1')), 'INVALID_STATE');
reset role;
select t.ok(public.get_shared_trip((select v from t.vals where k = 'token')) is null, 'share link dies with cancelled booking');

\echo '▶ إكمال الرحلة والتقييم'
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
insert into t.ids values ('b2', (public.request_booking((select v from t.ids where k = 'trip'), 1) ->> 'id')::uuid);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
select public.respond_booking((select v from t.ids where k = 'b2'), true);
select t.expect_error($$select public.complete_trip((select v from t.ids where k = 'trip'))$$, 'TOO_EARLY');
select public.start_trip((select v from t.ids where k = 'trip'));
reset role;
update public.trips set departure_at = now() - interval '4 hours', arrival_at = now() - interval '10 minutes' where id = (select v from t.ids where k = 'trip');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
select public.complete_trip((select v from t.ids where k = 'trip'));
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select t.expect_error(format($$select public.submit_review(%L, 5)$$, (select v from t.ids where k = 'b1')), 'INVALID_STATE');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select t.expect_error(format($$select public.submit_review(%L, 6)$$, (select v from t.ids where k = 'b2')), 'INVALID_INPUT');
select public.submit_review((select v from t.ids where k = 'b2'), 4, array['عالوقت'], 'منيح');
select t.expect_error(format($$select public.submit_review(%L, 5)$$, (select v from t.ids where k = 'b2')), 'ALREADY_REVIEWED');
select t.ok((select rating_avg from public.profiles where id = '00000000-0000-0000-0000-00000000000d') = 4.00, 'rating aggregated');
select t.expect_error(format($$select public.submit_rider_review(%L, 5)$$, (select v from t.ids where k = 'b2')), 'FORBIDDEN');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
select public.submit_rider_review((select v from t.ids where k = 'b2'), 5, array['محترم'], 'راكب ممتاز');
select t.expect_error(format($$select public.submit_rider_review(%L, 4)$$, (select v from t.ids where k = 'b2')), 'ALREADY_REVIEWED');
select t.ok((select rating_avg from public.profiles where id = '00000000-0000-0000-0000-000000000002') = 5.00, 'rider rated by driver');
select t.ok((select rating_avg from public.profiles where id = '00000000-0000-0000-0000-00000000000d') = 4.00, 'driver rating unchanged');
select t.ok((public.my_driver_trips() -> 0 -> 'bookings' -> 0 ->> 'reviewed')::boolean or (public.my_driver_trips() -> 1 -> 'bookings' -> 0 ->> 'reviewed')::boolean, 'driver sees reviewed flag');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select t.ok((public.booking_details((select v from t.ids where k = 'b2')) ->> 'driver_reviewed')::boolean, 'rider sees driver reviewed them');
select t.ok((select trips_count from public.profiles where id = '00000000-0000-0000-0000-00000000000d') = 1, 'driver trips counted');

\echo '▶ ملف السائق العام والتفضيلات'
select t.ok((public.driver_public('00000000-0000-0000-0000-00000000000d') ->> 'rating_count')::int = 1, 'driver public rating count');
select t.ok((public.driver_public('00000000-0000-0000-0000-00000000000d') -> 'reviews' -> 0 ->> 'author') = 'رامي', 'review author first name only');
select t.ok((public.driver_public('00000000-0000-0000-0000-00000000000d') -> 'histogram' ->> '4')::int = 1, 'histogram');
select t.ok(not (public.driver_public('00000000-0000-0000-0000-00000000000d') ? 'phone'), 'no phone in public profile');
update public.profiles set travel_prefs = '{"music": "no_music", "talk": "quiet"}' where id = auth.uid();
select t.expect_error($$update public.profiles set travel_prefs = '[1,2]' where id = auth.uid()$$, 'DENIED_OR_CHECK');

\echo '▶ البلاغات والإيقاف التلقائي'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
insert into t.ids values ('trip2', public.publish_trip((select v from t.ids where k = 'veh_d'), 'latakia', 'homs', null, null, now() + interval '3 days', 150, 45000, 3, 'men'));
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select t.expect_error($$select public.submit_report(auth.uid(), null, 'تجربة')$$, 'INVALID_INPUT');
select public.submit_report('00000000-0000-0000-0000-00000000000d', null, 'سواقة خطرة', 'سرعة زايدة');
select public.submit_report('00000000-0000-0000-0000-00000000000d', null, 'سواقة خطرة', 'مرة تانية');
reset role;
select t.ok((select driver_status from public.profiles where id = '00000000-0000-0000-0000-00000000000d') = 'approved', 'same reporter twice does not suspend');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select public.submit_report('00000000-0000-0000-0000-00000000000d', (select v from t.ids where k = 'trip'), 'تصرف غير محترم');
reset role;
select t.ok((select driver_status from public.profiles where id = '00000000-0000-0000-0000-00000000000d') = 'suspended', 'auto suspended after 2 reporters');
select t.ok((select status from public.trips where id = (select v from t.ids where k = 'trip2')) = 'cancelled', 'upcoming trips cancelled');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', true);
select t.expect_error(format($$select public.publish_trip(%L, 'latakia', 'damascus', null, null, now() + interval '5 days', 240, 75000, 3, 'men')$$, (select v from t.ids where k = 'veh_d')), 'NOT_APPROVED_DRIVER');
select t.ok((select count(*) from public.reports) = 0, 'reported driver cannot read reports');

\echo '▶ الصورة الشخصية وأرقام الإدارة'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
update public.profiles set avatar_path = auth.uid() || '/avatar-1.jpg' where id = auth.uid();
select t.expect_error($$update public.profiles set avatar_path = '00000000-0000-0000-0000-00000000000d/avatar.jpg' where id = auth.uid()$$, 'INVALID_INPUT');
select t.expect_error($$select public.admin_stats()$$, 'FORBIDDEN');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', true);
select t.ok((public.admin_stats() ->> 'users')::int >= 7, 'admin stats');

\echo '▶ أجهزة الإشعارات'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select t.expect_error($$select public.register_device('short', 'android')$$, 'INVALID_INPUT');
select public.register_device(repeat('t', 40), 'android');
select public.register_device(repeat('t', 40), 'android');
select t.ok((select count(*) from public.device_tokens) = 1, 'token registered once');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select t.ok((select count(*) from public.device_tokens) = 0, 'other users cannot see tokens');
select t.expect_error($$insert into public.device_tokens (token, user_id, platform) values (repeat('x', 40), auth.uid(), 'web')$$, 'DENIED');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select public.unregister_device(repeat('t', 40));
select t.ok((select count(*) from public.device_tokens) = 0, 'token removed');

\echo '▶ طلب حذف الحساب'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000009', true);
select public.request_account_deletion();
reset role;
select t.ok((select deletion_requested_at is not null from public.profiles where id = '00000000-0000-0000-0000-000000000009'), 'deletion requested');
select t.ok((select count(*) from public.notifications where kind = 'admin.deletion') = 1, 'admin notified about deletion');
set local role authenticated;

\echo '▶ الإشعارات والسجل'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select t.ok((select count(*) from public.notifications where user_id <> auth.uid()) = 0, 'only own notifications');
select public.mark_notifications_read();
select t.ok((select count(*) from public.notifications where read_at is null) = 0, 'marked read');
select t.ok((select count(*) from public.audit_log) = 0, 'rider cannot read audit');
select t.expect_error($$select public._audit('x', 'y', 'z')$$, 'DENIED');
select t.expect_error($$select public._notify(auth.uid(), 'x', 'y', 'z')$$, 'DENIED');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', true);
select t.ok((select count(*) from public.audit_log) > 10, 'admin reads audit');
select public.admin_set_driver_status('00000000-0000-0000-0000-00000000000d', 'approved', 'انحلّت المشكلة');
select t.ok((select driver_status from public.profiles where id = '00000000-0000-0000-0000-00000000000d') = 'approved', 'admin reinstated driver');

\echo '▶ الصيانة الدورية'
reset role;
-- رحلة منسية: وصلت من 13 ساعة ولسا مجدولة، وفيها طلب معلّق وحجز مؤكد
update public.trips set status = 'scheduled', departure_at = now() - interval '18 hours', arrival_at = now() - interval '13 hours', seats_available = 3
where id = (select v from t.ids where k = 'trip2');
update public.profiles set driver_status = 'approved', suspended_at = null where id = '00000000-0000-0000-0000-00000000000d';
insert into public.bookings (trip_id, rider_id, seats, status, pin) values
  ((select v from t.ids where k = 'trip2'), '00000000-0000-0000-0000-000000000001', 1, 'confirmed', '1111'),
  ((select v from t.ids where k = 'trip2'), '00000000-0000-0000-0000-000000000002', 1, 'pending', '2222');
select t.ok((public.maintenance() ->> 'trips_completed')::int >= 1, 'forgotten trip auto-completed');
select t.ok((select status from public.trips where id = (select v from t.ids where k = 'trip2')) = 'completed', 'trip completed');
select t.ok((select count(*) from public.bookings where trip_id = (select v from t.ids where k = 'trip2') and status = 'completed') = 1, 'confirmed → completed (can review)');
select t.ok((select count(*) from public.bookings where trip_id = (select v from t.ids where k = 'trip2') and status = 'pending') = 0, 'pending expired');
select t.ok((public.maintenance() ->> 'trips_completed')::int = 0, 'idempotent');

\echo '▶ التخزين: كل واحد بمجلدو'
reset role;
select t.ok(exists (select 1 from storage.buckets where id = 'driver-docs' and not public), 'private docs bucket');

\echo '✓ كل اختبارات قاعدة البيانات نجحت'
rollback;
