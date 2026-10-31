import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import 'common.dart';
import 'real_map.dart';

class DestStat {
  final String city;
  final int trips;
  final int fromPrice;
  final String? tag;
  const DestStat(this.city, this.trips, this.fromPrice, [this.tag]);
}

const destStats = <DestStat>[
  DestStat('دمشق', 12, 70000, 'الأكتر طلب'),
  DestStat('حلب', 8, 85000),
  DestStat('حمص', 15, 45000, 'الأرخص'),
  DestStat('طرطوس', 9, 25000),
  DestStat('حماة', 6, 55000),
  DestStat('درعا', 3, 95000),
];

/// خريطة الوجهات: فقاعات حسب عدد الرحلات، زوم بالإصبعين، وضغطة على مدينة بتقرّب عليها.
class DestinationsMap extends StatefulWidget {
  final String from;
  final ValueChanged<String> onSearch;
  const DestinationsMap({required this.from, required this.onSearch});
  @override
  State<DestinationsMap> createState() => _DestinationsMapState();
}

class _DestinationsMapState extends State<DestinationsMap> with TickerProviderStateMixin {
  final _map = MapController();
  DestStat? _sel;
  static const _home = LatLng(34.6, 36.6);
  static const _homeZoom = 6.6;

  void _flyTo(LatLng to, double zoom) {
    final from = _map.camera.center, fz = _map.camera.zoom;
    final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    final a = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic);
    // قوس خفيف بالزوم: بيبعّد شوي بالنص وبعدين بيقرّب
    c.addListener(() {
      final t = a.value;
      final lat = from.latitude + (to.latitude - from.latitude) * t;
      final lng = from.longitude + (to.longitude - from.longitude) * t;
      final z = fz + (zoom - fz) * t - math.sin(t * math.pi) * .6;
      _map.move(LatLng(lat, lng), z);
    });
    c.forward().whenComplete(c.dispose);
  }

  void _select(DestStat d) {
    final p = kCityPoints[d.city];
    if (p == null) return;
    setState(() => _sel = d);
    _flyTo(p, 10.5);
  }

  void _reset() {
    setState(() => _sel = null);
    _flyTo(_home, _homeZoom);
  }

  @override
  Widget build(BuildContext context) {
    final me = kCityPoints[widget.from];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('رحلات اليوم على الخريطة', style: T.h3)),
        if (_sel != null)
          TextButton.icon(onPressed: _reset, icon: const Icon(Icons.zoom_out_map_rounded, size: 18), label: const Text('كل المدن', style: TextStyle(fontFamily: kFont)))
        else
          const Text('حجم الدائرة = عدد الرحلات', style: T.small),
      ]),
      const SizedBox(height: 8),
      Container(
        height: 340,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: C.dark.withValues(alpha: .08), blurRadius: 20, offset: const Offset(0, 8))]),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _home,
              initialZoom: _homeZoom,
              minZoom: 5.5,
              maxZoom: 16,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onTap: (_, __) {
                if (_sel != null) setState(() => _sel = null);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.mishwar.mishwar',
              ),
              MarkerLayer(markers: [
                if (me != null)
                  Marker(
                    point: me,
                    width: 80,
                    height: 46,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(8)), child: const Text('انت هون', style: TextStyle(fontFamily: kFont, fontSize: 11, color: Colors.white))),
                      const SizedBox(height: 3),
                      Container(width: 16, height: 16, decoration: BoxDecoration(color: C.dark, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3))),
                    ]),
                  ),
                for (final d in destStats)
                  if (kCityPoints[d.city] != null && d.city != widget.from)
                    Marker(
                      point: kCityPoints[d.city]!,
                      width: 110,
                      height: 110,
                      child: _Bubble(d, selected: _sel == d, onTap: () => _select(d)),
                    ),
              ]),
              const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap · CARTO')]),
            ],
          ),
          Positioned(
            left: 10,
            top: 10,
            child: Column(children: [
              _zoomBtn(Icons.add_rounded, () => _flyTo(_map.camera.center, _map.camera.zoom + 1)),
              const SizedBox(height: 6),
              _zoomBtn(Icons.remove_rounded, () => _flyTo(_map.camera.center, _map.camera.zoom - 1)),
            ]),
          ),
        ]),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: _sel == null
            ? Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  height: 40,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final d in destStats)
                      if (d.city != widget.from)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ActionChip(
                            label: Text('${d.city} · ${d.trips}', style: const TextStyle(fontFamily: kFont, color: C.dark)),
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: C.border),
                            onPressed: () => _select(d),
                          ),
                        ),
                  ]),
                ),
              )
            : Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Enter(
                  key: ValueKey(_sel!.city),
                  child: CardBox(
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text('${widget.from} ← ${_sel!.city}', style: T.h3),
                            if (_sel!.tag != null) ...[const SizedBox(width: 8), Badge2(_sel!.tag!, bg: C.warnBg, fg: C.warn)],
                          ]),
                          Text('${_sel!.trips} رحلة اليوم · من ${money(_sel!.fromPrice)}', style: T.small),
                        ]),
                      ),
                      SizedBox(width: 120, child: Btn('اعرض', onTap: () => widget.onSearch(_sel!.city))),
                    ]),
                  ),
                ),
              ),
      ),
    ]);
  }

  Widget _zoomBtn(IconData i, VoidCallback f) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        child: InkWell(borderRadius: BorderRadius.circular(12), onTap: f, child: SizedBox(width: 40, height: 40, child: Icon(i, color: C.dark))),
      );
}

class _Bubble extends StatefulWidget {
  final DestStat d;
  final bool selected;
  final VoidCallback onTap;
  const _Bubble(this.d, {required this.selected, required this.onTap});
  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> with SingleTickerProviderStateMixin {
  late final AnimationController _p = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = 30.0 + widget.d.trips * 2.2;
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(alignment: Alignment.center, children: [
        AnimatedBuilder(
          animation: _p,
          builder: (_, __) => Container(
            width: s * (1 + _p.value * .7),
            height: s * (1 + _p.value * .7),
            decoration: BoxDecoration(shape: BoxShape.circle, color: (widget.selected ? C.yellow : C.primary).withValues(alpha: .35 * (1 - _p.value))),
          ),
        ),
        AnimatedScale(
          scale: widget.selected ? 1.15 : 1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(color: widget.selected ? C.yellow : C.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: C.dark.withValues(alpha: .25), blurRadius: 8, offset: const Offset(0, 3))]),
            alignment: Alignment.center,
            child: Text('${widget.d.trips}', style: TextStyle(fontFamily: kFont, fontSize: 15, color: widget.selected ? C.dark : Colors.white)),
          ),
        ),
        Positioned(
          bottom: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 4)]),
            child: Text(widget.d.city, style: const TextStyle(fontFamily: kFont, fontSize: 12, color: C.dark)),
          ),
        ),
      ]),
    );
  }
}
