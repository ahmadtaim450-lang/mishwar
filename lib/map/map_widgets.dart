// عناصر الخريطة المرسومة: علامات الرحلات، المجموعات، موقعي مع الاتجاه، والأزرار.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../core/theme.dart';
import 'geo_math.dart';
import 'models.dart';

/// تحريك الكاميرا بسلاسة (flutter_map ما فيه تحريك جاهز).
class MapAnimator {
  final MapController map;
  final TickerProvider vsync;
  AnimationController? _c;
  MapAnimator(this.map, this.vsync);

  void move(LatLng to, double zoom, {double? rotation, Duration duration = const Duration(milliseconds: 650)}) {
    final MapCamera cam;
    try {
      cam = map.camera;
    } catch (_) {
      return; // الخريطة لسا ما جهزت
    }
    _c?.dispose();
    final c = _c = AnimationController(vsync: vsync, duration: duration);
    final a = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic);
    final lat = Tween(begin: cam.center.latitude, end: to.latitude);
    final lon = Tween(begin: cam.center.longitude, end: to.longitude);
    final z = Tween(begin: cam.zoom, end: zoom);
    final r0 = cam.rotation, r1 = rotation ?? cam.rotation;
    final rot = Tween(begin: r0, end: r0 + (((r1 - r0) + 540) % 360 - 180));
    c.addListener(() => map.moveAndRotate(LatLng(lat.evaluate(a), lon.evaluate(a)), z.evaluate(a), rot.evaluate(a)));
    c.forward();
  }

  void fit(GeoBounds b, {EdgeInsets padding = const EdgeInsets.all(60), double maxZoom = 15}) {
    final MapCamera cam;
    try {
      cam = map.camera;
    } catch (_) {
      return;
    }
    if (b.north - b.south < 1e-6 && b.east - b.west < 1e-6) {
      move(b.center, math.min(maxZoom, 14));
      return;
    }
    final target = CameraFit.bounds(bounds: LatLngBounds(LatLng(b.south, b.west), LatLng(b.north, b.east)), padding: padding, maxZoom: maxZoom).fit(cam);
    move(target.center, target.zoom);
  }

  void dispose() => _c?.dispose();
}

/// علامة رحلة: السعر مع سهم لتحت.
class TripPin extends StatelessWidget {
  final MapTrip t;
  final bool selected;
  const TripPin(this.t, {super.key, this.selected = false});
  @override
  Widget build(BuildContext context) {
    final bg = selected ? C.dark : (t.exact ? C.primary : Colors.white);
    final fg = selected || t.exact ? Colors.white : C.dark;
    return Semantics(
      label: 'رحلة من ${t.board} لـ ${t.to}، ${fmtPriceShort(t.price)}',
      button: true,
      child: AnimatedScale(
        scale: selected ? 1.15 : 1,
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.bottomCenter,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? C.yellow : C.primary, width: 1.5),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(t.instant ? Icons.bolt_rounded : Icons.directions_car_filled_rounded, size: 13, color: fg),
              const SizedBox(width: 3),
              Flexible(child: Text(fmtPriceShort(t.price), maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontFamily: kFont, fontSize: 12.5, color: fg, height: 1.2))),
            ]),
          ),
          CustomPaint(size: const Size(10, 6), painter: _Tail(bg)),
        ]),
      ),
    );
  }
}

class _Tail extends CustomPainter {
  final Color c;
  _Tail(this.c);
  @override
  void paint(Canvas canvas, Size s) => canvas.drawPath(Path()..moveTo(0, 0)..lineTo(s.width, 0)..lineTo(s.width / 2, s.height)..close(), Paint()..color = c);
  @override
  bool shouldRepaint(_Tail o) => o.c != c;
}

/// فقاعة مجموعة: العدد، وحجمها بيكبر مع العدد.
class ClusterBubble extends StatelessWidget {
  final int count;
  final int? minPrice;
  const ClusterBubble(this.count, {super.key, this.minPrice});
  static double sizeFor(int n) => (38 + math.log(n) * 7).clamp(38, 64).toDouble();
  @override
  Widget build(BuildContext context) {
    final d = sizeFor(count);
    return Semantics(
      label: '$count رحلات هون',
      button: true,
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [C.primaryLight, C.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [BoxShadow(color: C.primary.withValues(alpha: .35), blurRadius: 12, spreadRadius: 2)],
        ),
        alignment: Alignment.center,
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(count > 99 ? '99+' : '$count', style: const TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 16, height: 1.1)),
          ),
        ),
      ),
    );
  }
}

/// موقعي: نقطة زرقا مع مخروط الاتجاه.
class MeDot extends StatelessWidget {
  final double? heading; // درجات من الشمال
  final double mapRotation;
  final bool weak;
  const MeDot({super.key, this.heading, this.mapRotation = 0, this.weak = false});
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'موقعك',
        child: SizedBox(
          width: 64,
          height: 64,
          child: Stack(alignment: Alignment.center, children: [
            if (heading != null)
              Transform.rotate(
                angle: (heading! + mapRotation) * math.pi / 180,
                child: CustomPaint(size: const Size(64, 64), painter: _Cone()),
              ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: weak ? C.muted : C.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3.5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 6)],
              ),
            ),
          ]),
        ),
      );
}

class _Cone extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2;
    final paint = Paint()
      ..shader = RadialGradient(colors: [C.primary.withValues(alpha: .55), C.primary.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(Rect.fromCircle(center: c, radius: r), -math.pi / 2 - .45, .9, false)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_Cone o) => false;
}

/// دبوس مكان (محفوظ أو نقطة مختارة).
class PlacePin extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? label;
  const PlacePin({super.key, this.icon = Icons.place_rounded, this.color = C.dark, this.label});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        if (label != null)
          Container(
            constraints: const BoxConstraints(maxWidth: 120),
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .15), blurRadius: 4)]),
            child: Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kFont, fontSize: 11, color: C.dark)),
          ),
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 6)]),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ]);
}

/// اسم مدينة على الخريطة (للتكبير البعيد).
class CityLabel extends StatelessWidget {
  final String name;
  final bool dark;
  const CityLabel(this.name, {super.key, this.dark = false});
  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.visible,
          style: TextStyle(
            fontFamily: kFont,
            fontSize: 13,
            color: dark ? Colors.white : C.dark,
            shadows: [Shadow(color: dark ? Colors.black : Colors.white, blurRadius: 4), Shadow(color: dark ? Colors.black : Colors.white, blurRadius: 8)],
          ),
        ),
      );
}

/// زر دائري فوق الخريطة.
class MapFab extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active, busy, dark;
  final Widget? child;
  const MapFab(this.icon, {super.key, required this.tooltip, this.onTap, this.active = false, this.busy = false, this.dark = false, this.child});
  @override
  Widget build(BuildContext context) {
    final bg = active ? C.primary : (dark ? const Color(0xFF15262B) : Colors.white);
    final fg = active ? Colors.white : (dark ? Colors.white : C.dark);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: Colors.black38,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(child: busy ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg)) : (child ?? Icon(icon, color: fg, size: 22))),
            ),
          ),
        ),
      ),
    );
  }
}

/// دائرة الدقة حول موقعي (بالمتر).
CircleMarker accuracyCircle(LatLng p, double meters) => CircleMarker(
      point: p,
      radius: meters.clamp(5, 3000),
      useRadiusInMeter: true,
      color: C.primary.withValues(alpha: .12),
      borderColor: C.primary.withValues(alpha: .35),
      borderStrokeWidth: 1,
    );
