// اختبار تكامل: SupabaseBackend (نفس الكود اللي بيستعملو التطبيق) ضد Supabase حقيقي.
// بيشتغل بس إذا انمرقت المفاتيح:
//   flutter test test/integration --dart-define=SUPABASE_TEST_URL=... --dart-define=SUPABASE_TEST_ANON=... --dart-define=SUPABASE_TEST_SERVICE=...
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishwar/core/errors.dart';
import 'package:mishwar/data/mock.dart';
import 'package:mishwar/data/store.dart';
import 'package:mishwar/data/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const url = String.fromEnvironment('SUPABASE_TEST_URL');
const anonKey = String.fromEnvironment('SUPABASE_TEST_ANON');
const serviceKey = String.fromEnvironment('SUPABASE_TEST_SERVICE');
final skip = url.isEmpty ? 'ما في Supabase للاختبار' : null;

SupabaseClient client(String key) => SupabaseClient(url, key, authOptions: const AuthClientOptions(autoRefreshToken: false));

Future<(SupabaseBackend, SupabaseClient, String)> user(SupabaseClient service, String email, {String? role}) async {
  final created = await service.auth.admin.createUser(AdminUserAttributes(email: email, password: 'Test-pass-123!', emailConfirm: true));
  final id = created.user!.id;
  if (role != null) await service.from('profiles').update({'role': role}).eq('id', id);
  final c = client(anonKey);
  await c.auth.signInWithPassword(email: email, password: 'Test-pass-123!');
  return (SupabaseBackend(client: c), c, id);
}

