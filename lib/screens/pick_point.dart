// السائق بيحدد نقطة التجمع (والنزول) الدقيقة على الخريطة: بيحرّك الخريطة والدبوس بالنص.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../data/store.dart';
import '../map/geo_math.dart';
import '../map/location_service.dart';
import '../map/map_widgets.dart';
import '../map/models.dart';
import '../map/tiles.dart';
import '../widgets/common.dart';

class PickPointScreen extends StatefulWidget {
  final Trip trip;
  const PickPointScreen(this.trip, {super.key});
  @override
  State<PickPointScreen> createState() => _PickPointScreenState();
}

class _PickPointScreenState extends State<PickPointScreen> with TickerProviderStateMixin {
  final _map = MapController();
  late final _anim = MapAnimator(_map, this);
  int _step = 0; // 0 الانطلاق، 1 الوصول
  LatLng? _pickup, _dropoff;
  LatLng? _center;
  String _address = '';
  bool _resolving = false;
  Timer? _debounce;
  bool _loaded = false;

  String get _city => _step == 0 ? widget.trip.from : widget.trip.to;
  LatLng get _cityPoint {
    final g = geo[_city];
    return g == null ? const LatLng(34.8, 36.5) : LatLng(g.$1, g.$2);
  }

  double get _fromCityKm => _center == null ? 0 : kmBetween(_center!, _cityPoint);
  bool get _tooFar => _fromCityKm > 25;

  @override
  void initState() {
    super.initState();
    Store.i.tripPoints(widget.trip).then((p) {
      if (!mounted) return;
      setState(() {
        _pickup = p.$1;
        _dropoff = p.$2;
        _loaded = true;
      });
      if (p.$1 != null) _anim.move(p.$1!, 16);
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _moved(MapCamera cam) {
    _center = cam.center;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _resolve);
    if (mounted) setState(() {});
  }

  Future<void> _resolve() async {
    final c = _center;
    if (c == null) return;
    setState(() => _resolving = true);
    GeoPlace? r;
    try {
      r = await Store.i.reverseGeocode(c);
    } catch (_) {}
    if (!mounted || _center != c) return;
    setState(() {
      _resolving = false;
      _address = r == null ? '' : [r.name, r.label].where((e) => e.isNotEmpty).join('، ');
    });
  }

  Future<void> _useMyLocation() async {
    final s = await LocationService.i.locate();
    if (!mounted) return;
    final p = LocationService.i.point;
    if (s != LocStatus.ok || p == null) {
      toast(context, locMessage(s));
      return;
    }
    _anim.move(p, 17);
  }

  void _switch(int step) {
    setState(() => _step = step);
    final p = step == 0 ? _pickup : _dropoff;
    _anim.move(p ?? _cityPoint, p == null ? 13 : 16);
  }

  Future<void> _confirm() async {
    final c = _center;
    if (c == null) return;
    setState(() => _step == 0 ? _pickup = c : _dropoff = c);
    if (_step == 0) {
      _switch(1);
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    final ok = await attempt(context, () => Store.i.setTripPoints(widget.trip, pickup: _pickup, dropoff: _dropoff));
    if (ok && mounted) {
      toast(context, 'انحفظت نقاط التجمع، الركاب رح يشوفوها على الخريطة');
      Navigator.maybePop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _step == 0 ? _pickup : _dropoff;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: TopBar(title: 'نقطة التجمع', sub: '${widget.trip.from} ← ${widget.trip.to}'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(children: [
            Expanded(child: _seg(0, 'الانطلاق · ${widget.trip.from}', _pickup != null)),
            const SizedBox(width: 8),
            Expanded(child: _seg(1, 'الوصول · ${widget.trip.to}', _dropoff != null)),
          ]),
        ),
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: _cityPoint,
                  initialZoom: 13,
                  minZoom: 9,
                  maxZoom: MapTiles.maxZoom,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  onMapReady: () => WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _moved(_map.camera);
                  }),
                  onPositionChanged: (cam, _) => WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _moved(cam);
                  }),
                ),
                children: [
                  mishwarTiles(dark: Store.i.mapDark),
                  CircleLayer(circles: [
                    CircleMarker(point: _cityPoint, radius: 25000, useRadiusInMeter: true, color: Colors.transparent, borderColor: C.primary.withValues(alpha: .5), borderStrokeWidth: 2),
                  ]),
                  MarkerLayer(markers: [
                    if (saved != null) Marker(point: saved, width: 40, height: 44, alignment: Alignment.topCenter, child: const PlacePin(icon: Icons.check_rounded, color: C.primary)),
                  ]),
                  RichAttributionWidget(showFlutterMapAttribution: false, attributions: [TextSourceAttribution(MapTiles.attribution)]),
                ],
              ),
            ),
            // الدبوس بنص الخريطة (الخريطة بتتحرك تحتو)
            IgnorePointer(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 44),
                  child: PlacePin(icon: _step == 0 ? Icons.groups_rounded : Icons.flag_rounded, color: _tooFar ? C.danger : C.dark),
                ),
              ),
            ),
            Positioned(left: 12, bottom: 12, child: MapFab(Icons.my_location_rounded, tooltip: 'موقعي', busy: LocationService.i.status == LocStatus.searching, onTap: _useMyLocation)),
          ]),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _tooFar
                    ? 'النقطة بعيدة ${fmtKm(_fromCityKm)} عن ${_city}، لازم تكون ضمن 25 كم'
                    : _resolving
                        ? 'عم نجيب العنوان...'
                        : (_address.isEmpty ? 'حرّك الخريطة لحتى الدبوس يصير على المكان بالزبط' : _address),
                style: _tooFar ? const TextStyle(fontFamily: kFont, color: C.danger, fontSize: 14) : T.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              const Text('اختار مكان واضح وسهل الوقوف فيه (كراج، دوّار، محطة).', style: T.small),
              const SizedBox(height: 12),
              Row(children: [
                if (_step == 1 || _pickup != null) ...[
                  Expanded(child: Btn('احفظ هيك', kind: BtnKind.outline, onTap: !_loaded ? null : _save)),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: Btn(_step == 0 ? 'هون نقطة الانطلاق' : 'هون نقطة الوصول', icon: Icons.check_rounded, onTap: _tooFar || _center == null || !_loaded ? null : _confirm),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _seg(int i, String label, bool done) => Press(
        onTap: () => _switch(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(color: _step == i ? C.dark : Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (done) ...[Icon(Icons.check_circle_rounded, size: 16, color: _step == i ? C.yellow : C.primary), const SizedBox(width: 4)],
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: kFont, fontSize: 13, color: _step == i ? Colors.white : C.dark))),
          ]),
        ),
      );
}
