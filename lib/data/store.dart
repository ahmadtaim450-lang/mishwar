// حالة التطبيق: الحجوزات، الرحلات المنشورة، وتوليد رحلات منطقية لكل طريق.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'mock.dart';
import '../core/errors.dart';
import 'backend.dart';
import 'demo_backend.dart';

/// إحداثيات المدن (lat, lon).
const geo = <String, (double, double)>{
  'اللاذقية': (35.5196, 35.7832),
  'جبلة': (35.3610, 35.9256),
  'بانياس': (35.1828, 35.9486),
  'طرطوس': (34.8890, 35.8866),
  'حمص': (34.7324, 36.7137),
  'حماة': (35.1318, 36.7578),
  'حلب': (36.2021, 37.1343),
  'النبك': (34.0237, 36.7280),
  'دمشق': (33.5138, 36.2765),
  'درعا': (32.6189, 36.1021),
  'إدلب': (35.9306, 36.6339),
  'الرقة': (35.9500, 39.0100),
  'دير الزور': (35.3360, 40.1400),
  'الحسكة': (36.5000, 40.7500),
  'القامشلي': (37.0500, 41.2200),
  'السويداء': (32.7090, 36.5660),
  'تدمر': (34.5600, 38.2800),
  'السلمية': (35.0110, 37.0530),
  'صافيتا': (34.8200, 36.1170),
  'القرداحة': (35.4560, 36.0560),
  'منبج': (36.5280, 37.9550),
  'القنيطرة': (33.1260, 35.8240),
};

/// توحيد الكتابة العربية للبحث: أ/إ/آ=ا، ة=ه، ى=ي، بلا تشكيل وبلا "ال" بأول الكلمة.
String norm(String s) => s
    .trim()
    .replaceAll(RegExp('[\u064B-\u0652\u0640]'), '')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAllMapped(RegExp(r'(^|\s)ال'), (m) => m[1]!);

/// المدن اللي بتطابق البحث، الأقرب أول.
List<City> searchCities(String q, {String? exclude}) {
  final list = cities.where((c) => c.name != exclude).toList();
  final n = norm(q);
  if (n.isEmpty) return list;
  int score(City c) {
    final name = norm(c.name), sub = norm(c.sub);
    if (name == n) return 0;
    if (name.startsWith(n)) return 1;
    if (name.contains(n)) return 2;
    if (sub.contains(n)) return 3;
    return 9;
  }
  final r = list.where((c) => score(c) < 9).toList()..sort((a, b) => score(a).compareTo(score(b)));
  return r;
}

City? cityNamed(String s) {
  final n = norm(s);
  for (final c in cities) {
    if (norm(c.name) == n) return c;
  }
  return null;
}

