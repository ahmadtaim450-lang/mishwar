// اختبار شامل على Supabase المحلي الحقيقي (Auth + REST + Storage):
// نفس المسار اللي بيمشي فيه التطبيق ولوحة الإدارة، من أول التسجيل لمشاركة الموقع.
// التشغيل: API_URL=... ANON_KEY=... SERVICE_ROLE_KEY=... node supabase/tests/e2e.mjs
import { createClient } from '@supabase/supabase-js';

const { API_URL, ANON_KEY, SERVICE_ROLE_KEY } = process.env;
if (!API_URL || !ANON_KEY || !SERVICE_ROLE_KEY) throw new Error('missing env');
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(API_URL, SERVICE_ROLE_KEY, opts);
const anon = createClient(API_URL, ANON_KEY, opts);

let fails = 0;
const ok = (cond, msg) => { console.log(`${cond ? '✓' : '✗'} ${msg}`); if (!cond) fails++; };
const must = (r, msg) => { if (r.error) { console.log(`✗ ${msg}: ${r.error.message}`); fails++; } else console.log(`✓ ${msg}`); return r.data; };
const denied = (r, code, msg) => ok(!!r.error && (!code || (r.error.message || '').includes(code)), `${msg}${r.error ? '' : ' (نجح وكان لازم يفشل)'}`);

async function user(email, name, gender, role) {
  const created = await service.auth.admin.createUser({ email, password: 'Test-pass-123!', email_confirm: true });
  if (created.error) throw created.error;
  const c = createClient(API_URL, ANON_KEY, opts);
  const s = await c.auth.signInWithPassword({ email, password: 'Test-pass-123!' });
  if (s.error) throw s.error;
  if (role) await service.from('profiles').update({ role }).eq('id', created.data.user.id);
  if (name) must(await c.rpc('complete_profile', { p_full_name: name, p_gender: gender }), `إكمال ملف ${name}`);
  return { c, id: created.data.user.id };
}

const stamp = Date.now();
const admin = await user(`admin${stamp}@mishwar.test`, 'مدير مشوار', 'male', 'admin');
const driver = await user(`driver${stamp}@mishwar.test`, 'سامر السائق', 'male');
const rider = await user(`rider${stamp}@mishwar.test`, 'رامي الراكب', 'male');
const stranger = await user(`x${stamp}@mishwar.test`, 'غريب الغريب', 'male');

console.log('▶ طلب السائق مع رفع الأوراق');
const interview = new Date(Date.now() + 2 * 86400e3).toISOString();
const appId = must(await driver.c.rpc('submit_driver_application', { p_city: 'latakia', p_make_model: 'كيا ريو', p_year: 2015, p_color: 'فضي', p_plate: `LAT ${stamp % 1000000}`, p_seats: 4, p_interview_at: interview }), 'تقديم الطلب');
const jpeg = Buffer.from('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==', 'base64');
const kinds = ['selfie', 'id_front', 'id_back', 'license', 'record', 'car_front', 'car_side', 'car_inside', 'mechanic'];
for (const k of kinds) {
  const p = `${driver.id}/${appId}/${k}.jpg`;
  const up = await driver.c.storage.from('driver-docs').upload(p, jpeg, { contentType: 'image/jpeg', upsert: true });
  if (up.error) { ok(false, `رفع ${k}: ${up.error.message}`); continue; }
  const r = await driver.c.rpc('add_application_document', { p_application: appId, p_kind: k, p_path: p });
  if (r.error) ok(false, `تسجيل ${k}: ${r.error.message}`);
}
ok(true, 'رفع 9 أوراق');
denied(await driver.c.storage.from('driver-docs').upload(`${rider.id}/hack.jpg`, jpeg, { contentType: 'image/jpeg' }), null, 'ما بيقدر يرفع بمجلد غيرو');
denied(await rider.c.storage.from('driver-docs').download(`${driver.id}/${appId}/selfie.jpg`), null, 'الراكب ما بيقدر يشوف أوراق السائق');
denied(await anon.storage.from('driver-docs').download(`${driver.id}/${appId}/selfie.jpg`), null, 'الزائر ما بيقدر يشوف الأوراق');

