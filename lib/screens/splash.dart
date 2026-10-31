import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/syria_map.dart';
import '../widgets/common.dart';
import 'onboarding.dart';

/// شاشة البداية: خريطة سوريا الحقيقية وسيارة بتمشي بين المدن.
class SplashScreen extends StatefulWidget {
  const SplashScreen();
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _drive = AnimationController(vsync: this, duration: const Duration(milliseconds: 8600))..repeat();
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  ui.Image? _car;

  @override
  void initState() {
    super.initState();
    _loadCar();
  }

  Future<void> _loadCar() async {
    try {
      final data = await DefaultAssetBundle.of(context).load('assets/images/car_topdown.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 120);
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _car = frame.image);
    } catch (_) {}
  }

  @override
  void dispose() {
    _drive.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.primary,
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 40),
          Enter(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: C.dark.withValues(alpha: .25), blurRadius: 30, offset: const Offset(0, 14))]),
              child: const Icon(Icons.route_rounded, color: C.primary, size: 48),
            ),
          ),
          const SizedBox(height: 14),
          const Enter(delay: 150, child: Text('مشوار', style: TextStyle(fontFamily: kFont, fontSize: 76, height: 1, color: Colors.white))),
          const SizedBox(height: 6),
          const Enter(delay: 300, child: Text('رفيقك بالطريق بين المدن', style: TextStyle(fontFamily: kFont, fontSize: 18, color: Colors.white))),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: AnimatedBuilder(
                animation: Listenable.merge([_drive, _intro]),
                builder: (_, __) => CustomPaint(painter: SyriaMapPainter(t: _drive.value, intro: Curves.easeOutCubic.transform(_intro.value), car: _car), size: Size.infinite),
              ),
            ),
          ),
          Enter(
            delay: 600,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
              child: Column(children: [
                Btn('يلّا نبلّش', kind: BtnKind.white, onTap: () => goReplace(context, const OnboardingScreen())),
                const SizedBox(height: 10),
                const Text('بسم الله · مجاني لكل السوريين', style: TextStyle(fontFamily: kFont, fontSize: 13, color: Colors.white)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
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
