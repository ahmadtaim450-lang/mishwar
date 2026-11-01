// خدمة الموقع للخريطة: أذونات، موقع حالي، متابعة موفّرة للبطارية، واتجاه (بوصلة أو اتجاه الحركة).
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

enum LocStatus { idle, searching, ok, serviceOff, denied, deniedForever, unavailable }

/// اتجاه الجهاز من الحساسات (مع تصحيح الميلان) بالدرجات: 0 شمال، 90 شرق.
/// [a] تسارع (الجاذبية) و[m] حقل مغناطيسي، بإحداثيات الجهاز (x يمين، y فوق، z لبرّا الشاشة).
double? headingFromSensors(List<double> a, List<double> m) {
  final ax = a[0], ay = a[1], az = a[2];
  final ex = m[0], ey = m[1], ez = m[2];
  var hx = ey * az - ez * ay, hy = ez * ax - ex * az, hz = ex * ay - ey * ax;
  final hn = math.sqrt(hx * hx + hy * hy + hz * hz);
  final an = math.sqrt(ax * ax + ay * ay + az * az);
  if (hn < 0.1 || an < 0.1) return null; // سقوط حر أو قرب مغناطيس قوي
  hx /= hn;
  hy /= hn;
  hz /= hn;
  final nx = ax / an, ny = ay / an, nz = az / an;
  final my = nz * hx - nx * hz;
  final deg = math.atan2(hy, my) * 180 / math.pi;
  return (deg + 360) % 360;
}

/// فرق زاويتين بأقصر اتجاه (-180..180).
double angleDelta(double a, double b) => ((b - a + 540) % 360) - 180;

/// تنعيم الزاوية (بلا قفزة عند 359→0).
double smoothAngle(double prev, double next, double k) => (prev + angleDelta(prev, next) * k + 360) % 360;

class LocationService extends ChangeNotifier {
  static final i = LocationService._();
  LocationService._();

  LocStatus status = LocStatus.idle;
  Position? last;
  double? _compass;
  StreamSubscription<Position>? _pos;
  StreamSubscription<AccelerometerEvent>? _acc;
  StreamSubscription<MagnetometerEvent>? _mag;
  List<double>? _a;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  int _watchers = 0;

  LatLng? get point => last == null ? null : LatLng(last!.latitude, last!.longitude);
  double? get accuracy => last?.accuracy;

  /// إشارة ضعيفة: الدقة أسوأ من 100 متر.
  bool get weak => (last?.accuracy ?? 0) > 100;

  /// الاتجاه: وقت السواقة اتجاه الحركة من GPS (أدق)، وغير هيك البوصلة.
  double? get heading {
    final p = last;
    if (p != null && p.speed > 2.5 && p.heading >= 0 && (p.headingAccuracy <= 0 || p.headingAccuracy < 45)) return p.heading;
    return _compass;
  }

  /// يطلب الإذن (إذا لازم) ويجيب الموقع الحالي. ما بيرمي أخطاء: الحالة بتوضح شو صار.
  Future<LocStatus> locate({Duration timeout = const Duration(seconds: 12)}) async {
    _set(LocStatus.searching);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _set(LocStatus.serviceOff);
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) return _set(LocStatus.deniedForever);
      if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) return _set(LocStatus.denied);
      try {
        last = await Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout));
      } on TimeoutException {
        // إشارة ضعيفة: آخر موقع معروف أحسن من لا شي
        if (!kIsWeb) last = await Geolocator.getLastKnownPosition();
        if (last == null) return _set(LocStatus.unavailable);
      }
      return _set(LocStatus.ok);
    } catch (_) {
      return _set(last == null ? LocStatus.unavailable : LocStatus.ok);
    }
  }

  /// متابعة الموقع وقت الشاشة مفتوحة. [precise] للتتبع وقت الرحلة، غير هيك دقة متوسطة
  /// وتحديث كل 25 متر لتوفير البطارية. لازم ينادى [unwatch] بعدين.
  void watch({bool precise = false, bool compass = true}) {
    _watchers++;
    if (_pos != null) return;
    if (status != LocStatus.ok) return;
    final settings = LocationSettings(accuracy: precise ? LocationAccuracy.high : LocationAccuracy.medium, distanceFilter: precise ? 10 : 25);
    _pos = Geolocator.getPositionStream(locationSettings: settings).listen((p) {
      last = p;
      notifyListeners();
    }, onError: (_) {});
    if (compass && !kIsWeb) _startCompass();
  }

  void unwatch() {
    _watchers = math.max(0, _watchers - 1);
    if (_watchers > 0) return;
    _pos?.cancel();
    _pos = null;
    _acc?.cancel();
    _mag?.cancel();
    _acc = null;
    _mag = null;
  }

  void _startCompass() {
    try {
      _acc = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) => _a = [e.x, e.y, e.z], onError: (_) {});
      _mag = magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
        final a = _a;
        if (a == null) return;
        final h = headingFromSensors(a, [e.x, e.y, e.z]);
        if (h == null) return;
        final prev = _compass;
        _compass = prev == null ? h : smoothAngle(prev, h, .2);
        // تحديث الواجهة 6 مرات بالثانية بالكتير، وبس إذا الفرق ملحوظ
        final now = DateTime.now();
        if ((prev == null || angleDelta(prev, _compass!).abs() > 3) && now.difference(_lastNotify).inMilliseconds > 160) {
          _lastNotify = now;
          notifyListeners();
        }
      }, onError: (_) {});
    } catch (_) {
      // الجهاز بلا حساسات: منعتمد على اتجاه الحركة بس
    }
  }

  Future<void> openSettings() async {
    try {
      if (status == LocStatus.serviceOff) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
  }

  LocStatus _set(LocStatus s) {
    status = s;
    notifyListeners();
    return s;
  }

  /// للاختبارات: موقع جاهز بلا GPS.
  @visibleForTesting
  void debugSet(Position? p, {LocStatus s = LocStatus.ok}) {
    last = p;
    status = s;
    notifyListeners();
  }
}

/// رسالة واضحة لكل حالة.
String locMessage(LocStatus s) => switch (s) {
      LocStatus.serviceOff => 'خدمة الموقع (GPS) مسكّرة. شغّلها من الإعدادات',
      LocStatus.denied => 'لازم تسمح للتطبيق يعرف موقعك لحتى نوريك الرحلات القريبة',
      LocStatus.deniedForever => 'إذن الموقع مرفوض. فيك تفعّلو من إعدادات التطبيق',
      LocStatus.unavailable => 'ما قدرنا نحدد موقعك هلأ. جرّب بمكان مفتوح',
      LocStatus.searching => 'عم نحدد موقعك...',
      _ => '',
    };
