import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../core/errors.dart';
import '../map/geo_math.dart';
import '../map/models.dart';
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
  Future<void> uploadAvatar(Uint8List jpeg) async {
    await _wait();
    if (jpeg.length > 2 * 1024 * 1024) throw AppException('UPLOAD_FAILED', AppException.messages['UPLOAD_FAILED']!);
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
  Future<void> reviewRider(RideReq q, int stars, List<String> tags, String? comment) async {
    await _wait();
    if (q.reviewed) throw AppException('ALREADY_REVIEWED', AppException.messages['ALREADY_REVIEWED']!);
    if (stars < 1 || stars > 5) throw AppException('INVALID_INPUT', AppException.messages['INVALID_INPUT']!);
    q.reviewed = true;
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
  Future<void> registerDevice(String token, String platform) async {}

  @override
  Future<void> unregisterDevice(String token) async {}

  @override
  Future<List<AppNotification>> notifications() async => List.of(_notes);

  @override
  Future<void> markNotificationsRead() async {
    for (var i = 0; i < _notes.length; i++) {
      final n = _notes[i];
      _notes[i] = AppNotification(n.id, n.kind, n.title, n.body, n.at, read: true);
    }
  }

  // ── الخرائط (تجريبي: نفس قواعد السيرفر، بيانات من مولّد الرحلات) ─────
  final _places = <SavedPlace>[];
  final _tripPts = <String, (LatLng?, LatLng?)>{};
  static const _mapDests = ['دمشق', 'حلب', 'حمص', 'اللاذقية', 'طرطوس', 'حماة', 'درعا', 'جبلة'];

  static DateTime _damascusNow() => DateTime.now().toUtc().add(const Duration(hours: 3));
  static DateTime _depUtc(int day, String hm) {
    final p = hm.split(':');
    final d = _damascusNow().add(Duration(days: day));
    return DateTime.utc(d.year, d.month, d.day, int.parse(p[0]), int.parse(p[1])).subtract(const Duration(hours: 3));
  }

  List<MapTrip> _mapTripsWhere(bool Function(LatLng p) inArea, MapFilter f, LatLng? me) {
    final now = DateTime.now().toUtc();
    final out = <MapTrip>[];
    for (final day in f.day == null ? const [0, 1, 2] : [f.day!]) {
      for (final board in geo.keys) {
        final g = geo[board]!;
        final bp = LatLng(g.$1, g.$2);
        if (!inArea(bp)) continue;
        for (final to in f.to == null ? _mapDests : [f.to!]) {
          if (to == board) continue;
          for (final t in tripsFor(board, to, day: day)) {
            if (!_allowed.contains(t.kind) || (f.kinds.isNotEmpty && !f.kinds.contains(t.kind))) continue;
            if (t.seatsLeft < f.seats || (f.maxPrice != null && t.price > f.maxPrice!) || (f.instantOnly && !t.instant)) continue;
            final dep = _depUtc(day, t.dep);
            if (!dep.isAfter(now)) continue;
            final pick = _tripPts[t.id]?.$1;
            final pt = pick ?? bp;
            out.add(MapTrip(
              tripId: t.id,
              board: board,
              to: to,
              point: pt,
              exact: pick != null,
              departure: dep,
              arrival: dep.add(Duration(minutes: durationMin(board, to))),
              price: t.price,
              seats: t.seatsLeft,
              kind: t.kind,
              instant: t.instant,
              driver: t.driver.name,
              rating: t.driver.rating,
              distanceKm: me == null ? null : double.parse(kmBetween(me, pt).toStringAsFixed(1)),
            ));
          }
        }
      }
    }
    out.sort((a, b) => me == null ? a.departure.compareTo(b.departure) : (a.distanceKm!.compareTo(b.distanceKm!) != 0 ? a.distanceKm!.compareTo(b.distanceKm!) : a.departure.compareTo(b.departure)));
    return out.take(300).toList();
  }

  void _checkFilter(MapFilter f) {
    if (f.seats < 1 || f.seats > 7) throw AppException('INVALID_INPUT', AppException.messages['INVALID_INPUT']!);
  }

  @override
  Future<List<MapTrip>> mapTrips(GeoBounds area, MapFilter f, {LatLng? me}) async {
    await _wait();
    _checkFilter(f);
    if (area.south > area.north || area.west > area.east) throw AppException('INVALID_INPUT', AppException.messages['INVALID_INPUT']!);
    return _mapTripsWhere(area.contains, f, me);
  }

  @override
  Future<List<MapTrip>> tripsNear(LatLng at, double radiusKm, MapFilter f) async {
    await _wait();
    _checkFilter(f);
    if (radiusKm <= 0 || radiusKm > 500) throw AppException('INVALID_INPUT', AppException.messages['INVALID_INPUT']!);
    return _mapTripsWhere((p) => kmBetween(at, p) <= radiusKm, f, at).take(100).toList();
  }

  @override
  Future<List<GeoPlace>> searchPlaces(String q, {LatLng? near}) async {
    if (q.length > 80) throw AppException('INVALID_INPUT', AppException.messages['INVALID_INPUT']!);
    final n = norm(q.toLowerCase());
    final saved = _places.where((p) => n.isEmpty || norm(p.label).contains(n)).map((p) => p.asPlace);
    final found = (n.isEmpty ? cities : searchCities(q)).where((c) => geo.containsKey(c.name)).map((c) {
      final g = geo[c.name]!;
      final pt = LatLng(g.$1, g.$2);
      return GeoPlace(name: c.name, label: c.sub, point: pt, kind: PlaceKind.city, city: c.name, distanceKm: near == null ? null : kmBetween(near, pt));
    }).toList();
    if (near != null && n.isEmpty) found.sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
    return [...saved, ...found].take(12).toList();
  }

  /// الوضع التجريبي ما بيتصل بمزود عناوين (المفاتيح بالسيرفر بس).
  @override
  Future<List<GeoPlace>> geocodeSuggest(String q, {LatLng? near}) async => const [];

  @override
  Future<GeoPlace?> reverseGeocode(LatLng at) async {
    final c = await nearestCity(at);
    if (c == null) return null;
    return GeoPlace(name: c.$2 < 2 ? c.$1 : 'قرب ${c.$1}', label: '${fmtKm(c.$2)} عن مركز ${c.$1}', point: at, kind: PlaceKind.address, city: c.$1);
  }

  /// بالتجربة: طريق حقيقي من OSRM العام (للتجربة بس)، وإذا ما زبط مسار تقريبي.
  @override
  Future<List<RouteOption>> route(List<LatLng> points, {bool alternatives = true}) async {
    if (points.length < 2 || points.length > 6) throw AppException('INVALID_INPUT', AppException.messages['INVALID_INPUT']!);
    if (delay == Duration.zero) return [approximateRoute(points)]; // الاختبارات: بلا شبكة
    try {
      final coords = points.map((p) => '${p.longitude},${p.latitude}').join(';');
      final res = await http
          .get(Uri.parse('https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson&alternatives=${alternatives && points.length == 2}'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [approximateRoute(points)];
      final body = utf8.decode(res.bodyBytes);
      final j = jsonDecode(body) as Map<String, dynamic>;
      final routes = [
        for (final r in (j['routes'] as List).cast<Map>())
          RouteOption(
            line: [for (final c in (r['geometry']['coordinates'] as List)) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())],
            meters: (r['distance'] as num).round(),
            seconds: (r['duration'] as num).round(),
          ),
      ];
      return routes.isEmpty ? [approximateRoute(points)] : routes.take(3).toList();
    } catch (_) {
      return [approximateRoute(points)];
    }
  }

  @override
  Future<(String, double)?> nearestCity(LatLng at) async {
    String? best;
    var bd = double.infinity;
    for (final e in geo.entries) {
      final d = kmBetween(at, LatLng(e.value.$1, e.value.$2));
      if (d < bd) {
        bd = d;
        best = e.key;
      }
    }
    return best == null ? null : (best, double.parse(bd.toStringAsFixed(1)));
  }

  @override
  Future<List<CityActivity>> cityActivity() async {
    final counts = <String, int>{};
    for (final t in _mapTripsWhere((_) => true, const MapFilter(), null)) {
      counts[t.board] = (counts[t.board] ?? 0) + 1;
    }
    return [
      for (final e in counts.entries) CityActivity(e.key, LatLng(geo[e.key]!.$1, geo[e.key]!.$2), e.value),
    ]..sort((a, b) => b.departures.compareTo(a.departures));
  }

  @override
  Future<List<GeoPlace>> cityPlaces(String city) async => const [];

  @override
  Future<List<SavedPlace>> myPlaces() async => List.of(_places);

  @override
  Future<SavedPlace> savePlace(String label, LatLng at, {String kind = 'other', String? address}) async {
    await _wait();
    final l = label.trim();
    if (l.isEmpty || l.length > 40 || !{'home', 'work', 'other'}.contains(kind)) throw AppException('INVALID_INPUT', AppException.messages['INVALID_INPUT']!);
    if (!GeoBounds.syria.contains(at)) throw AppException('OUTSIDE_SYRIA', AppException.messages['OUTSIDE_SYRIA']!);
    if (kind != 'other') _places.removeWhere((p) => p.kind == kind);
    _places.removeWhere((p) => p.label == l);
    if (_places.length >= 20) throw AppException('LIMIT_REACHED', AppException.messages['LIMIT_REACHED']!);
    final p = SavedPlace(id: 'p${DateTime.now().microsecondsSinceEpoch}', label: l, kind: kind, point: at, address: address);
    _places.add(p);
    return p;
  }

  @override
  Future<void> deletePlace(String id) async {
    final before = _places.length;
    _places.removeWhere((p) => p.id == id);
    if (_places.length == before) throw AppException('NOT_FOUND', AppException.messages['NOT_FOUND']!);
  }

  @override
  Future<void> setTripPoints(Trip t, {LatLng? pickup, LatLng? dropoff}) async {
    LatLng city(String n) => LatLng(geo[n]!.$1, geo[n]!.$2);
    if (pickup != null && geo.containsKey(t.from) && kmBetween(pickup, city(t.from)) > 25) throw AppException('POINT_TOO_FAR', AppException.messages['POINT_TOO_FAR']!);
    if (dropoff != null && geo.containsKey(t.to) && kmBetween(dropoff, city(t.to)) > 25) throw AppException('POINT_TOO_FAR', AppException.messages['POINT_TOO_FAR']!);
    _tripPts[t.id] = (pickup, dropoff);
  }

  @override
  Future<(LatLng?, LatLng?)> tripPoints(Trip t) async => _tripPts[t.id] ?? (null, null);
}
