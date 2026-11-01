import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/syria_map.dart';
import '../data/world_land.dart';
import '../widgets/common.dart';
import 'onboarding.dart';
import 'shell.dart';
import 'auth.dart' show SignupNameScreen;
import '../data/store.dart';
import '../widgets/syria_hero.dart';

/// شاشة البداية: خريطة سوريا ثلاثية الأبعاد ومدنها موصولة ببعض.
class SplashScreen extends StatelessWidget {
  const SplashScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF064854), Color(0xFF0A8FD0), C.primary])),
          child: SafeArea(
            child: Column(children: [
              const SizedBox(height: 36),
              const Enter(child: Text('مشوار', style: TextStyle(fontFamily: kFont, fontSize: 80, height: 1, color: Colors.white))),
              const SizedBox(height: 6),
              const Enter(delay: 150, child: Text('رفيقك بالطريق بين المدن', style: TextStyle(fontFamily: kFont, fontSize: 18, color: Colors.white))),
              const Expanded(child: SyriaHero()),
              Enter(
                delay: 900,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                  child: Column(children: [
                    Btn(Store.i.signedIn && (Store.i.profile?.complete ?? false) ? 'أهلين ${Store.i.name}، كمّل' : 'يلّا نبلّش', kind: BtnKind.white, onTap: () => goReplace(context, !Store.i.signedIn ? const OnboardingScreen() : ((Store.i.profile?.complete ?? false) ? const AppShell() : const SignupNameScreen()))),
                    const SizedBox(height: 10),
                    const Text('مشوارك بأمان', style: TextStyle(fontFamily: kFont, fontSize: 13, color: Colors.white70)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// الكرة الأرضية بالكود: قارات حقيقية، سوريا مميّزة، والسيارة بتلف حوالين الكرة.
class TinyPlanet extends StatefulWidget {
  final bool compact;
  const TinyPlanet({this.compact = false});
  @override
  State<TinyPlanet> createState() => _TinyPlanetState();
}

class _TinyPlanetState extends State<TinyPlanet> with TickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
  ui.Image? _car;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await DefaultAssetBundle.of(context).load('assets/images/car_side.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 360);
      final f = await codec.getNextFrame();
      if (mounted) setState(() => _car = f.image);
    } catch (_) {}
  }

  @override
  void dispose() {
    _orbit.dispose();
    _intro.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([_orbit, _intro, _spin]),
        builder: (_, __) => CustomPaint(
          size: Size.infinite,
          painter: GlobePainter(orbit: _orbit.value, spin: _spin.value, intro: Curves.easeOutCubic.transform(_intro.value), car: _car, compact: widget.compact),
        ),
      );
}

class GlobePainter extends CustomPainter {
  final double orbit, spin, intro;
  final ui.Image? car;
  final bool compact;
  GlobePainter({required this.orbit, this.spin = 0, required this.intro, this.car, this.compact = false});

  static const _tilt = 24.0 * math.pi / 180; // ميلان الكرة لتبيّن منطقتنا

  @override
  void paint(Canvas canvas, Size size) {
    final R = math.min(size.width, size.height) * (compact ? .3 : .3) * (.85 + .15 * intro);
    final c = Offset(size.width / 2, size.height / 2 + (1 - intro) * 80);
    final sphere = Rect.fromCircle(center: c, radius: R);
    final lam0 = (38.0 + 40 * math.sin(spin * 2 * math.pi)) * math.pi / 180; // الكرة بتتمايل حوالين سوريا

    // هالة الغلاف الجوي
    canvas.drawCircle(c, R * 1.18, Paint()..shader = ui.Gradient.radial(c, R * 1.18, [Colors.white.withValues(alpha: .45 * intro), Colors.white.withValues(alpha: 0)], [.82, 1]));

    // ظل الكرة على الأرض
    canvas.drawOval(Rect.fromCenter(center: c + Offset(0, R * 1.32), width: R * 1.5, height: R * .18), Paint()
      ..color = C.dark.withValues(alpha: .18 * intro)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));

    // المحيط
    canvas.drawCircle(c, R, Paint()..shader = ui.Gradient.radial(c - Offset(R * .35, R * .4), R * 1.5, const [Color(0xFF5FD0FF), Color(0xFF0A8FD8), Color(0xFF064E7A)], const [0, .6, 1]));

    // القارات (إسقاط متعامد)
    canvas.save();
    canvas.clipPath(Path()..addOval(sphere));
    final land = Paint()..color = const Color(0xFF6BCB77);
    final landEdge = Paint()
      ..color = const Color(0xFF3E9E52)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final poly in landPolys) {
      final path = _project(poly, c, R, lam0);
      if (path != null) {
        canvas.drawPath(path, land);
        canvas.drawPath(path, landEdge);
      }
    }
    final syr = _project(syriaLonLat, c, R, lam0);
    if (syr != null) {
      canvas.drawPath(syr, Paint()..color = C.yellow);
      canvas.drawPath(syr, Paint()
        ..color = C.dark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4);
    }
    // دبوس نابض فوق سوريا
    {
      final lam = 38.3 * math.pi / 180, phi = 34.9 * math.pi / 180, dl = lam - lam0;
      final x = math.cos(phi) * math.sin(dl);
      final y = math.cos(_tilt) * math.sin(phi) - math.sin(_tilt) * math.cos(phi) * math.cos(dl);
      final z = math.sin(_tilt) * math.sin(phi) + math.cos(_tilt) * math.cos(phi) * math.cos(dl);
      if (z > .15) {
        final p = Offset(c.dx + x * R, c.dy - y * R);
        final k = (orbit * 3) % 1;
        canvas.drawCircle(p, 6 + 16 * k, Paint()..color = C.yellow.withValues(alpha: .7 * (1 - k)));
        final pin = Path()
          ..moveTo(p.dx, p.dy)
          ..cubicTo(p.dx - 9, p.dy - 9, p.dx - 9, p.dy - 18, p.dx - 9, p.dy - 18)
          ..arcToPoint(Offset(p.dx + 9, p.dy - 18), radius: const Radius.circular(9))
          ..cubicTo(p.dx + 9, p.dy - 9, p.dx, p.dy, p.dx, p.dy);
        canvas.drawPath(pin, Paint()..color = C.yellow);
        canvas.drawPath(pin, Paint()
          ..color = C.dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);
        canvas.drawCircle(Offset(p.dx, p.dy - 18), 3.4, Paint()..color = C.dark);
      }
    }
    canvas.restore();

    // تظليل كروي (ضو من فوق يسار)
    canvas.drawCircle(c, R, Paint()..shader = ui.Gradient.radial(c - Offset(R * .45, R * .5), R * 2, [Colors.white.withValues(alpha: .35), Colors.white.withValues(alpha: 0), Colors.black.withValues(alpha: .28)], const [0, .45, 1]));

    // الطريق حوالين الكرة
    final roadR = R + 4;
    canvas.drawCircle(c, roadR, Paint()
      ..color = C.dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9);
    final dash = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    const n = 48;
    for (var i = 0; i < n; i++) {
      final a0 = i * 2 * math.pi / n;
      canvas.drawArc(Rect.fromCircle(center: c, radius: roadR), a0, math.pi / n, false, dash);
    }

    // السيارة: بتلف بعكس عقارب الساعة، دواليبها دايماً عالطريق
    if (intro > .6) {
      final theta = -math.pi / 2 - orbit * 2 * math.pi;
      final w = R * .62;
      final h = car == null ? w * .45 : w * car!.height / car!.width;
      final pos = c + Offset(math.cos(theta), math.sin(theta)) * (roadR + 4);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(theta + math.pi / 2);
      // ظل خفيف تحت السيارة
      canvas.drawOval(Rect.fromCenter(center: Offset(0, -2), width: w * .8, height: 6), Paint()
        ..color = Colors.black.withValues(alpha: .25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      final rect = Rect.fromLTWH(-w / 2, -h, w, h);
      if (car != null) {
        paintImage(canvas: canvas, rect: rect, image: car!, filterQuality: FilterQuality.high, fit: BoxFit.contain);
      } else {
        final body = RRect.fromRectAndCorners(Rect.fromLTWH(-w / 2, -h * .75, w, h * .55), topLeft: const Radius.circular(10), topRight: const Radius.circular(14), bottomLeft: const Radius.circular(6), bottomRight: const Radius.circular(6));
        canvas.drawRRect(body, Paint()..color = Colors.white);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-w * .3, -h, w * .55, h * .3), const Radius.circular(10)), Paint()..color = C.primary);
        for (final x in [-w * .3, w * .3]) {
          canvas.drawCircle(Offset(x, -h * .2), h * .2, Paint()..color = C.dark);
        }
      }
      canvas.restore();
    }
  }

  Path? _project(List<double> ll, Offset c, double R, double lam0) {
    final path = Path();
    var visible = 0;
    final sinT = math.sin(_tilt), cosT = math.cos(_tilt);
    for (var i = 0; i < ll.length; i += 2) {
      final lam = ll[i] * math.pi / 180, phi = ll[i + 1] * math.pi / 180;
      final cosPhi = math.cos(phi), sinPhi = math.sin(phi);
      final dl = lam - lam0;
      var x = cosPhi * math.sin(dl);
      var y = cosT * sinPhi - sinT * cosPhi * math.cos(dl);
      final z = sinT * sinPhi + cosT * cosPhi * math.cos(dl);
      if (z < 0) {
        // نقطة ورا الكرة: منلصقها عالحافة
        final l = math.sqrt(x * x + y * y);
        if (l > 0) {
          x /= l;
          y /= l;
        }
      } else {
        visible++;
      }
      final p = Offset(c.dx + x * R, c.dy - y * R);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (visible == 0) return null;
    return path..close();
  }

  @override
  bool shouldRepaint(covariant GlobePainter o) => true;
}

class SyriaMapPainter extends CustomPainter {
  final double t, intro;
  final ui.Image? car;
  final List<String> route;
  SyriaMapPainter({required this.t, this.intro = 1, this.car, this.route = const ['latakia', 'jableh', 'tartus', 'homs', 'damascus']});

  static const _w = 330.0, _h = 300.0;

  Offset _city(String id) => mapCities.firstWhere((c) => c.id == id).pos;

  @override
  void paint(Canvas canvas, Size size) {
    final s = (size.width / _w < size.height / _h) ? size.width / _w : size.height / _h;
    canvas.save();
    canvas.translate((size.width - _w * s) / 2, (size.height - _h * s) / 2 + 20 * (1 - intro));
    canvas.scale(s);

    // الخريطة
    final land = Path()..addPolygon(syriaOutline, true)..addPolygon(golanOutline, true);
    canvas.drawShadow(land, C.dark.withValues(alpha: .6 * intro), 10, false);
    canvas.drawPath(land, Paint()..color = Colors.white.withValues(alpha: intro));
    canvas.drawPath(Path()..addPolygon(golanOutline, true), Paint()
      ..color = Colors.white.withValues(alpha: intro)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round);

    // الطرق الثانوية
    final sec = Paint()
      ..color = const Color(0xFFC7D1D1)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (final (a, b) in const [('aleppo', 'hama'), ('hama', 'homs'), ('homs', 'palmyra'), ('palmyra', 'deir'), ('raqqa', 'deir'), ('hasakah', 'deir'), ('aleppo', 'raqqa'), ('damascus', 'daraa'), ('damascus', 'sweida'), ('aleppo', 'idlib')]) {
      _dashed(canvas, _city(a), _city(b), sec);
    }

    // الطريق الرئيسي
    final roadPath = Path()..moveTo(_city(route.first).dx, _city(route.first).dy);
    for (final id in route.skip(1)) {
      roadPath.lineTo(_city(id).dx, _city(id).dy);
    }
    final metric = roadPath.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * intro);
    canvas.drawPath(drawn, Paint()
      ..color = C.dark
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    for (double d = 0; d < metric.length * intro; d += 10) {
      final seg = metric.extractPath(d, d + 5);
      canvas.drawPath(seg, Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke);
    }

    // المدن
    for (final c in mapCities) {
      final main = route.contains(c.id) && c.id != 'jableh';
      if (!main && const ['jableh', 'qamishli'].contains(c.id)) continue;
      if (main) {
        final pulse = (t * 3) % 1;
        canvas.drawCircle(c.pos, 6 + 8 * pulse, Paint()..color = C.primary.withValues(alpha: .5 * (1 - pulse)));
      }
      canvas.drawCircle(c.pos, main ? 5 : 3, Paint()..color = c.id == 'damascus' ? C.yellow : (main ? C.dark : const Color(0xFF7FA3A8)));
      canvas.drawCircle(c.pos, main ? 5 : 3, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = main ? 2 : 1.2);
      final tp = TextPainter(
        text: TextSpan(text: c.name, style: TextStyle(fontFamily: kFont, fontSize: main ? 12 : 9.5, color: main ? C.dark : C.muted)),
        textDirection: TextDirection.rtl,
      )..layout();
      final left = c.pos.dx < 70;
      final o = left ? Offset(c.pos.dx + 9, c.pos.dy - tp.height / 2) : Offset(c.pos.dx - tp.width / 2, c.pos.dy - tp.height - 6);
      tp.paint(canvas, c.id == 'damascus' ? Offset(c.pos.dx + 12, c.pos.dy - 4) : o);
    }

    // السيارة: بتمشي بين المدن وبتوقف شوي بكل وحدة
    if (intro > .95) {
      final p = _progress(t, metric, route.map(_city).toList());
      final tan = metric.getTangentForOffset(metric.length * p);
      if (tan != null) {
        canvas.save();
        canvas.translate(tan.position.dx, tan.position.dy);
        canvas.rotate(-tan.angle);
        if (car != null) {
          const w = 34.0;
          final h = w * car!.height / car!.width;
          paintImage(canvas: canvas, rect: Rect.fromCenter(center: Offset.zero, width: w, height: h), image: car!, filterQuality: FilterQuality.high);
        } else {
          final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 30, height: 17), const Radius.circular(6));
          canvas.drawRRect(body, Paint()..color = Colors.white);
          canvas.drawRRect(body, Paint()
            ..color = C.dark
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(-1, 0), width: 11, height: 11), const Radius.circular(3)), Paint()..color = C.primary);
          canvas.drawRect(Rect.fromCenter(center: const Offset(13, -5), width: 2, height: 3.5), Paint()..color = C.yellow);
          canvas.drawRect(Rect.fromCenter(center: const Offset(13, 5), width: 2, height: 3.5), Paint()..color = C.yellow);
        }
        canvas.restore();
      }
    }

    // دبوس الوصول
    final d = _city('damascus');
    final pin = Path()
      ..moveTo(d.dx, d.dy - 2)
      ..cubicTo(d.dx - 11, d.dy - 11, d.dx - 11, d.dy - 22, d.dx - 11, d.dy - 22)
      ..arcToPoint(Offset(d.dx + 11, d.dy - 22), radius: const Radius.circular(11))
      ..cubicTo(d.dx + 11, d.dy - 11, d.dx, d.dy - 2, d.dx, d.dy - 2);
    canvas.drawPath(pin, Paint()..color = C.yellow);
    canvas.drawPath(pin, Paint()
      ..color = C.dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    canvas.drawCircle(Offset(d.dx, d.dy - 22), 4, Paint()..color = C.dark);

    canvas.restore();
  }

  /// تقدّم السيارة مع وقفات قصيرة بالمدن.
  double _progress(double t, ui.PathMetric m, List<Offset> pts) {
    final segs = <double>[];
    for (var i = 0; i < pts.length - 1; i++) {
      segs.add((pts[i + 1] - pts[i]).distance);
    }
    final total = segs.fold<double>(0, (a, b) => a + b);
    const travel = .74, pause = .06; // نسب من الدورة
    final stopsAt = {2, 3}; // طرطوس وحمص
    double time = 0, dist = 0;
    for (var i = 0; i < segs.length; i++) {
      final dur = travel * segs[i] / total;
      if (t <= time + dur) {
        final k = Curves.easeInOut.transform(((t - time) / dur).clamp(0.0, 1.0).toDouble());
        return (dist + segs[i] * k) / total;
      }
      time += dur;
      dist += segs[i];
      if (stopsAt.contains(i + 1)) {
        if (t <= time + pause) return dist / total;
        time += pause;
      }
    }
    return 1;
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p) {
    final len = (b - a).distance;
    final dir = (b - a) / len;
    for (double d = 0; d < len; d += 8) {
      c.drawLine(a + dir * d, a + dir * (d + 4 > len ? len : d + 4), p);
    }
  }

  @override
  bool shouldRepaint(covariant SyriaMapPainter o) => o.t != t || o.intro != intro || o.car != car;
}
