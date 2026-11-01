// شاشة الخريطة: كل الرحلات على خريطة سوريا، تجميع، فلاتر، بحث جغرافي،
// موقعي مع الاتجاه، اختيار نقطة بالضغط المطوّل، مسارات بديلة، وأماكني المحفوظة.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../data/store.dart';
import '../map/cluster.dart';
import '../map/geo_math.dart';
import '../map/location_service.dart';
import '../map/map_widgets.dart';
import '../map/models.dart';
import '../map/tiles.dart';
import '../map/viewport.dart';
import '../widgets/common.dart';
import 'map_search.dart';
import 'search.dart';
import 'trip.dart';

enum _Sheet { trips, place, route }

class MapExploreScreen extends StatefulWidget {
  /// مدينة نبلّش عندها (اختياري)، وفلتر وجهة ويوم
  final String? focusCity;
  final String? to;
  final int? day;
  const MapExploreScreen({super.key, this.focusCity, this.to, this.day});
  @override
  State<MapExploreScreen> createState() => _MapExploreScreenState();
}

class _MapExploreScreenState extends State<MapExploreScreen> with TickerProviderStateMixin {
  final _map = MapController();
  late final _anim = MapAnimator(_map, this);
  final _loc = LocationService.i;
  final _sheetCtl = DraggableScrollableController();
  late final _loader = ViewportLoader<MapTrip>((area, f) => Store.i.mapTrips(area, f, me: _loc.point));

  late MapFilter _filter = MapFilter(day: widget.day, to: widget.to);
  List<MapTrip> _trips = const [];
  List<Cluster<MapTrip>> _clusters = const [];
  double _clusterZ = -1;
  bool _loading = false;
  Object? _error;
  bool _ready = false;
  bool _outside = false;
  double _zoom = 7, _rotation = 0;
  bool _following = false;

  // الطبقات
  bool _showTrips = true, _showCities = true, _showHeat = false, _showSaved = true;
  List<CityActivity> _activity = const [];

  // الورقة السفلية
  _Sheet _mode = _Sheet.trips;
  String? _selected; // MapTrip.id
  List<MapTrip>? _group; // مجموعة مختارة
  String? _groupTitle;
  GeoPlace? _picked;
  bool _reversing = false;
  List<RouteOption> _routes = const [];
  int _routeIdx = 0;
  bool _routing = false;
  GeoPlace? _routeFrom, _routeDest;

  bool get _dark => Store.i.mapDark;
  static const _syriaCenter = LatLng(34.8, 38.3);

  @override
  void initState() {
    super.initState();
    _loc.addListener(_onLoc);
    Store.i.addListener(_onStore);
    unawaited(Store.i.loadMapPrefs());
    if (Store.i.signedIn) unawaited(Store.i.refreshPlaces().catchError((_) {}));
    if (_loc.status == LocStatus.idle && widget.focusCity == null) {
      _loc.locate().then((s) {
        if (!mounted) return;
        final p = _loc.point;
        if (s == LocStatus.ok && p != null && GeoBounds.syria.contains(p)) _anim.move(p, 11);
        _watch();
      });
    } else {
      _watch();
    }
  }

  bool _watching = false;
  void _watch() {
    if (_watching || _loc.status != LocStatus.ok) return;
    _watching = true;
    _loc.watch();
  }

  @override
  void dispose() {
    _loc.removeListener(_onLoc);
    Store.i.removeListener(_onStore);
    if (_watching) _loc.unwatch();
    _loader.dispose();
    _anim.dispose();
    _sheetCtl.dispose();
    super.dispose();
  }

