// حسابات جغرافية مشتركة: مسافات، مسار تقريبي، وتنسيق للعرض.
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'models.dart';

/// المسافة بالكيلومتر (Haversine).
double kmBetween(LatLng a, LatLng b) {
  const r = 6371.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180, dLon = (b.longitude - a.longitude) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(a.latitude * math.pi / 180) * math.cos(b.latitude * math.pi / 180) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(h.toDouble()));
}

/// مسار تقريبي (خطوط مستقيمة) لما المزود ما بيرد. الطول × 1.3 تقدير لطول الطريق الفعلي.
RouteOption approximateRoute(List<LatLng> pts) {
  var km = 0.0;
  for (var i = 0; i < pts.length - 1; i++) {
    km += kmBetween(pts[i], pts[i + 1]);
  }
  km *= 1.3;
  return RouteOption(line: List.of(pts), meters: (km * 1000).round(), seconds: (km / 65 * 3600).round(), summary: 'تقريبي', approximate: true);
}

/// "850 م" أو "12.4 كم" أو "182 كم".
String fmtKm(double km) {
  if (km < 1) return '${(km * 1000).round()} م';
  if (km < 20) return '${km.toStringAsFixed(1)} كم';
  return '${km.round()} كم';
}

/// "45 د" أو "ساعتين و10 د".
String fmtSeconds(int s) {
  final m = (s / 60).round();
  if (m < 60) return '${math.max(1, m)} د';
  final h = m ~/ 60, r = m % 60;
  final hs = h == 1 ? 'ساعة' : h == 2 ? 'ساعتين' : '$h ساعات';
  return r == 0 ? hs : '$hs و$r د';
}

/// السعر بالآلاف: 75000 → "75 ألف".
String fmtPriceShort(int syp) => syp >= 1000 ? '${(syp / 1000).round()} ألف' : '$syp';

/// الحدود اللي بتجمع نقاط.
GeoBounds boundsOf(Iterable<LatLng> pts) {
  var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
  for (final p in pts) {
    s = math.min(s, p.latitude);
    n = math.max(n, p.latitude);
    w = math.min(w, p.longitude);
    e = math.max(e, p.longitude);
  }
  return GeoBounds(s, w, n, e);
}

/// أقرب نقطة على خط (لمعرفة إذا السائق انحرف عن الطريق مثلاً) بالكيلومتر.
double distanceToLineKm(LatLng p, List<LatLng> line) {
  if (line.isEmpty) return double.infinity;
  if (line.length == 1) return kmBetween(p, line.first);
  var best = double.infinity;
  final cosLat = math.cos(p.latitude * math.pi / 180);
  for (var i = 0; i < line.length - 1; i++) {
    final a = line[i], b = line[i + 1];
    // إسقاط مسطح محلي (دقيق كفاية لمسافات قصيرة)
    final ax = (a.longitude - p.longitude) * cosLat, ay = a.latitude - p.latitude;
    final bx = (b.longitude - p.longitude) * cosLat, by = b.latitude - p.latitude;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    final d = math.sqrt(cx * cx + cy * cy) * 111.32;
    if (d < best) best = d;
  }
  return best;
}
