import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/syria_map.dart';

/// خريطة سوريا ثلاثية الأبعاد: مجسّم بسماكة، مدن مضيئة موصولة بخطوط
/// بتمشي عليها نبضات ضو، ووراها أمواج وشبكة منظور وجزيئات.
class SyriaHero extends StatefulWidget {
  const SyriaHero({super.key});
  @override
  State<SyriaHero> createState() => _SyriaHeroState();
}

class _SyriaHeroState extends State<SyriaHero> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_intro, _loop]),
          builder: (_, __) => CustomPaint(painter: _HeroPainter(_intro.value, _loop.value), size: Size.infinite),
        ),
      );
}

const _links = [
  ('latakia', 'tartus'), ('tartus', 'homs'), ('homs', 'damascus'), ('homs', 'hama'), ('hama', 'aleppo'),
  ('latakia', 'aleppo'), ('idlib', 'aleppo'), ('damascus', 'daraa'), ('damascus', 'sweida'), ('homs', 'palmyra'),
  ('palmyra', 'deir'), ('aleppo', 'raqqa'), ('raqqa', 'deir'), ('deir', 'hasakah'), ('hasakah', 'qamishli'),
];
const _labeled = {'damascus', 'aleppo', 'homs', 'latakia', 'deir', 'hasakah', 'tartus'};

class _HeroPainter extends CustomPainter {
  final double intro, t;
  _HeroPainter(this.intro, this.t);

  static double _ease(double x) => 1 - math.pow(1 - x.clamp(0.0, 1.0), 3).toDouble();
  static double _seg(double v, double a, double b) => ((v - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final c = Offset(w / 2, h * .5);
    final tau = math.pi * 2;

    // ── خلفية: شبكة منظور، أمواج، وجزيئات
    final floorY = c.dy + h * .06;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .07)
      ..strokeWidth = 1;
    final scroll = t * 8 % 1;
    for (var i = 0; i < 14; i++) {
      final p = (i + scroll) / 14;
      final y = floorY + math.pow(p, 2.2) * (h - floorY + 40);
      canvas.drawLine(Offset(0, y), Offset(w, y), grid..color = Colors.white.withValues(alpha: .1 * p));
    }
    final vp = Offset(c.dx, floorY - 30);
    for (var i = -10; i <= 10; i++) {
      canvas.drawLine(vp, Offset(c.dx + i * w * .16, h + 40), grid..color = Colors.white.withValues(alpha: .05));
    }
    final glow = Paint()..shader = ui.Gradient.radial(c, w * .62, [Colors.white.withValues(alpha: .22), Colors.white.withValues(alpha: 0)]);
    canvas.drawCircle(c, w * .62, glow);
    for (var i = 0; i < 3; i++) {
      final p = (t * 2 + i / 3) % 1;
      final r = w * (.25 + p * .55);
      canvas.drawOval(Rect.fromCenter(center: c + Offset(0, h * .05), width: r * 2, height: r * 1.1), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: .28 * (1 - p)));
    }
    final rnd = math.Random(11);
    for (var i = 0; i < 26; i++) {
      final x = rnd.nextDouble() * w, sp = .4 + rnd.nextDouble() * .8, ph = rnd.nextDouble();
      final y = h - ((t * sp + ph) % 1) * h * 1.1;
      canvas.drawCircle(Offset(x + math.sin(t * tau + i) * 6, y), .8 + rnd.nextDouble() * 1.6, Paint()..color = Colors.white.withValues(alpha: .15 + .35 * rnd.nextDouble()));
    }

    // ── إسقاط ثلاثي الأبعاد للخريطة
    final rise = _ease(_seg(intro, 0, .55));
    final k = math.min(w / 360, h / 290) * (.88 + .12 * rise);
    final squash = .58 + .05 * math.sin(t * tau);
    final yaw = .07 * math.sin(t * tau) - .05;
    final cosA = math.cos(yaw), sinA = math.sin(yaw);
    final lift = (1 - rise) * 80 + math.sin(t * tau * 2) * 3;
    final depth = 18.0 * k;
    Offset P(Offset m) {
      final x = m.dx - 165, y = m.dy - 150;
      final rx = x * cosA - y * sinA, ry = x * sinA + y * cosA;
      return Offset(c.dx + rx * k, c.dy - 6 + ry * k * squash + lift);
    }

    Path poly(List<Offset> pts, [Offset off = Offset.zero]) => Path()..addPolygon([for (final p in pts) P(p) + off], true);
    final top = poly(syriaOutline)..addPath(poly(golanOutline), Offset.zero);
    final alpha = rise;