  void _onLoc() {
    if (!mounted) return;
    setState(() {});
    final p = _loc.point;
    if (_following && p != null) _map.move(p, _zoom);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  LatLng get _initialCenter {
    final c = widget.focusCity == null ? null : geo[widget.focusCity];
    if (c != null) return LatLng(c.$1, c.$2);
    final p = _loc.point;
    if (p != null && GeoBounds.syria.contains(p)) return p;
    return _syriaCenter;
  }

  double get _initialZoom => widget.focusCity != null ? 10 : (_loc.point != null && GeoBounds.syria.contains(_loc.point!) ? 11 : 6.6);

  // ── تحميل حسب حدود الخريطة ───────────────────────────────────────
  void _onCamera(MapCamera cam, bool gesture) {
    // ممكن تنادى وقت البناء (أول مرة): منأجّل لبعد الإطار
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onCamera(cam, gesture);
      });
      return;
    }
    _zoom = cam.zoom;
    if (gesture && _following) _following = false;
    if (cam.rotation != _rotation) setState(() => _rotation = cam.rotation);
    final cz = clusterZoom(cam.zoom);
    if (cz != _clusterZ) _recluster(cz);
    _requestView(cam);
  }

  GeoBounds? _viewOf(MapCamera cam) {
    final b = cam.visibleBounds;
    return GeoBounds(b.south, b.west, b.north, b.east).intersect(GeoBounds.syria);
  }

  void _requestView(MapCamera cam, {bool now = false}) {
    if (!_showTrips) return;
    final view = _viewOf(cam);
    final outside = view == null;
    if (outside != _outside) setState(() => _outside = outside);
    if (view == null) return;
    void onResult(ViewportResult<MapTrip> r) {
      if (!mounted) return;
      setState(() {
        _trips = r.items;
        _loading = false;
        _error = null;
        _recluster(clusterZoom(_zoom), notify: false);
        if (_selected != null && !_trips.any((t) => t.id == _selected)) _selected = null;
      });
    }

    void onError(Object e) {
      if (mounted) setState(() => (_loading = false, _error = e));
    }

    void onLoading() {
      if (mounted) setState(() => _loading = true);
    }

    if (now) {
      _loader.load(view, _filter, onResult, onError: onError, onLoading: onLoading);
    } else {
      _loader.request(view, _filter, onResult, onError: onError, onLoading: onLoading);
    }
  }

  void _reload() {
    _loader.invalidate();
    try {
      _requestView(_map.camera, now: true);
    } catch (_) {}
  }

  void _recluster(double cz, {bool notify = true}) {
    _clusterZ = cz;
    final c = clusterize<MapTrip>(_trips, (t) => t.point, cz);
    if (notify) {
      setState(() => _clusters = c);
    } else {
      _clusters = c;
    }
  }

  // ── موقعي ────────────────────────────────────────────────────────
  Future<void> _locateMe() async {
    final p0 = _loc.point;
    if (_loc.status == LocStatus.ok && p0 != null) {
      _following = true;
      _anim.move(p0, _zoom < 13 ? 14 : _zoom, rotation: 0);
      return;
    }
    final s = await _loc.locate();
    if (!mounted) return;
    if (s == LocStatus.ok && _loc.point != null) {
      _watch();
      if (!GeoBounds.syria.contains(_loc.point!)) {
        toast(context, 'موقعك برّا سوريا، الرحلات جوّا سوريا بس');
        return;
      }
      _following = true;
      _anim.move(_loc.point!, 14);
      _reload();
    } else {
      _locationProblem(s);
    }
  }

  void _locationProblem(LocStatus s) {
    final settings = s == LocStatus.serviceOff || s == LocStatus.deniedForever;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(s == LocStatus.serviceOff ? Icons.location_disabled_rounded : Icons.location_off_rounded, size: 48, color: C.primary),
            const SizedBox(height: 10),
            Text(locMessage(s), style: T.h3, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            const Text('فيك تكمّل بلا موقع: حرّك الخريطة أو دوّر على مدينة.', style: T.body, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (settings)
              Btn(s == LocStatus.serviceOff ? 'افتح إعدادات الموقع' : 'افتح إعدادات التطبيق', icon: Icons.settings_rounded, onTap: () {
                Navigator.pop(c);
                _loc.openSettings();
              })
            else
              Btn('جرّب مرة تانية', icon: Icons.my_location_rounded, onTap: () {
                Navigator.pop(c);
                _locateMe();
              }),
            const SizedBox(height: 8),
            Btn('مو هلأ', kind: BtnKind.ghost, onTap: () => Navigator.pop(c)),
          ]),
        ),
      ),
    );
  }

  // ── التفاعل مع الخريطة ───────────────────────────────────────────
  void _tapCluster(Cluster<MapTrip> c) {
    final (sw, ne) = c.bounds((t) => t.point);
    final samePoint = (ne.latitude - sw.latitude).abs() < 1e-4 && (ne.longitude - sw.longitude).abs() < 1e-4;
    if (!samePoint && _zoom < 14) {
      _anim.fit(GeoBounds(sw.latitude, sw.longitude, ne.latitude, ne.longitude), padding: const EdgeInsets.fromLTRB(70, 160, 70, 260));
      return;
    }
    final items = List.of(c.items)..sort((a, b) => a.departure.compareTo(b.departure));
    setState(() {
      _mode = _Sheet.trips;
      _group = items;
      _groupTitle = 'من ${items.first.board}';
      _selected = null;
    });
    _expandSheet(.5);
  }

  void _tapTrip(MapTrip t) {
    setState(() {
      _mode = _Sheet.trips;
      _selected = t.id;
      _group = [t];
      _groupTitle = null;
    });
    _anim.move(t.point, _zoom < 11 ? 12 : _zoom);
    _expandSheet(.36);
  }

  void _expandSheet(double size) {
    if (!_sheetCtl.isAttached) return;
    _sheetCtl.animateTo(size, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  Future<void> _pick(LatLng p, {GeoPlace? known}) async {
    if (!GeoBounds.syria.contains(p)) {
      toast(context, 'اختار مكان جوّا سوريا');
      return;
    }
    setState(() {
      _mode = _Sheet.place;
      _picked = known ?? GeoPlace(name: 'نقطة على الخريطة', point: p);
      _reversing = known == null;
      _selected = null;
      _routes = const [];
    });
    _expandSheet(.34);
    if (known != null) return;
    GeoPlace? r;
    try {
      r = await Store.i.reverseGeocode(p);
    } catch (_) {
      // بلا نت أو المزود ما رد: منكمّل بأقرب مدينة
    }
    try {
      final c = await Store.i.nearestCity(p);
      r ??= c == null ? null : GeoPlace(name: 'قرب ${c.$1}', label: '${fmtKm(c.$2)} عن المركز', point: p, city: c.$1);
      if (r != null && r.city == null && c != null) r = GeoPlace(name: r.name, label: r.label, point: r.point, kind: r.kind, city: c.$1);
    } catch (_) {}
    if (!mounted || _picked?.point != p) return;
    setState(() {
      _reversing = false;
      if (r != null) _picked = GeoPlace(name: r.name, label: r.label, point: p, kind: r.kind, city: r.city);
    });
  }

  Future<void> _openSearch() async {
    // البحث بيتحيّز للمنطقة الظاهرة (إذا مكبّرة)، وإلا لموقعي
    LatLng? near = _loc.point;
    try {
      if (_ready && _zoom >= 9) near = _map.camera.center;
    } catch (_) {}
    final res = await Navigator.of(context).push<GeoPlace>(MaterialPageRoute(builder: (_) => MapSearchScreen(near: near)));
    if (res == null || !mounted) return;
    Store.i.addRecentPlace(res);
    _anim.move(res.point, res.kind == PlaceKind.city ? 11.5 : 15);
    _pick(res.point, known: res);
  }

  // ── المسارات ──────────────────────────────────────────────────────
  Future<void> _routeTo(GeoPlace dest) async {
    final me = _loc.point;
    final from = _routeFrom ?? (me != null && GeoBounds.syria.contains(me) ? GeoPlace(name: 'موقعي', point: me) : null);
    if (from == null) {
      // بلا موقع: نقطة البداية هي النقطة المختارة، والوجهة لازم تتحدد بعدين
      setState(() => _routeFrom = dest);
      toast(context, 'اضغط مطوّلاً على الوجهة أو دوّر عليها');
      return;
    }
    setState(() {
      _mode = _Sheet.route;
      _routing = true;
      _routeDest = dest;
      _routes = const [];
      _routeIdx = 0;
    });
    _expandSheet(.32);
    try {
      final r = await Store.i.route([from.point, dest.point]);
      if (!mounted) return;
      setState(() {
        _routes = r;
        _routing = false;
        _routeFrom = from;
      });
      _anim.fit(boundsOf([for (final o in r) ...o.line]), padding: const EdgeInsets.fromLTRB(50, 170, 50, 300));
    } catch (e) {
      if (!mounted) return;
      setState(() => _routing = false);
      toast(context, AppException.from(e).message);
    }
  }

  void _clearRoute() => setState(() {
        _routes = const [];
        _routeFrom = null;
        _routeDest = null;
        _mode = _picked == null ? _Sheet.trips : _Sheet.place;
      });

  Future<void> _searchTripsOnRoute() async {
    final a = _routeFrom, b = _routeDest;
    if (a == null || b == null) return;
    final ca = await Store.i.nearestCity(a.point), cb = await Store.i.nearestCity(b.point);
    if (!mounted || ca == null || cb == null) return;
    if (ca.$1 == cb.$1) {
      toast(context, 'النقطتين بنفس المدينة (${ca.$1})، مشوار للسفر بين المدن');
      return;
    }
    go(context, ResultsScreen(from: ca.$1, to: cb.$1, day: _filter.day ?? 1, pax: _filter.seats));
  }

  // ── الأماكن المحفوظة ─────────────────────────────────────────────
  Future<void> _savePicked() async {
    final p = _picked;
    if (p == null) return;
    if (!Store.i.signedIn) {
      toast(context, 'سجّل دخول لحتى تحفظ أماكنك');
      return;
    }
    final res = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _SavePlaceSheet(initial: p.kind == PlaceKind.address && !p.name.startsWith('قرب') ? p.name : ''),
    );
    if (res == null || !mounted) return;
    await attempt(context, () async {
      await Store.i.savePlace(res.$1, p.point, kind: res.$2, address: p.label.isEmpty ? p.name : p.label);
      if (mounted) toast(context, 'انحفظ "${res.$1}"');
    });
  }

  // ── الفلاتر والطبقات ─────────────────────────────────────────────
  void _setFilter(MapFilter f) {
    setState(() {
      _filter = f;
      _group = null;
      _selected = null;
    });
    _reload();
  }

  Future<void> _openFilters() async {
    final f = await showModalBottomSheet<MapFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _FilterSheet(_filter),
    );
    if (f != null) _setFilter(f);
  }

  Future<void> _openLayers() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          Widget sw(String t, IconData i, bool v, ValueChanged<bool> on) => SwitchListTile(
                value: v,
                onChanged: (x) {
                  on(x);
                  set(() {});
                  setState(() {});
                },
                secondary: Icon(i, color: C.dark),
                title: Text(t, style: T.label),
                activeColor: C.primary,
              );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 8), child: Align(alignment: AlignmentDirectional.centerStart, child: Text('طبقات الخريطة', style: T.h3))),
                sw('الرحلات', Icons.directions_car_filled_rounded, _showTrips, (v) {
                  _showTrips = v;
                  if (v) _reload();
                }),
                sw('أسماء المدن', Icons.location_city_rounded, _showCities, (v) => _showCities = v),
                sw('نشاط المدن (الأكثر رحلات)', Icons.local_fire_department_rounded, _showHeat, (v) {
                  _showHeat = v;
                  if (v && _activity.isEmpty) {
                    Store.i.cityActivity().then((a) {
                      if (mounted) setState(() => _activity = a);
                    }).catchError((_) {});
                  }
                }),
                sw('أماكني المحفوظة', Icons.star_rounded, _showSaved, (v) => _showSaved = v),
                sw('الوضع الداكن', Icons.dark_mode_rounded, _dark, Store.i.setMapDark),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── البناء ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final me = _loc.point;
    final routeSel = _routes.isEmpty ? null : _routes[_routeIdx.clamp(0, _routes.length - 1)];
    return Scaffold(
      backgroundColor: _dark ? const Color(0xFF0E1A1D) : const Color(0xFFE8EEEE),
      body: Stack(children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              minZoom: 5.5,
              maxZoom: MapTiles.maxZoom,
              cameraConstraint: CameraConstraint.containCenter(bounds: LatLngBounds(const LatLng(30.5, 33.5), const LatLng(39.0, 44.5))),
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all, rotationThreshold: 25),
              onMapReady: () => WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => _ready = true);
                _recluster(clusterZoom(_map.camera.zoom));
                _requestView(_map.camera, now: true);
              }),
              onPositionChanged: (cam, gesture) => _onCamera(cam, gesture),
              onTap: (_, __) {
                if (_selected != null || _mode != _Sheet.trips || _group != null) {
                  setState(() {
                    _selected = null;
                    _group = null;
                    if (_routes.isEmpty) {
                      _mode = _Sheet.trips;
                      _picked = null;
                    }
                  });
                }
              },
              onLongPress: (_, p) => _pick(p),
            ),
            children: [
              mishwarTiles(dark: _dark),
              if (_showHeat && _activity.isNotEmpty)
                CircleLayer(circles: [
                  for (final a in _activity)
                    CircleMarker(
                      point: a.point,
                      radius: 6000 + a.departures.clamp(1, 60) * 900.0,
                      useRadiusInMeter: true,
                      color: C.yellow.withValues(alpha: .28),
                      borderColor: C.star.withValues(alpha: .5),
                      borderStrokeWidth: 1,
                    ),
                ]),
              if (_routes.isNotEmpty)
                PolylineLayer(polylines: [
                  for (var i = 0; i < _routes.length; i++)
                    if (i != _routeIdx) Polyline(points: _routes[i].line, strokeWidth: 6, color: (_dark ? Colors.white : C.muted).withValues(alpha: .55), pattern: _routes[i].approximate ? StrokePattern.dashed(segments: const [10, 8]) : const StrokePattern.solid()),
                  if (routeSel != null) ...[
                    Polyline(points: routeSel.line, strokeWidth: 10, color: C.dark.withValues(alpha: .35)),
                    Polyline(points: routeSel.line, strokeWidth: 6, color: C.primary, pattern: routeSel.approximate ? StrokePattern.dashed(segments: const [12, 8]) : const StrokePattern.solid()),
                  ],
                ]),
              if (me != null && (_loc.accuracy ?? 0) > 15) CircleLayer(circles: [accuracyCircle(me, _loc.accuracy!)]),
              if (_showCities && _zoom < 9.5)
                MarkerLayer(rotate: true, markers: [
                  for (final e in geo.entries)
                    Marker(point: LatLng(e.value.$1, e.value.$2), width: 90, height: 22, alignment: Alignment.bottomCenter, child: IgnorePointer(child: CityLabel(e.key, dark: _dark))),
                ]),
              if (_showSaved && Store.i.savedPlaces.isNotEmpty)
                MarkerLayer(rotate: true, markers: [
                  for (final s in Store.i.savedPlaces)
                    Marker(
                      point: s.point,
                      width: 120,
                      height: 52,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => _pick(s.point, known: s.asPlace),
                        child: PlacePin(icon: s.kind == 'home' ? Icons.home_rounded : s.kind == 'work' ? Icons.work_rounded : Icons.star_rounded, color: C.star, label: _zoom > 12 ? s.label : null),
                      ),
                    ),
                ]),
              if (_showTrips)
                MarkerLayer(rotate: true, markers: [
                  for (final c in _clusters)
                    if (c.single)
                      Marker(
                        key: ValueKey(c.items.first.id),
                        point: c.point,
                        width: 92,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: GestureDetector(onTap: () => _tapTrip(c.items.first), child: Center(child: TripPin(c.items.first, selected: c.items.first.id == _selected))),
                      )
                    else
                      Marker(
                        point: c.point,
                        width: ClusterBubble.sizeFor(c.size),
                        height: ClusterBubble.sizeFor(c.size),
                        child: GestureDetector(onTap: () => _tapCluster(c), child: ClusterBubble(c.size)),
                      ),
                ]),
              MarkerLayer(markers: [
                if (_picked != null) Marker(point: _picked!.point, width: 40, height: 44, alignment: Alignment.topCenter, child: const PlacePin(icon: Icons.place_rounded, color: C.dark)),
                if (_routeFrom != null && _routes.isNotEmpty && _routeFrom!.name != 'موقعي') Marker(point: _routeFrom!.point, width: 40, height: 44, alignment: Alignment.topCenter, child: const PlacePin(icon: Icons.trip_origin_rounded, color: C.primary)),
                if (me != null) Marker(point: me, width: 64, height: 64, child: MeDot(heading: _loc.heading, mapRotation: _rotation, weak: _loc.weak)),
              ]),
              RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                showFlutterMapAttribution: false,
                attributions: [TextSourceAttribution(MapTiles.attribution)],
              ),
            ],
          ),
        ),
        _topBar(),
        _fabs(),
        _sheet(),
      ]),
    );
  }

  Widget _topBar() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              MapFab(Icons.arrow_forward_rounded, tooltip: 'رجوع', dark: _dark, onTap: () => Navigator.maybePop(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'دوّر على مدينة أو مكان',
                  child: Press(
                    onTap: _openSearch,
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: _dark ? const Color(0xFF15262B) : Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .15), blurRadius: 10, offset: const Offset(0, 3))]),
                      child: Row(children: [
                        const Icon(Icons.search_rounded, color: C.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_picked?.name ?? 'وين بدك تروح؟', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: kFont, fontSize: 15, color: _picked == null ? C.muted : (_dark ? Colors.white : C.dark)))),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              MapFab(Icons.layers_rounded, tooltip: 'طبقات الخريطة', dark: _dark, onTap: _openLayers),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                _chip(_filter.active > 0 ? 'فلاتر · ${_filter.active}' : 'فلاتر', Icons.tune_rounded, _filter.active > 0, _openFilters),
                _chip('اليوم', null, _filter.day == 0, () => _setFilter(_filter.copyWith(day: _filter.day == 0 ? null : 0))),
                _chip('بكرا', null, _filter.day == 1, () => _setFilter(_filter.copyWith(day: _filter.day == 1 ? null : 1))),
                _chip('حجز فوري', Icons.bolt_rounded, _filter.instantOnly, () => _setFilter(_filter.copyWith(instantOnly: !_filter.instantOnly))),
                if (_filter.to != null) _chip('لـ ${_filter.to} ✕', Icons.flag_rounded, true, () => _setFilter(_filter.copyWith(to: null))),
              ]),
            ),
            if (_outside || _error != null || !Store.i.live) const SizedBox(height: 8),
            if (_outside)
              _banner(Icons.travel_explore_rounded, 'الرحلات جوّا سوريا بس، رجّع الخريطة لسوريا', C.tint, C.dark)
            else if (_error != null)
              _banner(AppException.from(_error!).code == 'NETWORK' ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
                  AppException.from(_error!).code == 'NETWORK' ? 'ما في نت، عم نعرض آخر نتائج' : AppException.from(_error!).message, C.warnBg, C.warn, onRetry: _reload)
            else if (!Store.i.live)
              _banner(Icons.science_outlined, 'نسخة تجريبية: الرحلات على الخريطة للتجربة', C.warnBg, C.warn),
          ]),
        ),
      );

  Widget _chip(String label, IconData? icon, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Press(
          onTap: tap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: on ? C.dark : (_dark ? const Color(0xFF15262B) : Colors.white),
              borderRadius: BorderRadius.circular(19),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 16, color: on ? C.yellow : C.primary), const SizedBox(width: 4)],
              Text(label, style: TextStyle(fontFamily: kFont, fontSize: 13.5, color: on ? Colors.white : (_dark ? Colors.white : C.dark))),
            ]),
          ),
        ),
      );

  Widget _banner(IconData icon, String text, Color bg, Color fg, {VoidCallback? onRetry}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: kFont, fontSize: 12.5, color: fg))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: Text('حدّث', style: TextStyle(fontFamily: kFont, color: fg))),
        ]),
      );

  Widget _fabs() => Positioned(
        left: 12,
        bottom: MediaQuery.of(context).size.height * .30 + 12,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_rotation.abs() > 1) ...[
            MapFab(Icons.navigation_rounded, tooltip: 'رجّع الشمال لفوق', dark: _dark, onTap: () => _anim.move(_map.camera.center, _zoom, rotation: 0),
                child: Transform.rotate(angle: _rotation * 3.14159 / 180, child: const Icon(Icons.navigation_rounded, color: C.sos))),
            const SizedBox(height: 10),
          ],
          MapFab(Icons.add_rounded, tooltip: 'تكبير', dark: _dark, onTap: _ready ? () => _anim.move(_map.camera.center, (_zoom + 1).clamp(5.5, MapTiles.maxZoom), duration: const Duration(milliseconds: 250)) : null),
          const SizedBox(height: 8),
          MapFab(Icons.remove_rounded, tooltip: 'تصغير', dark: _dark, onTap: _ready ? () => _anim.move(_map.camera.center, (_zoom - 1).clamp(5.5, MapTiles.maxZoom), duration: const Duration(milliseconds: 250)) : null),
          const SizedBox(height: 14),
          MapFab(
            _loc.status == LocStatus.ok ? (_following ? Icons.my_location_rounded : Icons.location_searching_rounded) : Icons.location_disabled_rounded,
            tooltip: 'موقعي',
            dark: _dark,
            active: _following,
            busy: _loc.status == LocStatus.searching,
            onTap: _locateMe,
          ),
        ]),
      );

  // ── الورقة السفلية ───────────────────────────────────────────────
  Widget _sheet() => DraggableScrollableSheet(
        controller: _sheetCtl,
        initialChildSize: .3,
        minChildSize: .14,
        maxChildSize: .88,
        snap: true,
        snapSizes: const [.14, .3, .5],
        builder: (context, scroll) => Container(
          decoration: BoxDecoration(
            color: C.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 18, offset: const Offset(0, -4))],
          ),
          child: CustomScrollView(controller: scroll, slivers: [
            SliverToBoxAdapter(
              child: Column(children: [
                const SizedBox(height: 8),
                Container(width: 44, height: 5, decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(3))),
                if (_loading) const Padding(padding: EdgeInsets.fromLTRB(40, 8, 40, 0), child: LinearProgressIndicator(minHeight: 3, color: C.primary, backgroundColor: C.tint)),
                const SizedBox(height: 10),
              ]),
            ),
            ...switch (_mode) {
              _Sheet.place => _placeSlivers(),
              _Sheet.route => _routeSlivers(),
              _Sheet.trips => _tripSlivers(),
            },
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]),
        ),
      );

  List<Widget> _tripSlivers() {
    final list = _group ?? _trips;
    final title = _group != null
        ? (_groupTitle == null ? 'الرحلة المختارة' : '${tripsLabel(list.length)} ${_groupTitle!}')
        : _loading && _trips.isEmpty
            ? 'عم ندوّر...'
            : '${tripsLabel(list.length)} بهالمنطقة';
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Row(children: [
            Expanded(child: Text(title, style: T.h3, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (_group != null)
              TextButton(onPressed: () => setState(() => (_group = null, _selected = null)), child: const Text('كل الرحلات', style: TextStyle(fontFamily: kFont, color: C.primary)))
            else if (_loc.point != null && list.isNotEmpty)
              const Text('الأقرب أول', style: T.small),
          ]),
        ),
      ),
      if (list.isEmpty && !_loading)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
            child: Column(children: [
              const Icon(Icons.explore_off_rounded, size: 40, color: C.muted),
              const SizedBox(height: 6),
              Text(_filter.active > 0 ? 'ما في رحلات بهالفلاتر هون. جرّب تشيل فلتر أو صغّر الخريطة.' : 'ما في رحلات طالعة من هالمنطقة. صغّر الخريطة لتشوف مدن تانية.', style: T.body, textAlign: TextAlign.center),
              if (_filter.active > 0) TextButton(onPressed: () => _setFilter(const MapFilter()), child: const Text('شيل كل الفلاتر', style: TextStyle(fontFamily: kFont, color: C.primary))),
            ]),
          ),
        ),
      SliverList.builder(
        itemCount: list.length.clamp(0, 60),
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: MapTripTile(list[i], selected: list[i].id == _selected, onTap: () => _tapTrip(list[i]), onOpen: () => _openTrip(list[i])),
        ),
      ),
      if (list.length > 60)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(12), child: Text('كبّر الخريطة لتشوف باقي الرحلات', style: T.small, textAlign: TextAlign.center))),
    ];
  }

  Future<void> _openTrip(MapTrip m) async {
    await attempt(context, () async {
      final t = await Store.i.tripOf(m);
      if (!mounted) return;
      if (t == null) {
        toast(context, 'الرحلة ما عادت متاحة');
        _reload();
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripDetailsScreen(t, pax: _filter.seats)));
      // ممكن انحجز شي: منحدّث المقاعد على الخريطة
      if (mounted) _reload();
    });
  }

  List<Widget> _placeSlivers() {
    final p = _picked;
    if (p == null) return const [];
    final me = _loc.point;
    final dist = me == null ? null : kmBetween(me, p.point);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(14)),
                child: Icon(p.kind == PlaceKind.city ? Icons.location_city_rounded : p.kind == PlaceKind.saved ? Icons.star_rounded : Icons.place_rounded, color: C.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_reversing ? 'عم نجيب العنوان...' : p.name, style: T.h3, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (p.label.isNotEmpty || dist != null)
                    Text([if (p.label.isNotEmpty) p.label, if (dist != null) '${fmtKm(dist)} عنك'].join(' · '), style: T.small, maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
              IconButton(tooltip: 'سكّر', onPressed: () => setState(() => (_picked = null, _mode = _Sheet.trips)), icon: const Icon(Icons.close_rounded, color: C.muted)),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _action(Icons.near_me_rounded, 'رحلات من هون', () => _tripsFrom(p)),
              if (p.city != null || p.kind == PlaceKind.city) _action(Icons.flag_rounded, 'رحلات لـ ${p.city ?? p.name}', () => _setFilter(_filter.copyWith(to: p.city ?? p.name))),
              _action(Icons.alt_route_rounded, _routeFrom != null && _routeFrom!.name != 'موقعي' ? 'المسار من ${_routeFrom!.name} لهون' : 'المسار لهون', () => _routeTo(p)),
              _action(Icons.trip_origin_rounded, 'ابدأ المسار من هون', () {
                setState(() => _routeFrom = p);
                toast(context, 'تمام، هلأ اختار الوجهة (ضغطة مطوّلة أو بحث)');
              }),
              if (p.kind != PlaceKind.saved) _action(Icons.star_border_rounded, 'احفظ المكان', _savePicked),
              if (p.kind == PlaceKind.saved) _action(Icons.delete_outline_rounded, 'احذف من أماكني', () => _deleteSaved(p)),
            ]),
          ]),
        ),
      ),
    ];
  }

  Future<void> _deleteSaved(GeoPlace p) async {
    final s = Store.i.savedPlaces.where((e) => e.label == p.name && kmBetween(e.point, p.point) < .01).firstOrNull;
    if (s == null) return;
    final ok = await attempt(context, () => Store.i.deletePlace(s));
    if (ok && mounted) setState(() => (_picked = null, _mode = _Sheet.trips));
  }

  Future<void> _tripsFrom(GeoPlace p) async {
    setState(() {
      _loading = true;
      _mode = _Sheet.trips;
    });
    try {
      final list = await Store.i.tripsNear(p.point, 25, _filter);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _group = list;
        _groupTitle = 'قريبة من ${p.name}';
      });
      if (list.isNotEmpty) _anim.fit(boundsOf([p.point, ...list.map((t) => t.point)]), padding: const EdgeInsets.fromLTRB(60, 170, 60, 320));
      _expandSheet(.5);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, AppException.from(e).message);
    }
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) => Press(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: C.primary),
            const SizedBox(width: 6),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label)),
          ]),
        ),
      );

  List<Widget> _routeSlivers() => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${_routeFrom?.name ?? ''} ← ${_routeDest?.name ?? ''}', style: T.h3, maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(tooltip: 'سكّر المسار', onPressed: _clearRoute, icon: const Icon(Icons.close_rounded, color: C.muted)),
              ]),
              const SizedBox(height: 8),
              if (_routing)
                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: C.primary)))
              else ...[
                for (var i = 0; i < _routes.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CardBox(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      color: i == _routeIdx ? C.tint : Colors.white,
                      onTap: () => setState(() => _routeIdx = i),
                      child: Row(children: [
                        Icon(i == _routeIdx ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: C.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(fmtSeconds(_routes[i].seconds), style: T.h3),
                            Text([fmtKm(_routes[i].km), if (i == 0 && _routes.length > 1) 'الأسرع', if (_routes[i].summary.isNotEmpty && !_routes[i].approximate) _routes[i].summary].join(' · '),
                                style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                if (_routes.any((r) => r.approximate))
                  const InfoNote('المسار تقريبي (خط مباشر): خدمة الطرق مو متاحة هلأ. المسافة والوقت تقدير.'),
                const SizedBox(height: 6),
                Btn('دوّر على رحلة بهالطريق', icon: Icons.search_rounded, onTap: _searchTripsOnRoute),
              ],
            ]),
          ),
        ),
      ];
}

