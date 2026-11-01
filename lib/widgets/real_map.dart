import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/theme.dart';
import '../data/store.dart' show geo;

/// مدن ونقاط حقيقية على الطريق الدولي (M1 / M5).
final kCityPoints = <String, LatLng>{
  for (final e in geo.entries) e.key: LatLng(e.value.$1, e.value.$2),
};

/// مسار تقريبي على الأوتوستراد، بينستعمل إذا ما في نت.
List<LatLng> fallbackRoute(List<String> cities) {
  final pts = <LatLng>[];
  const via = <String, List<LatLng>>{
    'طرطوس>حمص': [LatLng(34.80, 36.10), LatLng(34.74, 36.42)],
    'حمص>دمشق': [LatLng(34.40, 36.74), LatLng(34.02, 36.73), LatLng(33.74, 36.60)],
  };
  for (var i = 0; i < cities.length; i++) {
    final p = kCityPoints[cities[i]];
    if (p == null) continue;
    pts.add(p);
    if (i < cities.length - 1) pts.addAll(via['${cities[i]}>${cities[i + 1]}'] ?? const []);
  }
  return pts;
}

/// بيجيب الطريق الحقيقي من OSRM (مجاني)، وإذا فشل بيرجع المسار التقريبي.
Future<List<LatLng>> fetchRoute(List<String> cities) async {
  final pts = cities.map((c) => kCityPoints[c]).whereType<LatLng>().toList();
  if (pts.length < 2) return fallbackRoute(cities);
  try {
    final coords = pts.map((p) => '${p.longitude},${p.latitude}').join(';');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    final req = await client.getUrl(Uri.parse('https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson'));
    req.headers.set('User-Agent', 'Mishwar/1.0');
    final res = await req.close().timeout(const Duration(seconds: 10));
    final body = await res.transform(utf8.decoder).join();
    client.close();
    final j = jsonDecode(body) as Map<String, dynamic>;
    final line = (j['routes'] as List).first['geometry']['coordinates'] as List;
    return [for (final c in line) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())];
  } catch (_) {
    return fallbackRoute(cities);
  }
}

/// نقطة على المسار حسب النسبة (0..1)، مع الاتجاه.
(LatLng, double) pointAlong(List<LatLng> line, double t) {
  if (line.length < 2) return (line.isEmpty ? const LatLng(34.8, 36.5) : line.first, 0);
  const d = Distance();
  final segs = <double>[];
  for (var i = 0; i < line.length - 1; i++) {
    segs.add(d(line[i], line[i + 1]));
  }
  final total = segs.fold<double>(0, (a, b) => a + b);
  var target = total * t.clamp(0.0, 1.0);
  for (var i = 0; i < segs.length; i++) {
    if (target <= segs[i] || i == segs.length - 1) {
      final k = segs[i] == 0 ? 0.0 : (target / segs[i]).clamp(0.0, 1.0);
      final a = line[i], b = line[i + 1];
      final p = LatLng(a.latitude + (b.latitude - a.latitude) * k, a.longitude + (b.longitude - a.longitude) * k);
      final bearing = math.atan2(b.longitude - a.longitude, b.latitude - a.latitude);
      return (p, bearing);
    }
    target -= segs[i];
  }
  return (line.last, 0);
}

/// خريطة حقيقية فيها المسار والمدن، واختيارياً سيارة بتمشي.
class TripMap extends StatefulWidget {
  final List<String> cities;
  final double? carProgress; // null = بلا سيارة
  final bool interactive;
  final ValueChanged<List<LatLng>>? onRoute;
  final LatLng? me; // موقع GPS الحقيقي
  const TripMap({required this.cities, this.carProgress, this.interactive = true, this.onRoute, this.me});
  @override
  State<TripMap> createState() => _TripMapState();
}

class _TripMapState extends State<TripMap> {
  final _map = MapController();
  List<LatLng> _route = const [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _route = fallbackRoute(widget.cities);
    fetchRoute(widget.cities).then((r) {
      if (!mounted) return;
      setState(() => _route = r);
      widget.onRoute?.call(r);
      _fit();
    });
  }

  void _fit() {
    if (!_ready || _route.length < 2) return;
    _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(_route), padding: const EdgeInsets.fromLTRB(40, 60, 40, 60)));
  }

  @override
  Widget build(BuildContext context) {
    final car = widget.carProgress == null ? null : pointAlong(_route, widget.carProgress!);
    final done = car == null ? <LatLng>[] : (_route.sublist(0, (_route.length * widget.carProgress!).clamp(1, _route.length).toInt())..add(car.$1));
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: const LatLng(34.6, 36.3),
        initialZoom: 7,
        interactionOptions: InteractionOptions(flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
        onMapReady: () {
          _ready = true;
          _fit();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.mishwar.mishwar',
          maxZoom: 18,
          // بلا نت: الخريطة بتضل بدون خلفية بدل ما تطلع أخطاء
          tileProvider: NetworkTileProvider(silenceExceptions: true),
        ),
        PolylineLayer(polylines: [
          Polyline(points: _route, strokeWidth: 9, color: C.dark.withValues(alpha: .25)),
          Polyline(points: _route, strokeWidth: 5, color: C.primary),
          if (done.length > 1) Polyline(points: done, strokeWidth: 5, color: C.dark),
        ]),
        MarkerLayer(markers: [
          for (var i = 0; i < widget.cities.length; i++)
            if (kCityPoints[widget.cities[i]] != null)
              Marker(
                point: kCityPoints[widget.cities[i]]!,
                width: 100,
                height: 64,
                alignment: Alignment.topCenter,
                child: _CityPin(widget.cities[i], last: i == widget.cities.length - 1, first: i == 0),
              ),
          if (widget.me != null)
            Marker(
              point: widget.me!,
              width: 30,
              height: 30,
              child: Container(
                decoration: BoxDecoration(color: C.primary.withValues(alpha: .25), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Container(width: 16, height: 16, decoration: BoxDecoration(color: C.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3))),
              ),
            ),
          if (car != null)
            Marker(
              point: car.$1,
              width: 54,
              height: 54,
              child: Transform.rotate(
                angle: car.$2 - math.pi / 2,
                child: Image.asset('assets/images/car_topdown.png', errorBuilder: (_, __, ___) => const Icon(Icons.directions_car_filled_rounded, color: C.dark, size: 34)),
              ),
            ),
        ]),
        const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap')]),
      ],
    );
  }
}

class _CityPin extends StatelessWidget {
  final String name;
  final bool first, last;
  const _CityPin(this.name, {this.first = false, this.last = false});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: last ? C.yellow : (first ? C.dark : Colors.white), borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .15), blurRadius: 6)]),
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: kFont, fontSize: 13, color: first ? Colors.white : C.dark)),
        ),
        const SizedBox(height: 4),
        Container(width: 14, height: 14, decoration: BoxDecoration(color: last ? C.yellow : C.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3))),
      ]);
}
