// البحث الجغرافي: مدن ونقاط تجمع وأماكني (فوري ومحلي)، وعناوين من مزود الخرائط
// (بعد ما يوقف الكتابة شوي)، وآخر عمليات البحث.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../core/theme.dart';
import '../data/store.dart';
import '../map/geo_math.dart';
import '../map/models.dart';
import '../widgets/common.dart';

class MapSearchScreen extends StatefulWidget {
  final LatLng? near;
  final String title;
  const MapSearchScreen({super.key, this.near, this.title = 'دوّر على مكان'});
  @override
  State<MapSearchScreen> createState() => _MapSearchScreenState();
}

class _MapSearchScreenState extends State<MapSearchScreen> {
  final _ctl = TextEditingController();
  Timer? _localT, _remoteT;
  int _seq = 0;
  List<GeoPlace> _local = const [];
  List<GeoPlace> _remote = const [];
  bool _remoteBusy = false;
  String? _remoteError;

  @override
  void initState() {
    super.initState();
    Store.i.loadMapPrefs();
    _searchLocal('');
  }

  @override
  void dispose() {
    _localT?.cancel();
    _remoteT?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    setState(() {});
    _localT?.cancel();
    _remoteT?.cancel();
    _localT = Timer(const Duration(milliseconds: 150), () => _searchLocal(q));
    if (q.trim().length >= 3) {
      _remoteT = Timer(const Duration(milliseconds: 550), () => _searchRemote(q));
    } else {
      setState(() => (_remote = const [], _remoteBusy = false, _remoteError = null));
    }
  }

  Future<void> _searchLocal(String q) async {
    final seq = ++_seq;
    try {
      final r = await Store.i.searchPlaces(q, near: widget.near);
      if (mounted && seq == _seq) setState(() => _local = r);
    } catch (_) {
      // بلا نت: منبحث بالمدن المحفوظة بالتطبيق
      if (!mounted || seq != _seq) return;
      setState(() => _local = [
            for (final c in searchCities(q))
              if (geo[c.name] != null) GeoPlace(name: c.name, label: c.sub, point: LatLng(geo[c.name]!.$1, geo[c.name]!.$2), kind: PlaceKind.city, city: c.name),
          ]);
    }
  }

  Future<void> _searchRemote(String q) async {
    final seq = _seq;
    setState(() => (_remoteBusy = true, _remoteError = null));
    try {
      final r = await Store.i.geocodeSuggest(q, near: widget.near);
      if (!mounted || seq != _seq) return;
      // ما منكرر شي موجود بالنتائج المحلية
      final names = _local.map((p) => norm(p.name)).toSet();
      setState(() => (_remote = r.where((p) => !names.contains(norm(p.name))).toList(), _remoteBusy = false));
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => (_remote = const [], _remoteBusy = false, _remoteError = 'ما قدرنا نجيب عناوين هلأ'));
    }
  }

  void _choose(GeoPlace p) => Navigator.pop(context, p);

  @override
  Widget build(BuildContext context) {
    final q = _ctl.text.trim();
    final recent = q.isEmpty ? Store.i.recentPlaces : const <GeoPlace>[];
    final saved = q.isEmpty ? Store.i.savedPlaces.map((s) => s.asPlace).toList() : const <GeoPlace>[];
    final local = q.isEmpty ? _local.where((p) => p.kind != PlaceKind.saved).take(8).toList() : _local;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: TopBar(title: widget.title),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: TextField(
            controller: _ctl,
            autofocus: true,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              final all = [..._local, ..._remote];
              if (all.isNotEmpty) _choose(all.first);
            },
            style: T.label,
            decoration: InputDecoration(
              hintText: 'مدينة، كراج، حي أو عنوان',
              hintStyle: T.small,
              prefixIcon: const Icon(Icons.search_rounded, color: C.primary),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'امسح',
                      icon: const Icon(Icons.close_rounded, color: C.muted),
                      onPressed: () {
                        _ctl.clear();
                        _onChanged('');
                      }),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            if (saved.isNotEmpty) ...[
              _head('أماكني'),
              for (final p in saved) _tile(p),
            ],
            if (recent.isNotEmpty) ...[
              Row(children: [
                Expanded(child: _head('آخر عمليات البحث')),
                TextButton(onPressed: () => setState(Store.i.clearRecentPlaces), child: const Text('امسح', style: TextStyle(fontFamily: kFont, color: C.primary))),
              ]),
              for (final p in recent) _tile(p, icon: Icons.history_rounded),
            ],
            if (local.isNotEmpty) ...[
              _head(q.isEmpty ? (widget.near != null ? 'مدن قريبة منك' : 'مدن') : 'مدن ونقاط تجمع'),
              for (final p in local) _tile(p),
            ],
            if (q.length >= 3) ...[
              _head('عناوين'),
              if (_remoteBusy) const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: C.primary)))),
              if (_remoteError != null) Padding(padding: const EdgeInsets.all(8), child: Text(_remoteError!, style: T.small)),
              if (!_remoteBusy && _remoteError == null && _remote.isEmpty)
                Padding(padding: const EdgeInsets.all(8), child: Text(Store.i.live ? 'ما لقينا عناوين بهالاسم' : 'البحث بالعناوين بيشتغل بالنسخة الحقيقية', style: T.small)),
              for (final p in _remote) _tile(p),
            ],
            if (q.isNotEmpty && local.isEmpty && _remote.isEmpty && !_remoteBusy && q.length < 3)
              const Padding(padding: EdgeInsets.all(16), child: Text('ما في نتائج، كمّل كتابة', style: T.body, textAlign: TextAlign.center)),
          ]),
        ),
      ]),
    );
  }

  Widget _head(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 6), child: Text(t, style: T.small));

  Widget _tile(GeoPlace p, {IconData? icon}) {
    final i = icon ??
        switch (p.kind) {
          PlaceKind.city => Icons.location_city_rounded,
          PlaceKind.garage => Icons.directions_bus_rounded,
          PlaceKind.meetingPoint => Icons.groups_rounded,
          PlaceKind.saved => Icons.star_rounded,
          PlaceKind.landmark => Icons.account_balance_rounded,
          PlaceKind.address => Icons.place_rounded,
        };
    final sub = [if (p.label.isNotEmpty) p.label, if (p.distanceKm != null) fmtKm(p.distanceKm!)].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => _choose(p),
        child: Row(children: [
          Icon(i, color: p.kind == PlaceKind.saved ? C.star : C.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: T.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (sub.isNotEmpty) Text(sub, style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}
