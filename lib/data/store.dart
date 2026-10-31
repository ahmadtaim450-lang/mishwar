// حالة التطبيق: الحجوزات، الرحلات المنشورة، وتوليد رحلات منطقية لكل طريق.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'mock.dart';

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
};

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
  const majors = ['طرطوس', 'حمص', 'حماة', 'جبلة'];
  final c = majors.where((m) => m != a && m != b && _hav(a, m) + _hav(m, b) <= d * 1.2).toList()..sort((x, y) => _hav(a, x).compareTo(_hav(a, y)));
  if (c.length <= 2) return c;
  return [c.first, c.last];
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
      ));
    }
    return list;
  }();
}

enum BStatus { pending, confirmed, done, cancelled }

class Booking {
  final Trip t;
  final int seats;
  final bool family;
  BStatus status;
  bool rated = false;
  Booking(this.t, this.seats, {this.family = false, this.status = BStatus.pending});
  int get total => t.price * seats;
}

class RideReq {
  final Person p;
  final String note;
  final int seats;
  int state = 0; // 0 بانتظار، 1 مقبول، 2 مرفوض
  RideReq(this.p, this.note, {this.seats = 1});
}

class MyRide {
  final Trip t;
  final reqs = <RideReq>[];
  MyRide(this.t);
  int get booked => reqs.where((q) => q.state == 1).fold(0, (a, q) => a + q.seats);
  int get pending => reqs.where((q) => q.state == 0).length;
}

class Store extends ChangeNotifier {
  static final i = Store._();
  final messenger = GlobalKey<ScaffoldMessengerState>();

  bool female = false;
  String name = 'إيهاب';
  int pax = 1;
  final bookings = <Booking>[];
  final rides = <MyRide>[];
  final recent = <(String, String)>[('جبلة', 'حمص'), ('طرطوس', 'حلب')];

  Store._() {
    final t = tripsFor('اللاذقية', 'دمشق', day: 1).first;
    bookings.add(Booking(t, 1, status: BStatus.confirmed));
    final past = tripsFor('جبلة', 'حمص', day: -4).first;
    bookings.add(Booking(past, 1, status: BStatus.done));
  }

  List<Booking> get upcoming => bookings.where((b) => b.status == BStatus.pending || b.status == BStatus.confirmed).toList()..sort((a, b) => a.t.day != b.t.day ? a.t.day.compareTo(b.t.day) : a.t.dep.compareTo(b.t.dep));
  List<Booking> get past => bookings.where((b) => b.status == BStatus.done).toList();
  Booking? get next {
    final u = upcoming;
    return u.isEmpty ? null : u.first;
  }

  int get driverPending => rides.fold(0, (a, r) => a + r.pending);

  Booking? bookingOf(Trip t) {
    for (final b in bookings) {
      if (b.t.id == t.id && b.status != BStatus.cancelled) return b;
    }
    return null;
  }

  void setFemale(bool v) {
    female = v;
    notifyListeners();
  }

  void search(String from, String to) {
    recent.removeWhere((e) => e.$1 == from && e.$2 == to);
    recent.insert(0, (from, to));
    if (recent.length > 3) recent.removeLast();
    notifyListeners();
  }

  Booking book(Trip t, int seats, {bool family = false}) {
    final b = Booking(t, seats, family: family, status: t.instant ? BStatus.confirmed : BStatus.pending);
    bookings.insert(0, b);
    notifyListeners();
    if (!t.instant) {
      Timer(const Duration(seconds: 9), () {
        if (b.status != BStatus.pending) return;
        b.status = BStatus.confirmed;
        notifyListeners();
        say('${t.driver.name} قبل حجزك على رحلة ${t.from} ← ${t.to}. رحلة موفقة');
      });
    }
    return b;
  }

  void cancel(Booking b) {
    b.status = BStatus.cancelled;
    notifyListeners();
  }

  void finish(Booking b) {
    b.status = BStatus.done;
    notifyListeners();
  }

  void rate(Booking b) {
    b.rated = true;
    notifyListeners();
  }

  void publish(Trip t) {
    final ride = MyRide(t);
    rides.insert(0, ride);
    notifyListeners();
    final guests = female
        ? [(reem, 'راكبة وحدة · شنتاية صغيرة', 1), (noorDriver, 'مع بنتي · مقعدين', 2)]
        : [(mazen, 'راكب واحد · طالب جامعة', 1), (hussam, 'شنتاية صغيرة', 1)];
    var delay = 7;
    for (final (p, note, s) in guests) {
      Timer(Duration(seconds: delay), () {
        if (!rides.contains(ride)) return;
        ride.reqs.add(RideReq(p, note, seats: s));
        notifyListeners();
        say('وصلك طلب حجز من ${p.name} على رحلتك لـ${t.to}');
      });
      delay += 12;
    }
  }

  void answer(RideReq q, bool ok) {
    q.state = ok ? 1 : 2;
    notifyListeners();
  }

  void say(String msg) => messenger.currentState?.showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Lalezar')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF064854),
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
}
