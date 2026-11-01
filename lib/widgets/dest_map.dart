import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../data/syria_map.dart';
import '../data/store.dart';
import 'common.dart';

class DestStat {
  final String id, city;
  final int trips;
  final int fromPrice;
  final String? tag;
  const DestStat(this.id, this.city, this.trips, this.fromPrice, [this.tag]);
}

/// إحصائيات الوجهات من نفس مصدر البحث، فالأرقام بتطابق النتائج.
List<DestStat> buildDestStats(String from, Map<String, (int, int)> raw) {
  final list = <DestStat>[
    for (final e in _cityIds.entries)
      if (e.key != from) DestStat(e.value, e.key, raw[e.key]?.$1 ?? 0, raw[e.key]?.$2 ?? suggestedPrice(from, e.key)),
  ];
  final withTrips = list.where((d) => d.trips > 0).toList();
  if (withTrips.isEmpty) return list;
  final most = withTrips.reduce((a, b) => a.trips >= b.trips ? a : b);
  final cheap = withTrips.reduce((a, b) => a.fromPrice <= b.fromPrice ? a : b);
  return [for (final d in list) DestStat(d.id, d.city, d.trips, d.fromPrice, d == most ? 'الأكتر رحلات' : d == cheap ? 'الأرخص' : null)];
}

const _cityIds = {'اللاذقية': 'latakia', 'جبلة': 'jableh', 'طرطوس': 'tartus', 'حمص': 'homs', 'حماة': 'hama', 'حلب': 'aleppo', 'دمشق': 'damascus', 'درعا': 'daraa'};
Offset _pos(String id) => mapCities.firstWhere((c) => c.id == id).pos;

/// خريطة سوريا مرسومة بالكود: فقاعات الرحلات، زوم بالإصبعين، وضغطة على مدينة بتقرّب عليها.
class DestinationsMap extends StatefulWidget {
  final String from;
  final int day;
  final ValueChanged<String> onSearch;
  const DestinationsMap({required this.from, this.day = 1, required this.onSearch});
  @override
  State<DestinationsMap> createState() => _DestinationsMapState();
}

class _DestinationsMapState extends State<DestinationsMap> with TickerProviderStateMixin {
  final _tc = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  Animation<Matrix4>? _mAnim;
  DestStat? _sel;
  Size _view = Size.zero;
  double _k = 1; // مقياس الخريطة داخل المساحة
  Map<String, (int, int)> _raw = const {};
  String _loadedKey = '';