console.log('▶ لوحة الإدارة');
const apps = must(await admin.c.from('driver_applications').select('id, status, user:profiles!driver_applications_user_id_fkey(full_name), vehicle:vehicles(plate), application_documents(kind, storage_path)').eq('id', appId), 'الإدارة بتقرا الطلب مع السيارة والأوراق');
ok(apps?.[0]?.application_documents?.length === 9 && apps[0].user.full_name === 'سامر السائق', 'تفاصيل الطلب كاملة');
const signed = await admin.c.storage.from('driver-docs').createSignedUrls(kinds.map((k) => `${driver.id}/${appId}/${k}.jpg`), 60);
ok(!signed.error && signed.data.every((s) => s.signedUrl), 'الإدارة بتفتح الأوراق بروابط مؤقتة');
ok((await rider.c.from('driver_applications').select('id')).data?.length === 0, 'الراكب ما بيشوف طلبات');
denied(await rider.c.rpc('admin_review_application', { p_application: appId, p_status: 'approved' }), 'FORBIDDEN', 'الراكب ما بيقدر يوافق');
must(await admin.c.rpc('admin_review_application', { p_application: appId, p_status: 'interview', p_note: 'جيب الأوراق', p_interview_at: interview, p_place: 'نقطة مشوار' }), 'تحديد مقابلة');
must(await admin.c.rpc('admin_review_application', { p_application: appId, p_status: 'approved', p_note: null, p_interview_at: null, p_place: null }), 'تفعيل السائق');
const stats = must(await admin.c.rpc('admin_stats'), 'أرقام لوحة الإدارة');
ok(stats?.drivers >= 1 && stats?.users >= 4, 'الأرقام منطقية');
denied(await rider.c.rpc('admin_stats'), 'FORBIDDEN', 'الراكب ما بيشوف أرقام الإدارة');
const prof = must(await driver.c.rpc('my_profile'), 'ملف السائق');
ok(prof?.driver_status === 'approved' && prof?.vehicle?.verified === true, 'السائق صار موثّق وسيارتو مفحوصة');

console.log('▶ نشر وبحث وحجز');
const dep = new Date(Date.now() + 26 * 3600e3);
const tripId = must(await driver.c.rpc('publish_trip', { p_vehicle: prof.vehicle.id, p_from: 'latakia', p_to: 'damascus', p_from_spot: 'الكورنيش', p_to_spot: 'البرامكة', p_departure: dep.toISOString(), p_duration_min: 240, p_price: 75000, p_seats: 3, p_kind: 'men', p_instant: false, p_prefs: ['ممنوع التدخين'], p_note: null, p_stops: ['tartus', 'homs'] }), 'نشر رحلة');
const day = new Date(dep.getTime() + 3 * 3600e3).toISOString().slice(0, 10);
const found = must(await rider.c.rpc('search_trips', { p_from: 'latakia', p_to: 'damascus', p_date: day, p_seats: 1 }), 'البحث');
ok(found?.some((t) => t.id === tripId && t.driver_name === 'سامر السائق'), 'الرحلة بالنتائج مع اسم السائق');
ok(found?.every((t) => !('plate' in t)), 'البحث ما بيكشف رقم السيارة');
denied(await anon.from('trips').select('id'), null, 'الزائر ما بيقرا الرحلات');
denied(await rider.c.from('trips').insert({ driver_id: rider.id }), null, 'ما في إدخال مباشر بجدول الرحلات');

const req = must(await rider.c.rpc('request_booking', { p_trip: tripId, p_seats: 2, p_family: false, p_message: 'معي شنتاية' }), 'طلب حجز');
ok(req?.status === 'pending' && /^\d{4}$/.test(req?.pin), 'الطلب بانتظار الموافقة');
let det = must(await rider.c.rpc('booking_details', { p_booking: req.id }), 'تفاصيل الحجز');
ok(det.pin === null && det.vehicle.plate === null && det.driver.phone === null, 'الرمز والرقم مخفيين قبل الموافقة');
denied(await stranger.c.rpc('booking_details', { p_booking: req.id }), 'FORBIDDEN', 'الغريب ما بيشوف الحجز');
denied(await rider.c.rpc('respond_booking', { p_booking: req.id, p_accept: true }), 'FORBIDDEN', 'الراكب ما بيوافق على حجزو');
must(await driver.c.rpc('respond_booking', { p_booking: req.id, p_accept: true }), 'السائق وافق');
det = must(await rider.c.rpc('booking_details', { p_booking: req.id }), 'تفاصيل بعد الموافقة');
ok(/^\d{4}$/.test(det.pin) && det.vehicle.plate?.startsWith('LAT'), 'الرمز والرقم ظهروا بعد الموافقة');
const dtrips = must(await driver.c.rpc('my_driver_trips'), 'رحلات السائق');
ok(dtrips?.[0]?.seats_available === 1 && dtrips[0].bookings.length === 1, 'المقاعد نقصت والطلب ظاهر');

