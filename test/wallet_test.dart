// محفظة السائق بالوضع التجريبي: نفس قواعد السيرفر (العمولة، الحجب، الاسترجاع، الشحن).
import 'package:flutter_test/flutter_test.dart';
import 'package:mishwar/core/errors.dart';
import 'package:mishwar/data/demo_backend.dart';
import 'package:mishwar/data/mock.dart';
import 'package:mishwar/data/store.dart';
import 'package:mishwar/data/wallet.dart';

Matcher code(String c) => throwsA(isA<AppException>().having((e) => e.code, 'code', c));
Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

Future<DemoBackend> approvedDriver() async {
  final b = DemoBackend(delay: Duration.zero);
  await b.verifyOtp('+963912345678', '123456');
  await b.completeProfile('سامر السائق', false);
  final a = DriverApp()
    ..city = 'اللاذقية'
    ..car = 'كيا ريو'
    ..year = '2015'
    ..color = 'فضي'
    ..plate = 'اللاذقية 123456'
    ..slot = '10:00';
  await b.submitApplication(a, (_) {});
  await tick(); // المقابلة
  b.approveAfterInterview();
  await tick();
  return b;
}

void main() {
  test('غير السائق ما إلو محفظة', () async {
    final b = DemoBackend(delay: Duration.zero);
    await b.verifyOtp('+963912345678', '123456');
    await expectLater(() => b.myWallet(), code('NOT_APPROVED_DRIVER'));
    await expectLater(() => b.requestTopup(50000, TopupMethod.shamCash, 'X-123'), code('NOT_APPROVED_DRIVER'));
  });

  test('العمولة بتنخصم لحظة القبول، وبترجع إذا الرحلة انلغت', () async {
    final b = await approvedDriver();
    expect((await b.application()).$1, DStatus.approved);
    var w = await b.myWallet();
    expect(w.balance, 50000, reason: 'رصيد تجريبي');
    expect(w.canAccept, isTrue);

    final t = await b.publishTrip(tripsFor('اللاذقية', 'دمشق').first);
    await tick();
    final ride = (await b.myRides()).firstWhere((r) => r.t.id == t.id);
    expect(ride.reqs, isNotEmpty);
    final q = ride.reqs.first;
    await b.respond(q, true);
    w = await b.myWallet();
    final fee = w.commissionFor(t.price, q.seats);
    expect(w.balance, 50000 - fee);
    expect(w.entries.first.kind, 'commission');
    expect(w.monthCommission, fee);

    await b.cancelTrip(t);
    w = await b.myWallet();
    expect(w.balance, 50000);
    expect(w.entries.first.kind, 'refund');
    expect(w.monthCommission, 0);
  });

  test('الرصيد ما بيكفي = ما بيقدر يقبل', () async {
    final b = await approvedDriver();
    final expensive = Trip(
      id: 'x', from: 'حلب', fromSpot: 'الكراج', to: 'دمشق', toSpot: 'البرامكة', dep: '08:00', arr: '13:00', duration: '5 س',
      price: 2000000, seatsLeft: 4, seatsTotal: 4, driver: const Person('سامر', 'س'), car: 'كيا', day: 2,
    );
    final t = await b.publishTrip(expensive);
    await tick();
    final q = (await b.myRides()).firstWhere((r) => r.t.id == t.id).reqs.first;
    await expectLater(() => b.respond(q, true), code('WALLET_LOW'));
    expect(q.state, 0, reason: 'الطلب بيضل معلّق');
    expect((await b.myWallet()).balance, 50000, reason: 'ما انخصم شي');
  });

  test('طلب الشحن: التحقق، التكرار، والموافقة', () async {
    final b = await approvedDriver();
    await expectLater(() => b.requestTopup(5000, TopupMethod.shamCash, 'SC-1'), code('INVALID_AMOUNT'));
    await expectLater(() => b.requestTopup(50000, TopupMethod.shamCash, 'x'), code('INVALID_INPUT'));
    await b.requestTopup(100000, TopupMethod.syriatelCash, 'SY-555');
    await expectLater(() => b.requestTopup(100000, TopupMethod.syriatelCash, 'sy-555'), code('DUPLICATE_REFERENCE'));
    await tick(); // "الإدارة" وافقت
    final w = await b.myWallet();
    expect(w.balance, 150000);
    expect(w.requests.single.status, 'approved');
    expect(w.entries.first.kind, 'topup');
  });

  test('حساب العمولة وعدد الحجوزات المتبقية', () {
    const w = Wallet(balance: 20000, canAccept: true);
    expect(w.commissionFor(75000, 2), 12000);
    expect(w.commissionFor(10000, 1), 2000, reason: 'الحد الأدنى');
    expect(w.bookingsLeft(50000), 5);
    expect(const Wallet(balance: -100, canAccept: false).bookingsLeft(50000), 0);
    expect(TopupMethodX.parse('mtn_cash'), TopupMethod.mtnCash);
    expect(methodLabel('agent'), 'وكيل معتمد');
  });

  test('Store: قبول برصيد ناقص بيرجع رمز WALLET_LOW واضح', () async {
    final b = await approvedDriver();
    await Store.i.start(b);
    final w = await Store.i.refreshWallet();
    expect(Store.i.wallet, w);
    expect(AppException.messages['WALLET_LOW'], contains('اشحن'));
  });
}