    // ظل تحت المجسّم
    canvas.drawOval(
      Rect.fromCenter(center: Offset(c.dx, c.dy + 150 * k * squash + depth + 8 + lift * .3), width: 300 * k, height: 46 * k),
      Paint()
        ..color = const Color(0xFF032B33).withValues(alpha: .35 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // الجوانب (السماكة)
    const layers = 9;
    for (var i = layers; i >= 1; i--) {
      final f = i / layers;
      final col = Color.lerp(const Color(0xFF7FCBEF), const Color(0xFF2E8FBF), f)!;
      canvas.drawPath(top.shift(Offset(0, depth * f)), Paint()..color = col.withValues(alpha: alpha));
    }
    // الوجه العلوي
    final b = top.getBounds();
    canvas.drawPath(
      top,
      Paint()..shader = ui.Gradient.linear(b.topLeft, b.bottomRight, [Colors.white.withValues(alpha: alpha), const Color(0xFFE3F5FE).withValues(alpha: alpha), const Color(0xFFC6EBFC).withValues(alpha: alpha)], [0, .55, 1]),
    );
    canvas.drawPath(top, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: alpha));
    // لمعة متحركة عالسطح
    canvas.save();
    canvas.clipPath(top);
    final sx = b.left + ((t * 1.5) % 1) * (b.width + 200) - 100;
    canvas.drawRect(b.inflate(20), Paint()..shader = ui.Gradient.linear(Offset(sx - 60, b.top), Offset(sx + 60, b.bottom), [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .5 * alpha), Colors.white.withValues(alpha: 0)], [0, .5, 1]));
    canvas.restore();

    // ── الخطوط بين المدن
    final city = {for (final m in mapCities) m.id: P(m.pos)};
    final drawP = _seg(intro, .45, 1);
    for (var i = 0; i < _links.length; i++) {
      final (a, z) = _links[i];
      final pa = city[a]!, pz = city[z]!;
      final d = (pz - pa).distance;
      final ctrl = Offset((pa.dx + pz.dx) / 2, (pa.dy + pz.dy) / 2 - d * .35 - 6);
      final local = _ease(_seg(drawP, i / _links.length * .6, i / _links.length * .6 + .4));
      if (local <= 0) continue;
      final path = Path()
        ..moveTo(pa.dx, pa.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, pz.dx, pz.dy);
      final metric = path.computeMetrics().first;
      final part = metric.extractPath(0, metric.length * local);
      canvas.drawPath(part, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = C.yellow.withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawPath(part, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFB300));
      if (local >= 1) {
        final ph = (t * 2.4 + i * .37) % 1;
        final tan = metric.getTangentForOffset(metric.length * ph);
        if (tan != null) {
          canvas.drawCircle(tan.position, 5, Paint()
            ..color = Colors.white.withValues(alpha: .7)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
          canvas.drawCircle(tan.position, 2.2, Paint()..color = Colors.white);
        }
      }
    }

    // ── المدن: نقطة مع نبض وعمود ضو
    final dotsP = _seg(intro, .35, .8);
    for (final m in mapCities) {
      final p = city[m.id]!;
      final big = _labeled.contains(m.id);
      final appear = _ease(_seg(dotsP, (m.pos.dy / 300) * .6, (m.pos.dy / 300) * .6 + .4));
      if (appear <= 0) continue;
      final pulse = (t * 3 + m.pos.dx / 100) % 1;
      canvas.drawOval(Rect.fromCenter(center: p, width: (10 + pulse * 26) * (big ? 1 : .7), height: (10 + pulse * 26) * squash * (big ? 1 : .7)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = C.primary.withValues(alpha: (1 - pulse) * .8 * appear));
      final beam = (big ? 22.0 : 12.0) * appear;
      canvas.drawLine(p, p - Offset(0, beam), Paint()
        ..shader = ui.Gradient.linear(p, p - Offset(0, beam), [C.primary.withValues(alpha: .9), C.primary.withValues(alpha: 0)])
        ..strokeWidth = 2.5);
      canvas.drawCircle(p, (big ? 5.5 : 3.8) * appear, Paint()..color = C.dark);
      canvas.drawCircle(p, (big ? 3 : 2) * appear, Paint()..color = C.yellow);
      if (big && appear > .6) {
        final tp = TextPainter(
          text: TextSpan(text: m.name, style: TextStyle(fontFamily: kFont, fontSize: 12.5, color: C.dark.withValues(alpha: (appear - .6) / .4))),
          textDirection: TextDirection.rtl,
        )..layout();
        final o = p - Offset(tp.width / 2, beam + tp.height + 2);
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(o.dx - 7, o.dy - 1, tp.width + 14, tp.height + 2), const Radius.circular(9));
        canvas.drawRRect(r, Paint()..color = Colors.white.withValues(alpha: .92 * (appear - .6) / .4));
        tp.paint(canvas, o);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeroPainter o) => o.intro != intro || o.t != t;
}
