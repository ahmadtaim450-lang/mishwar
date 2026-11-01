import 'dart:async';
import 'dart:math' as math;
import '../core/errors.dart';
import 'backend.dart';
import 'mock.dart';
import 'store.dart';

/// الوضع التجريبي: كلشي بالذاكرة، بنفس قواعد السيرفر (الجنس، المقاعد، الحالات).
/// بينستعمل لما ما في مفاتيح Supabase، وبالاختبارات.
class DemoBackend implements Backend {
  /// سرعة المحاكاة (الاختبارات بتخليها صفر).
  final Duration delay;
  DemoBackend({this.delay = const Duration(milliseconds: 450)});

  final _changes = StreamController<void>.broadcast();
  final _rnd = math.Random();
  bool _signed = false;
  UserProfile _me = const UserProfile(id: 'me', name: '');
  DriverApp? _app;
  DStatus _driver = DStatus.none;
  final _bookings = <Booking>[];
  final _rides = <MyRide>[];
  final _notes = <AppNotification>[];
  final _chats = <String, List<ChatMessage>>{};
  final _chatStreams = <String, StreamController<List<ChatMessage>>>{};
  final _timers = <Timer>[];

  @override
  bool get isLive => false;
  @override
  bool get signedIn => _signed;
  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> init() async {}

  Future<void> _wait() => delay == Duration.zero ? Future.value() : Future.delayed(delay);
  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _after(Duration d, void Function() f) => _timers.add(Timer(delay == Duration.zero ? Duration.zero : d, f));