double _hav(String a, String b) {
  final p = geo[a]!, q = geo[b]!;
  const r = 6371.0;
  final dLat = (q.$1 - p.$1) * math.pi / 180, dLon = (q.$2 - p.$2) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(p.$1 * math.pi / 180) * math.cos(q.$1 * math.pi / 180) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// مسافة الطريق التقريبية بالكيلومتر.
int roadKm(String a, String b) => geo.containsKey(a) && geo.containsKey(b) ? (_hav(a, b) * 1.4).round() : 200;

/// المدن الرئيسية الواقعة على الطريق بين مدينتين (لحد وقفتين).
List<String> stopsBetween(String a, String b) {
  if (!geo.containsKey(a) || !geo.containsKey(b)) return const [];
  final d = _hav(a, b);
  // بالترتيب حسب الأهمية: الكراجات الكبيرة أولى بالوقفة
  const majors = ['حمص', 'طرطوس', 'حماة', 'جبلة'];
  final c = majors.where((m) => m != a && m != b && _hav(a, m) + _hav(m, b) <= d * 1.2).take(2).toList()
    ..sort((x, y) => _hav(a, x).compareTo(_hav(a, y)));
  return c;
}

int suggestedPrice(String a, String b) => math.max(15000, (roadKm(a, b) * 240 / 5000).round() * 5000);
int durationMin(String a, String b) => (roadKm(a, b) / 75 * 60).round() + stopsBetween(a, b).length * 10;

String fmtDur(int m) {
  final h = m ~/ 60, r = m % 60;
  if (h == 0) return '$r د';
  final hs = h == 1 ? 'ساعة' : h == 2 ? 'ساعتين' : '$h س';
  return r == 0 ? hs : '$hs $r د';
}

String _hm(int min) => '${(min ~/ 60 % 24).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

const _weekdays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const _months = ['كانون 2', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين 1', 'تشرين 2', 'كانون 1'];

/// "اليوم"، "بكرا"، أو "الخميس 5 تشرين 2".
String dayLabel(int day) {
  if (day == 0) return 'اليوم';
  if (day == 1) return 'بكرا';
  if (day == -1) return 'مبارح';
  final d = DateTime.now().add(Duration(days: day));
  return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

/// صيغ العدد بالعربي.
String seatsLabel(int n) => n == 1 ? 'مقعد واحد' : n == 2 ? 'مقعدين' : '$n مقاعد';
String paxLabel(int n) => n == 1 ? 'راكب واحد' : n == 2 ? 'راكبين' : '$n ركاب';
String tripsLabel(int n) => n == 0 ? 'ما في رحلات' : n == 1 ? 'رحلة وحدة' : n == 2 ? 'رحلتين' : n <= 10 ? '$n رحلات' : '$n رحلة';

const _men = [
  samer,
  abuSami,
  hussam,
  mazen,
  Person('خالد', 'خ', rating: 4.7, trips: 23),
  Person('أبو محمد', 'أ', rating: 4.9, trips: 61),
];
const _women = [reem, noorDriver];
const _cars = ['كيا ريو · فضي', 'هيونداي أكسنت · أبيض', 'شيري تيغو · رمادي', 'تويوتا كورولا · أسود', 'كيا سيراتو · أزرق', 'هيونداي إلنترا · أبيض'];
const _hubs = {'دمشق', 'حلب', 'حمص', 'اللاذقية'};

final _cache = <String, List<Trip>>{};

/// رحلات منطقية وثابتة لكل طريق ويوم (نفس الطريق بيعطي نفس الرحلات).
List<Trip> tripsFor(String from, String to, {int day = 1}) {
  if (from == to) return const [];
  final key = '$from>$to>$day';
  return _cache[key] ??= () {
    final seed = key.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);
    final r = math.Random(seed);
    final bothHubs = _hubs.contains(from) && _hubs.contains(to);
    final count = (bothHubs ? 4 : 2) + r.nextInt(3) - (day > 3 ? 1 : 0);
    final dur = durationMin(from, to);
    final base = suggestedPrice(from, to);
    final stops = stopsBetween(from, to);
    final fromSpots = cities.firstWhere((c) => c.name == from, orElse: () => City(from, 'المركز', '')).sub.split(' · ');
    final toSpots = cities.firstWhere((c) => c.name == to, orElse: () => City(to, 'المركز', '')).sub.split(' · ');
    final starts = <int>{};
    while (starts.length < count) {
      starts.add((6 + r.nextInt(13)) * 60 + [0, 15, 30, 45][r.nextInt(4)]);
    }
    final sorted = starts.toList()..sort();
    final list = <Trip>[];
    for (var i = 0; i < count; i++) {
      final kind = (i == 1 && count >= 3) ? RideKind.women : (i == count - 1 && count >= 4 ? RideKind.family : RideKind.men);
      final driver = kind == RideKind.women ? _women[r.nextInt(_women.length)] : (i == 0 ? samer : _men[1 + r.nextInt(_men.length - 1)]);
      final total = 3 + r.nextInt(2);
      final left = 1 + r.nextInt(total);
      list.add(Trip(
        id: '$key>$i',
        from: from,
        fromSpot: fromSpots[r.nextInt(fromSpots.length)],
        to: to,
        toSpot: toSpots[r.nextInt(toSpots.length)],
        dep: _hm(sorted[i]),
        arr: _hm(sorted[i] + dur),
        duration: fmtDur(dur),
        price: math.max(15000, base + (r.nextInt(3) - 1) * 5000),
        seatsLeft: left,
        seatsTotal: total,
        driver: driver,
        car: _cars[r.nextInt(_cars.length)],
        kind: kind,
        instant: r.nextInt(3) == 0,
        stops: stops,
        day: day,
        plate: '${const ['دمشق', 'اللاذقية', 'حمص', 'طرطوس', 'حلب'][r.nextInt(5)]} ${100000 + r.nextInt(899999)}',
      ));
    }
    return list;
  }();
}

/// معرّفات المدن بقاعدة البيانات.
const cityIds = <String, String>{
  'دمشق': 'damascus', 'حلب': 'aleppo', 'اللاذقية': 'latakia', 'حمص': 'homs', 'طرطوس': 'tartus', 'حماة': 'hama',
  'جبلة': 'jableh', 'درعا': 'daraa', 'بانياس': 'banias', 'إدلب': 'idlib', 'الرقة': 'raqqa', 'دير الزور': 'deir_ez_zor',
  'الحسكة': 'hasakah', 'القامشلي': 'qamishli', 'السويداء': 'sweida', 'تدمر': 'palmyra', 'السلمية': 'salamiyah',
  'صافيتا': 'safita', 'القرداحة': 'qardaha', 'منبج': 'manbij', 'القنيطرة': 'quneitra', 'النبك': 'nabk',
};
final cityNames = {for (final e in cityIds.entries) e.value: e.key};

// ═══════════════════════════════════════════════════════════════════
// النماذج
// ═══════════════════════════════════════════════════════════════════

enum BStatus { pending, confirmed, rejected, done, cancelled }

class Booking {
  final String id;
  final Trip t;
  final int seats;
  final bool family;
  BStatus status;
  bool rated;
  /// رمز الرحلة: الراكب بيتأكد منو مع السائق قبل ما يطلع (بيظهر بعد التأكيد)
  String? pin;
  String? plate;
  String? driverPhone;
  Booking(this.t, this.seats, {String? id, this.family = false, this.status = BStatus.pending, this.rated = false, this.pin, this.plate, this.driverPhone})
      : id = id ?? 'local-${DateTime.now().microsecondsSinceEpoch}';
  int get total => t.price * seats;
  bool get active => status == BStatus.pending || status == BStatus.confirmed;
}

class RideReq {
  final String id;
  final Person p;
  final String note;
  final int seats;
  int state; // 0 بانتظار، 1 مقبول، 2 مرفوض
  RideReq(this.p, this.note, {this.seats = 1, String? id, this.state = 0}) : id = id ?? 'req-${DateTime.now().microsecondsSinceEpoch}';
}

class MyRide {
  final Trip t;
  final reqs = <RideReq>[];
  String status; // scheduled, in_progress, completed, cancelled
  MyRide(this.t, {this.status = 'scheduled'});
  int get booked => reqs.where((q) => q.state == 1).fold(0, (a, q) => a + q.seats);
  int get pending => reqs.where((q) => q.state == 0).length;
}

enum DStatus { none, reviewing, interview, approved, rejected, suspended }

/// طلب الانضمام كسائق موثّق.
class DriverApp {
  String? id;
  String name = '', phone = '', city = '', car = '', year = '', color = '', plate = '';
  final docs = <String, Uint8List>{};
  String place = '';
  int day = 1;
  String slot = '';
  String? note;
  DateTime sent = DateTime.now();

  /// موعد المقابلة بتوقيت دمشق.
  DateTime get interviewAt {
    final p = slot.split(':');
    final d = DateTime.now().toUtc().add(const Duration(hours: 3)).add(Duration(days: day));
    return DateTime.utc(d.year, d.month, d.day, int.parse(p[0]), int.parse(p[1])).subtract(const Duration(hours: 3));
  }
}

class UserProfile {
  final String id, name;
  final bool? female;
  final DStatus driverStatus;
  final String? phone, car, plate, vehicleId, photo;
  final double rating;
  final int trips;
  final String role;
  final String? music;
  final Map<String, String> prefs;
  const UserProfile({required this.id, required this.name, this.female, this.driverStatus = DStatus.none, this.phone, this.car, this.plate, this.vehicleId, this.photo, this.rating = 0, this.trips = 0, this.role = 'user', this.music, this.prefs = const {}});
  Person get person => Person(name, name.isEmpty ? '؟' : name.substring(0, 1), id: id, photo: photo, rating: rating, trips: trips);
  bool get complete => name.trim().length >= 3 && female != null;
}

/// ملف السائق كما بيشوفو الراكب.
class DriverPublic {
  final Person p;
  final int trips, reviewsCount;
  final double rating;
  final bool verified;
  final DateTime? since;
  final List<Review> reviews;
  final Map<int, int> histogram;
  const DriverPublic(this.p, {this.trips = 0, this.reviewsCount = 0, this.rating = 0, this.verified = false, this.since, this.reviews = const [], this.histogram = const {}});
}

class AppNotification {
  final String id, kind, title, body;
  final DateTime at;
  final bool read;
  const AppNotification(this.id, this.kind, this.title, this.body, this.at, {this.read = false});
}

class ChatMessage {
  final String id, body;
  final bool mine;
  final DateTime at;
  const ChatMessage(this.id, this.body, this.mine, this.at);
}

String timeAgo(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'هلق';
  if (d.inMinutes < 60) return 'قبل ${d.inMinutes} د';
  if (d.inHours < 24) return 'قبل ${d.inHours} س';
  if (d.inDays == 1) return 'مبارح';
  return 'قبل ${d.inDays} أيام';
}

// ═══════════════════════════════════════════════════════════════════
// Store: حالة التطبيق. الشاشات بتحكي معو، وهو بيحكي مع الـ Backend
// (Supabase الحقيقي إذا في مفاتيح، أو التجريبي المحلي).
// ═══════════════════════════════════════════════════════════════════
class Store extends ChangeNotifier {
  static final i = Store._();
  Store._();

  final messenger = GlobalKey<ScaffoldMessengerState>();
  Backend backend = DemoBackend();
  StreamSubscription<void>? _changes;

  UserProfile? profile;
  DriverApp? app;
  int pax = 1;
  final bookings = <Booking>[];
  final rides = <MyRide>[];
  final notifications = <AppNotification>[];
  final recent = <(String, String)>[('جبلة', 'حمص'), ('طرطوس', 'حلب')];
  bool loadingTrips = false;

  bool get live => backend.isLive;
  bool get signedIn => backend.signedIn;
  String get name => (profile?.name.trim().isNotEmpty ?? false) ? profile!.name.split(' ').first : 'ضيف';
  bool get female => profile?.female ?? false;
  DStatus get driverStatus => profile?.driverStatus ?? DStatus.none;
  int get unread => notifications.where((n) => !n.read).length;

  /// بيشغّل الـ Backend وبيرجّع إذا المستخدم مسجّل وحسابو كامل.
  Future<bool> start(Backend b) async {
    backend = b;
    await backend.init();
    _changes?.cancel();
    _changes = backend.changes.listen((_) => refreshAll());
    if (!backend.signedIn) return false;
    await _loadProfile();
    if (profile?.complete ?? false) unawaited(refreshAll());
    return profile?.complete ?? false;
  }

  Future<void> _loadProfile() async {
    profile = await backend.loadProfile();
    notifyListeners();
  }

  bool _notesLoaded = false;

  Future<void> refreshAll() async {
    if (!backend.signedIn) return;
    final seen = {for (final n in notifications) n.id};
    try {
      final results = await Future.wait([backend.myBookings(), backend.myRides(), backend.notifications(), backend.loadProfile()]);
      bookings
        ..clear()
        ..addAll(results[0] as List<Booking>);
      rides
        ..clear()
        ..addAll(results[1] as List<MyRide>);
      notifications
        ..clear()
        ..addAll(results[2] as List<AppNotification>);
      profile = results[3] as UserProfile? ?? profile;
      // إشعار جديد وصل؟ منعرضو فوراً
      if (_notesLoaded) {
        for (final n in notifications.where((n) => !n.read && !seen.contains(n.id)).take(2)) {
          say('${n.title} · ${n.body}');
        }
      }
      _notesLoaded = true;
      notifyListeners();
      if (profile?.complete ?? false) unawaited(onSignedIn?.call() ?? Future.value());
    } catch (_) {
      // التحديث بالخلفية: إذا فشل منحافظ عالبيانات القديمة
    }
  }

  // ── الدخول ─────────────────────────────────────────────────────────
  Future<void> sendOtp(String phone) => _guard(() => backend.sendOtp(normalizePhone(phone)));

  /// بيرجّع true إذا الحساب كامل (فينا ندخل عالرئيسية مباشرة).
  Future<bool> verifyOtp(String phone, String code) => _guard(() async {
        await backend.verifyOtp(normalizePhone(phone), code);
        await _loadProfile();
        if (profile?.complete ?? false) unawaited(refreshAll());
        return profile?.complete ?? false;
      });

  Future<void> completeProfile(String fullName, bool female, {String? music}) => _guard(() async {
        await backend.completeProfile(fullName, female, music: music);
        await _loadProfile();
        unawaited(refreshAll());
      });

  /// بينادى قبل الخروج (لإلغاء تسجيل جهاز الإشعارات).
  static Future<void> Function()? onSigningOut;

  Future<void> signOut() async {
    try {
      await onSigningOut?.call();
    } catch (_) {}
    await backend.signOut();
    profile = null;
    bookings.clear();
    rides.clear();
    notifications.clear();
    notifyListeners();
  }

  // ── البحث ──────────────────────────────────────────────────────────
  void search(String from, String to) {
    recent.removeWhere((e) => e.$1 == from && e.$2 == to);
    recent.insert(0, (from, to));
    if (recent.length > 3) recent.removeLast();
    notifyListeners();
  }

  Future<List<Trip>> searchTrips(String from, String to, int day, int seats) => _guard(() => backend.searchTrips(from, to, day, seats));
  Future<Map<String, (int, int)>> destinationStats(String from, int day) => _guard(() => backend.destinationStats(from, day));

  // ── الحجوزات ───────────────────────────────────────────────────────
  List<Booking> get upcoming => bookings.where((b) => b.active).toList()..sort((a, b) => a.t.day != b.t.day ? a.t.day.compareTo(b.t.day) : a.t.dep.compareTo(b.t.dep));
  List<Booking> get past => bookings.where((b) => b.status == BStatus.done).toList();
  Booking? get next {
    final u = upcoming;
    return u.isEmpty ? null : u.first;
  }

  Booking? bookingOf(Trip t) {
    for (final b in bookings) {
      if (b.t.id == t.id && b.active) return b;
    }
    return null;
  }

  Future<Booking> book(Trip t, int seats, {bool family = false, String? message}) => _guard(() async {
        final b = await backend.requestBooking(t, seats, family: family, message: message);
        bookings.removeWhere((x) => x.id == b.id);
        bookings.insert(0, b);
        notifyListeners();
        return b;
      });

  Future<Booking> details(Booking b) => _guard(() async {
        final d = await backend.bookingDetails(b);
        final i = bookings.indexWhere((x) => x.id == d.id);
        if (i >= 0) bookings[i] = d;
        notifyListeners();
        return d;
      });

  Future<void> cancel(Booking b, {String reason = ''}) => _guard(() async {
        await backend.cancelBooking(b, reason);
        b.status = BStatus.cancelled;
        notifyListeners();
      });

  Future<void> rate(Booking b, int stars, List<String> tags, String? comment) => _guard(() async {
        await backend.submitReview(b, stars, tags, comment);
        b.rated = true;
        notifyListeners();
      });

  Future<void> report(String targetId, String reason, {String? tripId, String? details}) => _guard(() => backend.report(targetId, tripId, reason, details));

  // ── السائق ─────────────────────────────────────────────────────────
  int get driverPending => rides.fold(0, (a, r) => a + r.pending);

  Future<Trip> publish(Trip draft, {List<String> prefs = const [], String? note}) => _guard(() async {
        final t = await backend.publishTrip(draft, prefs: prefs, note: note);
        rides.insert(0, MyRide(t));
        notifyListeners();
        return t;
      });

  Future<void> answer(RideReq q, bool ok) => _guard(() async {
        await backend.respond(q, ok);
        q.state = ok ? 1 : 2;
        notifyListeners();
      });

  Future<void> cancelRide(MyRide r) => _guard(() async {
        await backend.cancelTrip(r.t);
        r.status = 'cancelled';
        notifyListeners();
      });

  Future<void> startRide(MyRide r) => _guard(() async {
        await backend.startTrip(r.t);
        r.status = 'in_progress';
        notifyListeners();
      });

  Future<void> finishRide(MyRide r) => _guard(() async {
        await backend.completeTrip(r.t);
        r.status = 'completed';
        notifyListeners();
      });

  /// الراكب بيأكد وصولو (بالتجريبي). بالحقيقي السائق هو اللي بينهي الرحلة.
  void finish(Booking b) {
    if (!live) b.status = BStatus.done;
    notifyListeners();
  }

  Future<void> submitApplication(DriverApp a, {void Function(double)? onProgress}) => _guard(() async {
        app = a..sent = DateTime.now();
        await backend.submitApplication(a, onProgress ?? (_) {});
        await _loadProfile();
      });

  Future<void> refreshApplication() async {
    try {
      final (status, a) = await backend.application();
      if (a != null) app = a;
      if (profile != null && status != profile!.driverStatus) await _loadProfile();
      notifyListeners();
    } catch (_) {}
  }

  /// بالتجريبي بس: بيحاكي حضور المقابلة.
  void finishInterview() {
    if (backend is DemoBackend) (backend as DemoBackend).approveAfterInterview();
  }

  Future<void> cancelApplication() => _guard(() async {
        await backend.cancelApplication();
        app = null;
        await _loadProfile();
      });

  // ── التتبع والرسائل والإشعارات ─────────────────────────────────────
  Future<void> updateLocation(Trip t, double lat, double lon, {double? accuracy, double? heading}) async {
    try {
      await backend.updateLocation(t, lat, lon, accuracy, heading);
    } catch (_) {
      // التتبع بيكمّل بالمحاولة الجاية
    }
  }

  Future<DriverPublic> driverPublic(Person p) => _guard(() => backend.driverPublic(p));

  Future<void> updateProfile({String? name, String? music, Map<String, String>? prefs}) => _guard(() async {
        if (name != null && name.trim().length < 3) throw AppException('INVALID_NAME', AppException.messages['INVALID_NAME']!);
        await backend.updateProfile(name: name?.trim(), music: music, prefs: prefs);
        await _loadProfile();
      });

  Future<void> uploadAvatar(Uint8List bytes) => _guard(() async {
        await backend.uploadAvatar(bytes);
        await _loadProfile();
      });

  Future<void> requestDeletion() => _guard(() async {
        await backend.requestDeletion();
        await signOut();
      });

  /// بينادى بعد الدخول (الإشعارات). بيتعيّن من main لحتى Store ما يعتمد على Firebase.
  static Future<void> Function()? onSignedIn;

  Future<void> registerDevice(String token, String platform) async {
    try {
      await backend.registerDevice(token, platform);
    } catch (_) {}
  }

  Future<void> unregisterDevice(String token) async {
    try {
      await backend.unregisterDevice(token);
    } catch (_) {}
  }

  Future<String> shareLink(Booking b) => _guard(() => backend.createShareLink(b));
  Stream<List<ChatMessage>> messages(String bookingId) => backend.messages(bookingId);
  Future<void> sendMessage(String bookingId, String body) => _guard(() => backend.sendMessage(bookingId, body.trim()));

  Future<void> markAllRead() => _guard(() async {
        await backend.markNotificationsRead();
        final all = notifications.map((n) => AppNotification(n.id, n.kind, n.title, n.body, n.at, read: true)).toList();
        notifications
          ..clear()
          ..addAll(all);
        notifyListeners();
      });

  // ── أدوات ──────────────────────────────────────────────────────────
  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw AppException.from(e);
    }
  }

  void say(String msg) => messenger.currentState?.showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Lalezar')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF064854),
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
}

/// رقم سوري بالصيغة الدولية: +9639XXXXXXXX
String normalizePhone(String raw) {
  // الأرقام العربية (٠١٢...) بتتحوّل لإنكليزية أول
  const eastern = '٠١٢٣٤٥٦٧٨٩';
  final buf = StringBuffer();
  for (final ch in raw.split('')) {
    final k = eastern.indexOf(ch);
    buf.write(k >= 0 ? '$k' : ch);
  }
  var d = buf.toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00963')) d = d.substring(5);
  if (d.startsWith('963')) d = d.substring(3);
  if (d.startsWith('0')) d = d.substring(1);
  if (!RegExp(r'^9[0-9]{8}$').hasMatch(d)) throw const AppException('INVALID_PHONE', 'رقم الموبايل مو صحيح، لازم يبلّش بـ 9 ويكون 9 أرقام');
  return '+963$d';
}