  Future<void> _loadStats() async {
    final key = '${widget.from}>${widget.day}';
    if (key == _loadedKey) return;
    _loadedKey = key;
    try {
      final r = await Store.i.destinationStats(widget.from, widget.day);
      if (mounted && key == _loadedKey) setState(() => _raw = r);
    } catch (_) {
      _loadedKey = '';
    }
  }

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (_mAnim != null) _tc.value = _mAnim!.value;
    });
    _loadStats();
  }

  @override
  void didUpdateWidget(covariant DestinationsMap old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.day != widget.day) _loadStats();
  }

  @override
  void dispose() {
    _anim.dispose();
    _pulse.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _mAnim = Matrix4Tween(begin: _tc.value, end: target).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOutCubic));
    _anim.forward(from: 0);
  }

  Offset _mapOrigin() => Offset((_view.width - 330 * _k) / 2, (_view.height - 300 * _k) / 2);

  void _select(DestStat d) {
    setState(() => _sel = d);
    const z = 2.8;
    final p = _mapOrigin() + _pos(d.id) * _k;
    final m = Matrix4.identity()
      ..translate(_view.width / 2 - p.dx * z, _view.height / 2 - p.dy * z)
      ..scale(z);
    _animateTo(m);
  }

  void _reset() {
    setState(() => _sel = null);
    _animateTo(Matrix4.identity());
  }

  void _zoomBy(double f) {
    final cur = _tc.value.getMaxScaleOnAxis();
    final next = (cur * f).clamp(1.0, 5.0);
    final c = Offset(_view.width / 2, _view.height / 2);
    final scene = _tc.toScene(c);
    final m = Matrix4.identity()
      ..translate(c.dx - scene.dx * next, c.dy - scene.dy * next)
      ..scale(next);
    _animateTo(next == 1 ? Matrix4.identity() : m);
  }

  @override
  Widget build(BuildContext context) {
    final fromId = _cityIds[widget.from];
    final destStats = buildDestStats(widget.from, _raw);
    if (_sel != null) {
      final m = destStats.where((d) => d.id == _sel!.id);
      _sel = m.isEmpty ? null : m.first;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('رحلات ${dayLabel(widget.day)} من ${widget.from}', style: T.h3)),
        if (_sel != null)
          TextButton.icon(onPressed: _reset, icon: const Icon(Icons.zoom_out_map_rounded, size: 18), label: const Text('كل المدن', style: TextStyle(fontFamily: kFont)))
        else
          const Flexible(child: Text('حجم الدائرة = عدد الرحلات', style: T.small, overflow: TextOverflow.ellipsis)),
      ]),
      const SizedBox(height: 8),
      Container(
        height: 340,
        decoration: BoxDecoration(color: const Color(0xFFE3F5FE), borderRadius: BorderRadius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (_, box) {
          _view = Size(box.maxWidth, box.maxHeight);
          _k = ((box.maxWidth - 24) / 330).clamp(0.1, (box.maxHeight - 24) / 300).toDouble();
          final o = _mapOrigin();
          return Stack(children: [
            InteractiveViewer(
              transformationController: _tc,
              minScale: 1,
              maxScale: 5,
              boundaryMargin: const EdgeInsets.all(60),
              child: SizedBox(
                width: box.maxWidth,
                height: box.maxHeight,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(child: CustomPaint(painter: _SyriaPainter(origin: o, k: _k))),
                    if (fromId != null) _here(o + _pos(fromId) * _k),
                    for (final d in destStats)
                      if (d.trips > 0 && d.id != fromId && d.id != 'jableh' && !(d.id == 'latakia' && fromId == 'jableh')) _bubble(d, o + _pos(d.id) * _k),
                  ]),
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Column(children: [
                _zoomBtn(Icons.add_rounded, () => _zoomBy(1.6)),
                const SizedBox(height: 6),
                _zoomBtn(Icons.remove_rounded, () => _zoomBy(1 / 1.6)),
              ]),
            ),
          ]);
        }),
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
                    if (destStats.every((d) => d.trips == 0))
                      Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('لسا ما في رحلات منشورة من ${widget.from} ${dayLabel(widget.day)}', style: T.small))),
                    for (final d in destStats)
                      if (d.id != fromId && d.trips > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ActionChip(
                            label: Text('${d.city} · ${tripsLabel(d.trips)}', style: const TextStyle(fontFamily: kFont, color: C.dark)),
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
                  key: ValueKey(_sel!.id),
                  child: CardBox(
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                            Text('${widget.from} ← ${_sel!.city}', style: T.h3),
                            if (_sel!.tag != null) Badge2(_sel!.tag!, bg: C.warnBg, fg: C.warn),
                          ]),
                          Text('${tripsLabel(_sel!.trips)} · ${roadKm(widget.from, _sel!.city)} كم · من ${money(_sel!.fromPrice)}', style: T.small),
                        ]),
                      ),
                      SizedBox(width: 110, child: Btn('اعرض', onTap: () => widget.onSearch(_sel!.city))),
                    ]),
                  ),
                ),
              ),
      ),
    ]);
  }

  Widget _bubble(DestStat d, Offset p) {
    final s = (11 + d.trips * 1.8) * _k;
    final sel = _sel?.id == d.id;
    final ring = s * (1 + _pulse.value * .8);
    return Positioned(
      left: p.dx - 60,
      top: p.dy - 60,
      width: 120,
      height: 120,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _select(d),
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          Container(width: ring, height: ring, decoration: BoxDecoration(shape: BoxShape.circle, color: (sel ? C.yellow : C.primary).withValues(alpha: .35 * (1 - _pulse.value)))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: sel ? s * 1.15 : s,
            height: sel ? s * 1.15 : s,
            decoration: BoxDecoration(color: sel ? C.yellow : C.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: [BoxShadow(color: C.dark.withValues(alpha: .25), blurRadius: 6, offset: const Offset(0, 2))]),
            alignment: Alignment.center,
            child: FittedBox(child: Padding(padding: const EdgeInsets.all(2), child: Text('${d.trips}', style: TextStyle(fontFamily: kFont, color: sel ? C.dark : Colors.white)))),
          ),
          Positioned(
            // اسم المدينة: يمين الفقاعة، إلا طرطوس (عالحافة) تحتها
            left: d.id == 'tartus' ? null : 60 + s / 2 + 3,
            top: d.id == 'tartus' ? 60 + s / 2 + 1 : null,
            child: Text(d.city, style: TextStyle(fontFamily: kFont, fontSize: 11 * _k, color: C.dark, shadows: const [Shadow(color: Colors.white, blurRadius: 4)])),
          ),
        ]),
      ),
    );
  }

  Widget _here(Offset p) => Positioned(
        left: p.dx - 40,
        top: p.dy - 40,
        width: 80,
        height: 50,
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(7)), child: const Text('انت هون', textScaler: TextScaler.noScaling, style: TextStyle(fontFamily: kFont, fontSize: 10, color: Colors.white))),
          const SizedBox(height: 3),
          Container(width: 13, height: 13, decoration: BoxDecoration(color: C.dark, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5))),
        ]),
      );

  Widget _zoomBtn(IconData i, VoidCallback f) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        child: InkWell(borderRadius: BorderRadius.circular(12), onTap: f, child: SizedBox(width: 40, height: 40, child: Icon(i, color: C.dark))),
      );
}