  void _notify(String kind, String title, String body) {
    _notes.insert(0, AppNotification('n${_notes.length + 1}', kind, title, body, DateTime.now()));
    _emit();
  }

  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
  }

  // ── الدخول ─────────────────────────────────────────────────────────
  @override
  Future<void> sendOtp(String phone) async {
    await _wait();
  }

  @override
  Future<void> verifyOtp(String phone, String code) async {
    await _wait();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) throw const AppException('OTP_INVALID', 'الرمز غلط أو انتهت صلاحيتو');
    _signed = true;
    _me = UserProfile(id: 'me', name: _me.name, female: _me.female, phone: phone, driverStatus: _driver);
  }

  @override
  Future<void> signOut() async {
    _signed = false;
  }

  @override
  Future<UserProfile?> loadProfile() async {
    if (!_signed) return null;
    return UserProfile(
      id: 'me',
      name: _me.name,
      female: _me.female,
      phone: _me.phone,
      driverStatus: _driver,
      car: _app == null ? null : '${_app!.car} · ${_app!.color}',
      plate: _app?.plate,
      vehicleId: _app == null ? null : 'veh-me',
      rating: 4.9,
      trips: 12,
      music: _me.music,
      prefs: _prefs,
    );
  }

  @override
  Future<void> completeProfile(String fullName, bool female, {String? music}) async {
    await _wait();
    final n = fullName.trim();
    if (n.length < 3) throw AppException('INVALID_NAME', AppException.messages['INVALID_NAME']!);
    if (_me.female != null && _me.female != female) throw AppException('GENDER_LOCKED', AppException.messages['GENDER_LOCKED']!);
    final first = _me.female == null;
    _me = UserProfile(id: 'me', name: n, female: female, phone: _me.phone, driverStatus: _driver);
    if (first) _seed();
  }

  /// حجوزات مثال لحتى الواجهات ما تكون فاضية بأول تجربة.
  void _seed() {
    final f = _me.female ?? false;
    final up = tripsFor('اللاذقية', 'دمشق', day: 1).firstWhere((t) => f ? t.kind != RideKind.men : t.kind != RideKind.women);
    _bookings.add(Booking(up, 1, id: 'b-seed-1', status: BStatus.confirmed, pin: '4821', plate: up.plate, driverPhone: '+963 9•• ••• •12'));
    final past = tripsFor('جبلة', 'حمص', day: -4).firstWhere((t) => f ? t.kind != RideKind.men : t.kind != RideKind.women);
    _bookings.add(Booking(past, 1, id: 'b-seed-2', status: BStatus.done, pin: '1937', plate: past.plate));
    _chats['b-seed-1'] = [
      ChatMessage('m1', 'مرحبا، حجزت مقعد معك لبكرا', true, DateTime.now().subtract(const Duration(hours: 3))),
      ChatMessage('m2', 'أهلين، تم القبول. الانطلاق بالزبط من ${up.fromSpot}', false, DateTime.now().subtract(const Duration(hours: 2, minutes: 55))),
    ];
    _notes.add(AppNotification('n0', 'booking.confirmed', 'انقبل حجزك', '${up.driver.name} قبل طلبك لرحلة ${up.from} ← ${up.to}', DateTime.now().subtract(const Duration(hours: 3))));
  }

  Map<String, String> _prefs = const {};

  @override
  Future<void> updateProfile({String? name, String? music, Map<String, String>? prefs}) async {
    await _wait();
    if (prefs != null) _prefs = Map.of(prefs);
    _me = UserProfile(id: 'me', name: name ?? _me.name, female: _me.female, phone: _me.phone, driverStatus: _driver, music: music ?? _me.music, prefs: _prefs);
  }

  @override
  Future<void> requestDeletion() async {
    await _wait();
    _bookings.clear();
    _signed = false;
  }

  @override
  Future<DriverPublic> driverPublic(Person p) async {
    await _wait();
    return DriverPublic(p, trips: p.trips, reviewsCount: reviews.length, rating: p.rating, verified: true, since: DateTime(2026, 3), reviews: reviews, histogram: const {5: 3, 4: 1});
  }

  // ── البحث ──────────────────────────────────────────────────────────
  List<RideKind> get _allowed => (_me.female ?? false) ? const [RideKind.women, RideKind.family] : const [RideKind.men, RideKind.family];

  @override
  Future<List<Trip>> searchTrips(String from, String to, int day, int seats) async {
    await _wait();
    if (from == to || seats < 1 || seats > 7) throw AppException('INVALID_INPUT', AppException.messages['INVALID_INPUT']!);
    return tripsFor(from, to, day: day).where((t) => _allowed.contains(t.kind) && t.seatsLeft >= seats).toList();
  }

  @override
  Future<Map<String, (int, int)>> destinationStats(String from, int day) async {
    return {
      for (final c in cityIds.keys)
        if (c != from && geo.containsKey(c)) c: (tripsFor(from, c, day: day).where((t) => _allowed.contains(t.kind)).length, suggestedPrice(from, c)),
    };
  }

  // ── الحجز ──────────────────────────────────────────────────────────
  @override
  Future<Booking> requestBooking(Trip t, int seats, {bool family = false, String? message}) async {
    await _wait();
    final f = _me.female ?? false;
    if (!_me.complete) throw AppException('PROFILE_INCOMPLETE', AppException.messages['PROFILE_INCOMPLETE']!);
    if ((t.kind == RideKind.women && !f) || (t.kind == RideKind.men && f)) throw AppException('GENDER_RESTRICTED', AppException.messages['GENDER_RESTRICTED']!);
    if (t.kind == RideKind.family && !family) throw AppException('FAMILY_ONLY', AppException.messages['FAMILY_ONLY']!);
    if (seats < 1 || seats > t.seatsLeft) throw AppException('NOT_ENOUGH_SEATS', AppException.messages['NOT_ENOUGH_SEATS']!);
    if (_bookings.any((b) => b.t.id == t.id && b.active)) throw AppException('ALREADY_BOOKED', AppException.messages['ALREADY_BOOKED']!);
    final b = Booking(t, seats, id: 'b-${DateTime.now().microsecondsSinceEpoch}', family: family, status: t.instant ? BStatus.confirmed : BStatus.pending);
    if (t.instant) _confirm(b);
    _bookings.insert(0, b);
    if (message != null && message.trim().isNotEmpty) _chats[b.id] = [ChatMessage('m-${b.id}', message.trim(), true, DateTime.now())];
    if (!t.instant) {
      _after(const Duration(seconds: 9), () {
        if (b.status != BStatus.pending) return;
        _confirm(b);
        _notify('booking.confirmed', 'انقبل حجزك', '${t.driver.name} قبل حجزك على رحلة ${t.from} ← ${t.to}');
      });
    }
    return b;
  }

  void _confirm(Booking b) {
    b.status = BStatus.confirmed;
    b.pin = (1000 + _rnd.nextInt(9000)).toString();
    b.plate = b.t.plate;
    b.driverPhone = '+963 9•• ••• •${10 + _rnd.nextInt(89)}';
  }

  @override
  Future<List<Booking>> myBookings() async => List.of(_bookings.where((b) => b.status != BStatus.cancelled && b.status != BStatus.rejected));

  @override
  Future<Booking> bookingDetails(Booking b) async => _bookings.firstWhere((x) => x.id == b.id, orElse: () => b);

  @override
  Future<void> cancelBooking(Booking b, String reason) async {
    await _wait();
    if (!b.active) throw AppException('INVALID_STATE', AppException.messages['INVALID_STATE']!);
    b.status = BStatus.cancelled;
  }

  @override
  Future<void> submitReview(Booking b, int stars, List<String> tags, String? comment) async {
    await _wait();
    if (b.status != BStatus.done) throw AppException('INVALID_STATE', AppException.messages['INVALID_STATE']!);
    if (b.rated) throw AppException('ALREADY_REVIEWED', AppException.messages['ALREADY_REVIEWED']!);
    if (stars < 1 || stars > 5) throw AppException('INVALID_INPUT', AppException.messages['INVALID_INPUT']!);
    b.rated = true;
  }

  @override
  Future<void> report(String targetId, String? tripId, String reason, String? details) async {
    await _wait();
    if (reason.trim().length < 2) throw AppException('INVALID_INPUT', AppException.messages['INVALID_INPUT']!);
  }

  // ── السائق ─────────────────────────────────────────────────────────
  @override
  Future<List<MyRide>> myRides() async => List.of(_rides.where((r) => r.status != 'cancelled'));

  @override
  Future<Trip> publishTrip(Trip d, {List<String> prefs = const [], String? note}) async {
    await _wait();
    if (_driver != DStatus.approved) throw AppException('NOT_APPROVED_DRIVER', AppException.messages['NOT_APPROVED_DRIVER']!);
    if (d.from == d.to) throw AppException('INVALID_ROUTE', AppException.messages['INVALID_ROUTE']!);
    final f = _me.female ?? false;
    if ((d.kind == RideKind.women && !f) || (d.kind == RideKind.men && f)) throw AppException('GENDER_RESTRICTED', AppException.messages['GENDER_RESTRICTED']!);
    if (d.price < 1000 || d.price > 2000000) throw AppException('INVALID_PRICE', AppException.messages['INVALID_PRICE']!);
    final t = Trip(
      id: 'me-${DateTime.now().microsecondsSinceEpoch}', from: d.from, fromSpot: d.fromSpot, to: d.to, toSpot: d.toSpot, dep: d.dep, arr: d.arr,
      duration: d.duration, price: d.price, seatsLeft: d.seatsTotal, seatsTotal: d.seatsTotal, driver: d.driver, car: d.car,
      kind: d.kind, instant: d.instant, stops: d.stops, day: d.day, plate: d.plate,
    );
    final ride = MyRide(t);
    _rides.insert(0, ride);
    final guests = f
        ? [(reem, 'راكبة وحدة · شنتاية صغيرة', 1), (noorDriver, 'مع بنتي · مقعدين', 2)]
        : [(mazen, 'راكب واحد · طالب جامعة', 1), (hussam, 'شنتاية صغيرة', 1)];
    var secs = 7;
    for (final (p, n, s) in guests) {
      _after(Duration(seconds: secs), () {
        if (ride.status != 'scheduled') return;
        ride.reqs.add(RideReq(p, n, seats: s));
        _notify('booking.requested', 'طلب حجز جديد', '${p.name} بدو ${s == 1 ? 'مقعد' : '$s مقاعد'} برحلتك لـ${t.to}');
      });
      secs += 12;
    }
    return t;
  }

  @override
  Future<void> respond(RideReq q, bool accept) async {
    await _wait();
    if (q.state != 0) throw AppException('INVALID_STATE', AppException.messages['INVALID_STATE']!);
    final ride = _rides.firstWhere((r) => r.reqs.contains(q));
    if (accept && ride.booked + q.seats > ride.t.seatsTotal) throw AppException('NOT_ENOUGH_SEATS', AppException.messages['NOT_ENOUGH_SEATS']!);
    q.state = accept ? 1 : 2;
  }

  @override
  Future<void> cancelTrip(Trip t) async {
    await _wait();
    for (final r in _rides) {
      if (r.t.id == t.id) r.status = 'cancelled';
    }
  }

  @override
  Future<void> startTrip(Trip t) async {
    for (final r in _rides) {
      if (r.t.id == t.id) r.status = 'in_progress';
    }
  }

  @override
  Future<void> completeTrip(Trip t) async {
    for (final r in _rides) {
      if (r.t.id == t.id) r.status = 'completed';
    }
  }

  @override
  Future<void> submitApplication(DriverApp a, void Function(double) onProgress) async {
    if (_driver != DStatus.none && _driver != DStatus.rejected) throw AppException('APPLICATION_ACTIVE', AppException.messages['APPLICATION_ACTIVE']!);
    for (var i = 1; i <= a.docs.length; i++) {
      await Future.delayed(delay == Duration.zero ? Duration.zero : const Duration(milliseconds: 120));
      onProgress(i / a.docs.length);
    }
    _app = a..id = 'app-me';
    _driver = DStatus.reviewing;
    _after(const Duration(seconds: 12), () {
      if (_driver != DStatus.reviewing) return;
      _driver = DStatus.interview;
      _notify('application.interview', 'أوراقك تمام!', 'موعد مقابلتك ${dayLabel(a.day)} الساعة ${a.slot}');
    });
  }

  void approveAfterInterview() => _after(const Duration(seconds: 4), () {
        if (_driver != DStatus.interview) return;
        _driver = DStatus.approved;
        _notify('application.approved', 'مبروك! صرت سائق موثّق', 'فيك هلق تنشر رحلتك الأولى');
      });

  @override
  Future<(DStatus, DriverApp?)> application() async => (_driver, _app);

  @override
  Future<void> cancelApplication() async {
    if (_driver != DStatus.reviewing && _driver != DStatus.interview) throw AppException('INVALID_STATE', AppException.messages['INVALID_STATE']!);
    _driver = DStatus.none;
    _app = null;
  }

  // ── التتبع والرسائل والإشعارات ─────────────────────────────────────
  @override
  Future<void> updateLocation(Trip t, double lat, double lon, double? accuracy, double? heading) async {}

  /// بالتجريبي ما في سيرفر للمتابعة المباشرة، فبيرجع فاضي ومنبعت لقطة موقع.
  @override
  Future<String> createShareLink(Booking b) async => '';

  @override
  Stream<List<ChatMessage>> messages(String bookingId) {
    final c = _chatStreams.putIfAbsent(bookingId, () => StreamController<List<ChatMessage>>.broadcast());
    scheduleMicrotask(() => c.add(List.of(_chats[bookingId] ?? const [])));
    return c.stream;
  }

  @override
  Future<void> sendMessage(String bookingId, String body) async {
    if (body.isEmpty || body.length > 1000) throw AppException('INVALID_INPUT', AppException.messages['INVALID_INPUT']!);
    final list = _chats.putIfAbsent(bookingId, () => []);
    list.add(ChatMessage('m${list.length}-${DateTime.now().millisecondsSinceEpoch}', body, true, DateTime.now()));
    _chatStreams[bookingId]?.add(List.of(list));
    if (list.where((m) => !m.mine).length < 3) {
      _after(const Duration(seconds: 2), () {
        list.add(ChatMessage('r${list.length}', 'تمام، وصلت رسالتك', false, DateTime.now()));
        _chatStreams[bookingId]?.add(List.of(list));
      });
    }
  }

  @override
  Future<List<AppNotification>> notifications() async => List.of(_notes);

  @override
  Future<void> markNotificationsRead() async {
    for (var i = 0; i < _notes.length; i++) {
      final n = _notes[i];
      _notes[i] = AppNotification(n.id, n.kind, n.title, n.body, n.at, read: true);
    }
  }
}