console.log('▶ الرسائل والإشعارات');
must(await rider.c.from('messages').insert({ booking_id: req.id, sender_id: rider.id, body: 'وين بالزبط؟' }), 'الراكب بعت رسالة');
denied(await stranger.c.from('messages').insert({ booking_id: req.id, sender_id: stranger.id, body: 'سبام' }), null, 'الغريب ما بيبعت رسائل');
ok((await driver.c.from('messages').select('body').eq('booking_id', req.id)).data?.[0]?.body === 'وين بالزبط؟', 'السائق بيقرا الرسالة');
ok((await stranger.c.from('messages').select('id').eq('booking_id', req.id)).data?.length === 0, 'الغريب ما بيقرا الرسائل');
const notes = (await rider.c.from('notifications').select('kind')).data || [];
ok(notes.some((n) => n.kind === 'booking.confirmed'), 'إشعار الموافقة وصل للراكب');
must(await rider.c.rpc('mark_notifications_read', { p_ids: null }), 'قراءة الإشعارات');

console.log('▶ مشاركة الموقع مع الأهل');
const token = must(await rider.c.rpc('create_share_link', { p_booking: req.id, p_hours: 24 }), 'إنشاء رابط');
const shared = must(await anon.rpc('get_shared_trip', { p_token: token }), 'الأهل بيفتحوا الرابط بلا حساب');
ok(shared?.from === 'اللاذقية' && shared?.driver === 'سامر' && shared?.location === null, 'ملخص الرحلة بلا موقع قبل الانطلاق');
ok((await anon.rpc('get_shared_trip', { p_token: 'f'.repeat(36) })).data === null, 'رابط غلط ما بيرجع شي');
denied(await driver.c.rpc('update_live_location', { p_trip: tripId, p_lat: 35.5, p_lon: 35.8, p_accuracy: 10, p_heading: 0 }), 'TRACKING_CLOSED', 'التتبع مسكّر قبل الرحلة بساعتين');

console.log('▶ الإلغاء');
must(await rider.c.rpc('cancel_booking', { p_booking: req.id, p_reason: 'تغيّرت خطتي' }), 'الراكب لغى');
ok((await anon.rpc('get_shared_trip', { p_token: token })).data === null, 'الرابط وقف بعد الإلغاء');
ok((await driver.c.rpc('my_driver_trips')).data?.[0]?.seats_available === 3, 'المقاعد رجعت');

console.log('▶ دوال السيرفر (Edge Functions)');
const fn = (name, body, headers = {}) => fetch(`${API_URL}/functions/v1/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
const noteId = (await service.from('notifications').select('id').limit(1).single()).data?.id;
ok((await fn('push', { notification_id: noteId })).status === 401, 'push بلا كلمة السر مرفوض');
const pushRes = await fn('push', { notification_id: noteId }, { 'x-push-secret': process.env.PUSH_SECRET || 'test-push-secret' });
ok(pushRes.status === 200, `push بكلمة السر بيشتغل (${pushRes.status})`);
must(await stranger.c.rpc('request_account_deletion'), 'طلب حذف حساب');
const tok = async (u) => (await u.c.auth.getSession()).data.session.access_token;
ok((await fn('admin-delete-user', { user_id: stranger.id }, { Authorization: `Bearer ${await tok(rider)}` })).status === 403, 'غير المدير ما بيقدر يحذف');
const del = await fn('admin-delete-user', { user_id: stranger.id }, { Authorization: `Bearer ${await tok(admin)}` });
ok(del.status === 200, `المدير حذف الحساب (${del.status})`);
ok((await service.from('profiles').select('id').eq('id', stranger.id)).data?.length === 0, 'الملف انحذف مع المستخدم');
ok((await fn('admin-delete-user', { user_id: rider.id }, { Authorization: `Bearer ${await tok(admin)}` })).status === 409, 'ما بينحذف حساب ما طلب الحذف');

console.log(fails ? `✗ ${fails} فشل` : '✓ الاختبار الشامل نجح');
process.exit(fails ? 1 : 0);