/// بطاقة رحلة بالقائمة تحت الخريطة.
class MapTripTile extends StatelessWidget {
  final MapTrip t;
  final bool selected;
  final VoidCallback onTap, onOpen;
  const MapTripTile(this.t, {super.key, this.selected = false, required this.onTap, required this.onOpen});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'رحلة ${t.board} لـ ${t.to} الساعة ${hmDamascus(t.departure)}',
        child: Press(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? C.primary : Colors.transparent, width: 2),
            ),
            child: Row(children: [
              Column(children: [
                Text(hmDamascus(t.departure), style: T.h3),
                Text(dayLabel(dayOffset(t.departure)), style: T.small, maxLines: 1),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${t.board} ← ${t.to}', style: T.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [
                      t.driver,
                      if (t.rating > 0) '★ ${t.rating.toStringAsFixed(1)}',
                      seatsLabel(t.seats),
                      if (t.distanceKm != null) '${fmtKm(t.distanceKm!)} عنك',
                      if (t.exact) 'نقطة تجمع محددة',
                    ].join(' · '),
                    style: T.small,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmtPriceShort(t.price), style: const TextStyle(fontFamily: kFont, fontSize: 16, color: C.primary)),
                const SizedBox(height: 4),
                Press(
                  onTap: onOpen,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(10)),
                    child: const Text('التفاصيل', style: TextStyle(fontFamily: kFont, fontSize: 12, color: Colors.white)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      );
}

class _FilterSheet extends StatefulWidget {
  final MapFilter initial;
  const _FilterSheet(this.initial);
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late MapFilter f = widget.initial;
  static const _prices = [null, 30000, 50000, 80000];
  static const _days = [null, 0, 1, 2];

  @override
  Widget build(BuildContext context) {
    final female = Store.i.female;
    final kinds = [female ? RideKind.women : RideKind.men, RideKind.family];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('فلترة الرحلات', style: T.h2),
            const SizedBox(height: 14),
            const Text('اليوم', style: T.label),
            const SizedBox(height: 8),
            ChipGroup(
              options: [for (final d in _days) d == null ? 'كل الأيام' : dayLabel(d)],
              selected: {_days.indexOf(f.day).clamp(0, _days.length - 1)},
              onTap: (i) => setState(() => f = f.copyWith(day: _days[i])),
            ),
            const SizedBox(height: 16),
            const Text('نوع الرحلة', style: T.label),
            const SizedBox(height: 8),
            ChipGroup(
              options: [for (final k in kinds) k == RideKind.women ? 'نسائية' : k == RideKind.family ? 'عائلية' : 'عادية'],
              selected: {for (var i = 0; i < kinds.length; i++) if (f.kinds.contains(kinds[i])) i},
              onTap: (i) => setState(() {
                final s = Set.of(f.kinds);
                s.contains(kinds[i]) ? s.remove(kinds[i]) : s.add(kinds[i]);
                f = f.copyWith(kinds: s);
              }),
            ),
            const SizedBox(height: 16),
            const Text('أعلى سعر', style: T.label),
            const SizedBox(height: 8),
            ChipGroup(
              options: [for (final p in _prices) p == null ? 'أي سعر' : 'لحد ${fmtPriceShort(p)}'],
              selected: {_prices.indexOf(f.maxPrice).clamp(0, _prices.length - 1)},
              onTap: (i) => setState(() => f = f.copyWith(maxPrice: _prices[i])),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(child: Text('عدد الركاب', style: T.label)),
              Counter(value: f.seats, min: 1, max: 4, onChanged: (v) => setState(() => f = f.copyWith(seats: v))),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: f.instantOnly,
              activeColor: C.primary,
              onChanged: (v) => setState(() => f = f.copyWith(instantOnly: v)),
              title: const Text('حجز فوري بس', style: T.label),
              subtitle: const Text('بلا انتظار موافقة السائق', style: T.small),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Btn('مسح', kind: BtnKind.outline, onTap: () => Navigator.pop(context, const MapFilter()))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: Btn('طبّق', onTap: () => Navigator.pop(context, f))),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _SavePlaceSheet extends StatefulWidget {
  final String initial;
  const _SavePlaceSheet({required this.initial});
  @override
  State<_SavePlaceSheet> createState() => _SavePlaceSheetState();
}

class _SavePlaceSheetState extends State<_SavePlaceSheet> {
  late final _ctl = TextEditingController(text: widget.initial);
  String _kind = 'other';
  static const _kinds = ['home', 'work', 'other'];
  static const _labels = ['البيت', 'الشغل', 'غير شي'];

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('احفظ المكان', style: T.h2),
            const SizedBox(height: 12),
            ChipGroup(
              options: _labels,
              selected: {_kinds.indexOf(_kind)},
              onTap: (i) => setState(() {
                _kind = _kinds[i];
                if (i < 2) _ctl.text = _labels[i];
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctl,
              maxLength: 40,
              textInputAction: TextInputAction.done,
              style: T.label,
              decoration: InputDecoration(
                hintText: 'اسم المكان (مثلاً: بيت أهلي)',
                hintStyle: T.small,
                filled: true,
                fillColor: C.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder(
              valueListenable: _ctl,
              builder: (_, v, __) => Btn('احفظ', icon: Icons.star_rounded, onTap: v.text.trim().isEmpty ? null : () => Navigator.pop(context, (v.text.trim(), _kind))),
            ),
          ]),
        ),
      );
}
