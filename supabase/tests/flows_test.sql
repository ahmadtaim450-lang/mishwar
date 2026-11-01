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
    if sqlerrm = p_code or (p_code = 'DENIED' and (sqlstate in ('42501') or sqlerrm like '%row-level security%' or sqlerrm like '%permission denied%')) then
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
select t.ok((select trips_count from public.profiles where id = '00000000-0000-0000-0000-00000000000d') = 1, 'driver trips counted');

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

\echo '▶ التخزين: كل واحد بمجلدو'
reset role;
select t.ok(exists (select 1 from storage.buckets where id = 'driver-docs' and not public), 'private docs bucket');

\echo '✓ كل اختبارات قاعدة البيانات نجحت'
rollback;
