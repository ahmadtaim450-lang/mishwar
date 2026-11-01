import 'package:flutter_test/flutter_test.dart';
import 'package:mishwar/core/errors.dart';
import 'package:mishwar/data/demo_backend.dart';
import 'package:mishwar/data/mock.dart';
import 'package:mishwar/data/store.dart';

Matcher code(String c) => throwsA(isA<AppException>().having((e) => e.code, 'code', c));

void main() {
  late DemoBackend b;
  setUp(() => b = DemoBackend(delay: Duration.zero));
  tearDown(() => b.dispose());

  test('الدخول برمز من 6 أرقام بس', () async {
    await expectLater(() => b.verifyOtp('+963912345678', '12'), code('OTP_INVALID'));
    await b.verifyOtp('+963912345678', '123456');
    expect(b.signedIn, isTrue);
    expect((await b.loadProfile())!.complete, isFalse);
    await expectLater(() => b.completeProfile('ا', false), code('INVALID_NAME'));
    await b.completeProfile('سامي الراكب', false);
    expect((await b.loadProfile())!.complete, isTrue);
    await expectLater(() => b.completeProfile('سامي الراكب', true), code('GENDER_LOCKED'));
  });

  test('قواعد الحجز: الجنس والمقاعد والتكرار', () async {
    await b.verifyOtp('+963912345678', '123456');
    await b.completeProfile('سامي الراكب', false);
    final found = await b.searchTrips('حمص', 'حلب', 1, 1);
    expect(found, isNotEmpty);
    expect(found.any((t) => t.kind == RideKind.women), isFalse, reason: 'الرجال ما بيشوفوا الرحلات النسائية');

    final women = tripsFor('حمص', 'حلب', day: 1).firstWhere((t) => t.kind == RideKind.women);
    await expectLater(() => b.requestBooking(women, 1), code('GENDER_RESTRICTED'));

    final men = found.firstWhere((t) => t.kind == RideKind.men);
    await expectLater(() => b.requestBooking(men, men.seatsLeft + 1), code('NOT_ENOUGH_SEATS'));
    final booking = await b.requestBooking(men, 1, message: 'مرحبا');
    expect(booking.active, isTrue);
    await expectLater(() => b.requestBooking(men, 1), code('ALREADY_BOOKED'));
    if (men.instant) expect(booking.pin, matches(RegExp(r'^\d{4}$')));

    await b.cancelBooking(booking, 'تغيّرت خطتي');
    expect(booking.status, BStatus.cancelled);
    await expectLater(() => b.cancelBooking(booking, ''), code('INVALID_STATE'));
  });

  test('الرحلات العائلية بدها حجز عائلي', () async {
    await b.verifyOtp('+963912345678', '123456');
    await b.completeProfile('سامي الراكب', false);
    final fam = tripsFor('حمص', 'حلب', day: 1).where((t) => t.kind == RideKind.family && t.seatsLeft >= 2);
    if (fam.isEmpty) return;
    await expectLater(() => b.requestBooking(fam.first, 2), code('FAMILY_ONLY'));
    expect((await b.requestBooking(fam.first, 2, family: true)).family, isTrue);
  });

  test('النشر بس للسائق الموثّق، وطلب الانضمام بيمشي بمراحلو', () async {
    await b.verifyOtp('+963912345678', '123456');
    await b.completeProfile('سامر السائق', false);
    final draft = tripsFor('اللاذقية', 'حمص', day: 2).first;
    await expectLater(() => b.publishTrip(draft), code('NOT_APPROVED_DRIVER'));

    final a = DriverApp()
      ..city = 'اللاذقية'
      ..car = 'كيا ريو'
      ..year = '2015'
      ..color = 'فضي'
      ..plate = 'اللاذقية 123456'
      ..slot = '10:00';
    var last = 0.0;
    await b.submitApplication(a, (p) => last = p);
    expect((await b.application()).$1, DStatus.reviewing);
    await expectLater(() => b.submitApplication(a, (_) {}), code('APPLICATION_ACTIVE'));
    expect(last, anyOf(0.0, 1.0));
    await b.cancelApplication();
    expect((await b.application()).$1, DStatus.none);
  });

  test('الرسائل: فاضية مرفوضة وطويلة مرفوضة', () async {
    await expectLater(() => b.sendMessage('x', ''), code('INVALID_INPUT'));
    await expectLater(() => b.sendMessage('x', 'ا' * 1001), code('INVALID_INPUT'));
    await b.sendMessage('x', 'مرحبا');
    final msgs = await b.messages('x').first;
    expect(msgs.single.mine, isTrue);
  });

  test('Store بيحوّل الأخطاء لرسائل عربية', () async {
    await Store.i.start(DemoBackend(delay: Duration.zero));
    await expectLater(() => Store.i.sendOtp('123'), code('INVALID_PHONE'));
    await Store.i.sendOtp('0912345678');
    expect(await Store.i.verifyOtp('0912345678', '123456'), isFalse);
    await Store.i.completeProfile('إيهاب أحمد', false);
    expect(Store.i.name, 'إيهاب');
    await Store.i.refreshAll();
    expect(Store.i.next, isNotNull, reason: 'حجز المثال');
    final t = (await Store.i.searchTrips('طرطوس', 'حلب', 1, 1)).firstWhere((t) => t.kind == RideKind.men);
    final booking = await Store.i.book(t, 1);
    expect(Store.i.bookingOf(t)?.id, booking.id);
  });
}