void main() {
  test('المسار الكامل عبر SupabaseBackend', () async {
    final service = client(serviceKey);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final (driver, _, driverId) = await user(service, 'fd$stamp@mishwar.test');
    final (rider, _, _) = await user(service, 'fr$stamp@mishwar.test');
    final (_, adminC, _) = await user(service, 'fa$stamp@mishwar.test', role: 'admin');

    // الملف الشخصي
    expect((await rider.loadProfile())!.complete, isFalse);
    await rider.completeProfile('رامي الراكب', false, music: 'no_music');
    await driver.completeProfile('سامر السائق', false);
    final rp = await rider.loadProfile();
    expect(rp!.name, 'رامي الراكب');
    expect(rp.female, isFalse);
    expect(rp.music, 'no_music');
    await rider.updateProfile(prefs: {'talk': 'بحب الهدوء'});
    expect((await rider.loadProfile())!.prefs['talk'], 'بحب الهدوء');

    // الانضمام كسائق مع رفع الأوراق
    final jpeg = base64Decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==');
    final app = DriverApp()
      ..city = 'اللاذقية'
      ..car = 'كيا ريو'
      ..year = '2015'
      ..color = 'فضي'
      ..plate = 'LAT ${stamp % 1000000}'
      ..day = 2
      ..slot = '10:00';
    for (final k in ['selfie', 'id_front', 'id_back', 'license', 'record', 'car_front', 'car_side', 'car_inside', 'mechanic']) {
      app.docs[k] = jpeg;
    }
    final progress = <double>[];
    await driver.submitApplication(app, progress.add);
    expect(progress.last, 1.0);
    final (status, fetched) = await driver.application();
    expect(status, DStatus.reviewing);
    expect(fetched!.city, 'اللاذقية');
    expect(fetched.slot, '10:00');
    expect(fetched.day, 2);
    await expectLater(() => rider.publishTrip(tripsFor('اللاذقية', 'دمشق').first), throwsA(predicate((e) => AppException.from(e!).code == 'VEHICLE_NOT_VERIFIED' || AppException.from(e).code == 'NOT_APPROVED_DRIVER')));

    // الإدارة بتوافق
    final iso = fetched.interviewAt.toIso8601String();
    await adminC.rpc('admin_review_application', params: {'p_application': fetched.id, 'p_status': 'interview', 'p_note': null, 'p_interview_at': iso, 'p_place': 'نقطة مشوار'});
    await adminC.rpc('admin_review_application', params: {'p_application': fetched.id, 'p_status': 'approved', 'p_note': null, 'p_interview_at': null, 'p_place': null});
    final dp = await driver.loadProfile();
    expect(dp!.driverStatus, DStatus.approved);
    expect(dp.car, 'كيا ريو · فضي');
    expect(dp.vehicleId, isNotNull);

    // الصورة الشخصية بتظهر للركاب
    await driver.uploadAvatar(jpeg);
    final withPhoto = await driver.loadProfile();
    expect(withPhoto!.photo, contains('/storage/v1/object/public/avatars/'));

    // النشر
    final me = Person('سامر السائق', 'س', id: driverId);
    final draft = Trip(id: 'draft', from: 'اللاذقية', fromSpot: 'الكورنيش', to: 'دمشق', toSpot: 'البرامكة', dep: '09:30', arr: '13:30', duration: '4 س',
        price: 75000, seatsLeft: 3, seatsTotal: 3, driver: me, car: '', kind: RideKind.men, stops: const ['طرطوس', 'حمص'], day: 2);
    final published = await driver.publishTrip(draft, prefs: const ['ممنوع التدخين'], note: 'أهلا وسهلا');
    expect(published.id, isNot('draft'));
    expect(published.plate, app.plate.toUpperCase());

    // البحث والإحصائيات
    final found = await rider.searchTrips('اللاذقية', 'دمشق', 2, 1);
    final t = found.firstWhere((x) => x.id == published.id);
    expect(t.from, 'اللاذقية');
    expect(t.to, 'دمشق');
    expect(t.dep, '09:30');
    expect(t.arr, '13:30');
    expect(t.day, 2);
    expect(t.stops, ['طرطوس', 'حمص']);
    expect(t.driver.name, 'سامر السائق');
    expect(t.driver.photo, withPhoto.photo, reason: 'صورة السائق بالبحث');
    expect(t.seatsLeft, 3);
    expect(t.plate, isEmpty, reason: 'البحث ما بيكشف رقم السيارة');
    expect((await rider.destinationStats('اللاذقية', 2))['دمشق']?.$1, greaterThanOrEqualTo(1));

    // جزء من الطريق: طرطوس ← حمص ضمن نفس الرحلة
    final seg = (await rider.searchTrips('طرطوس', 'حمص', 2, 1)).firstWhere((x) => x.id == published.id);
    expect(seg.isSegment, isTrue);
    expect(seg.fullFrom, 'اللاذقية');
    expect(seg.price, lessThan(75000));
    expect(seg.dep.compareTo('09:30'), greaterThan(0), reason: 'بيوصل لطرطوس بعد الانطلاق');

    // الحجز والموافقة
    final b = await rider.requestBooking(t, 2, message: 'معي شنتاية');
    expect(b.status, BStatus.pending);
    expect(b.pin, isNull);
    expect(b.t.from, 'اللاذقية');
    final rides = await driver.myRides();
    final ride = rides.firstWhere((r) => r.t.id == t.id);
    expect(ride.reqs.single.seats, 2);
    expect(ride.reqs.single.note, 'معي شنتاية');
    await driver.respond(ride.reqs.single, true);
    final d = await rider.bookingDetails(b);
    expect(d.status, BStatus.confirmed);
    expect(d.pin, matches(RegExp(r'^\d{4}$')));
    expect(d.plate, app.plate.toUpperCase());
    expect((await rider.myBookings()).map((x) => x.id), contains(b.id));

    // ملف السائق العام والرسائل والإشعارات
    final pub = await rider.driverPublic(me);
    expect(pub.verified, isTrue);
    await rider.sendMessage(b.id, 'وين بالزبط؟');
    final notes = await rider.notifications();
    expect(notes.any((n) => n.kind == 'booking.confirmed'), isTrue);
    await rider.markNotificationsRead();
    expect((await rider.notifications()).every((n) => n.read), isTrue);

    // رابط الأهل
    final link = await rider.createShareLink(d);
    expect(link, contains('?t='));
    final token = link.split('?t=').last;
    final shared = await client(anonKey).rpc('get_shared_trip', params: {'p_token': token});
    expect((shared as Map)['from'], 'اللاذقية');

    // الأخطاء بتوصل كرموز مفهومة
    await expectLater(() => rider.requestBooking(t, 1), throwsA(predicate((e) => AppException.from(e!).code == 'ALREADY_BOOKED')));

    // السائق ما بيقدر يقيّم الراكب قبل ما تخلص الرحلة
    await expectLater(() => driver.reviewRider(ride.reqs.single, 5, const ['محترم'], null), throwsA(predicate((e) => AppException.from(e!).code == 'INVALID_STATE')));

    // الإلغاء
    await rider.cancelBooking(d, 'تغيّرت خطتي');
    expect((await rider.myBookings()).where((x) => x.id == b.id), isEmpty);
    expect((await driver.myRides()).firstWhere((r) => r.t.id == t.id).t.seatsLeft, 3);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
