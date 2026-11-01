// تجميع العلامات المتقاربة (Clustering) بشبكة على مستوى البكسل حسب التكبير.
// خوارزمية خفيفة O(n): بتشتغل على آلاف النقاط بأجزاء من الثانية.
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class Cluster<T> {
  final LatLng point; // مركز المجموعة
  final List<T> items;
  const Cluster(this.point, this.items);
  int get size => items.length;
  bool get single => items.length == 1;

  /// حدود عناصر المجموعة (للتكبير عليها).
  (LatLng, LatLng) bounds(LatLng Function(T) pos) {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    for (final it in items) {
      final p = pos(it);
      s = math.min(s, p.latitude);
      n = math.max(n, p.latitude);
      w = math.min(w, p.longitude);
      e = math.max(e, p.longitude);
    }
    return (LatLng(s, w), LatLng(n, e));
  }
}

/// إسقاط Web Mercator لبكسل عند تكبير معيّن (نفس إسقاط الخريطة).
math.Point<double> project(LatLng p, double zoom) {
  final scale = 256 * math.pow(2, zoom).toDouble();
  final lat = p.latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  final x = (p.longitude + 180) / 360 * scale;
  final y = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * scale;
  return math.Point(x, y);
}

/// بيجمّع العناصر اللي بتقع بنفس الخلية (حجمها [cellPx] بكسل).
/// فوق [maxZoom] كل عنصر لحالو، إلا إذا عناصر بنفس النقطة تماماً (بتضل مجموعة).
List<Cluster<T>> clusterize<T>(Iterable<T> items, LatLng Function(T) pos, double zoom, {double cellPx = 64, double maxZoom = 15}) {
  final z = zoom.clamp(0, 22).toDouble();
  final cells = <int, List<T>>{};
  final sums = <int, (double, double)>{};
  for (final it in items) {
    final p = pos(it);
    final int key;
    if (z > maxZoom) {
      // نفس النقطة (لحد ~1 متر) = نفس المفتاح
      key = Object.hash((p.latitude * 1e5).round(), (p.longitude * 1e5).round());
    } else {
      final px = project(p, z);
      key = Object.hash((px.x / cellPx).floor(), (px.y / cellPx).floor());
    }
    (cells[key] ??= <T>[]).add(it);
    final s = sums[key] ?? (0.0, 0.0);
    sums[key] = (s.$1 + p.latitude, s.$2 + p.longitude);
  }
  return [
    for (final e in cells.entries)
      Cluster<T>(LatLng(sums[e.key]!.$1 / e.value.length, sums[e.key]!.$2 / e.value.length), e.value),
  ];
}

/// تكبير مقرّب لنص درجة: ما منعيد التجميع مع كل حركة صغيرة بالإصبع.
double clusterZoom(double zoom) => (zoom * 2).floorToDouble() / 2;