class _SyriaPainter extends CustomPainter {
  final Offset origin;
  final double k;
  _SyriaPainter({required this.origin, required this.k});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(k);
    final land = Path()..addPolygon(syriaOutline, true)..addPolygon(golanOutline, true);
    canvas.drawShadow(land, C.dark.withValues(alpha: .4), 6, false);
    canvas.drawPath(land, Paint()..color = Colors.white);
    canvas.drawPath(Path()..addPolygon(syriaOutline, true), Paint()
      ..color = const Color(0xFFBFE6F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / k * 1.0
      ..strokeJoin = StrokeJoin.round);
    // الطرق الرئيسية
    final road = Paint()
      ..color = const Color(0xFFDDE3E3)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in const [('latakia', 'tartus'), ('tartus', 'homs'), ('homs', 'damascus'), ('homs', 'hama'), ('hama', 'aleppo'), ('damascus', 'daraa'), ('latakia', 'aleppo'), ('homs', 'palmyra'), ('palmyra', 'deir'), ('aleppo', 'raqqa'), ('raqqa', 'deir'), ('deir', 'hasakah')]) {
      canvas.drawLine(_pos(a), _pos(b), road);
    }
    // أسماء المدن الثانوية
    for (final id in const ['raqqa', 'deir', 'hasakah', 'palmyra', 'idlib', 'sweida']) {
      final c = mapCities.firstWhere((m) => m.id == id);
      canvas.drawCircle(c.pos, 2.2, Paint()..color = const Color(0xFFC7D1D1));
      final tp = TextPainter(text: TextSpan(text: c.name, style: const TextStyle(fontFamily: kFont, fontSize: 8.5, color: C.muted)), textDirection: TextDirection.rtl)..layout();
      tp.paint(canvas, c.pos + Offset(-tp.width / 2, -tp.height - 3));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SyriaPainter o) => o.origin != origin || o.k != k;
}
