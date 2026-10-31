import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../widgets/common.dart';
import 'search.dart' show TripCard;
import 'splash.dart';
import 'messages.dart';
import 'profile.dart';
import 'shell.dart';

class TripDetailsScreen extends StatelessWidget {
  final Trip t;
  const TripDetailsScreen(this.t);
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: TopBar(title: '${t.from} ← ${t.to}', actions: [SquareBtn(Icons.ios_share_rounded, tooltip: 'مشاركة', onTap: () => toast(context, 'تم نسخ رابط الرحلة'))]),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
          Enter(child: CardBox(child: Timeline(a: t.from, b: t.to, ta: t.dep, tb: t.arr, sa: t.fromSpot, sb: t.toSpot))),
          const SizedBox(height: 12),
          Enter(
            delay: 80,
            child: CardBox(
              child: Row(children: [
                const Expanded(child: Text('السعر لراكب واحد', style: T.body)),
                Text(money(t.price), style: const TextStyle(fontFamily: kFont, fontSize: 22, color: C.primary)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Enter(
            delay: 160,
            child: CardBox(
              child: Column(children: [
                InkWell(
                  onTap: () => go(context, DriverScreen(t.driver)),
                  child: Row(children: [
                    Avatar(t.driver, size: 54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [Text(t.driver.name, style: T.h3), const SizedBox(width: 6), const Icon(Icons.verified_rounded, color: C.primary, size: 18)]),
                        Text('★ ${t.driver.rating} · ${t.driver.trips} رحلة', style: T.small),
                      ]),
                    ),
                    const Icon(Icons.chevron_left_rounded, color: C.muted),
                  ]),
                ),
                const Divider(height: 24, color: C.line),
                _info(Icons.directions_car_outlined, t.car),
                _info(Icons.smoke_free_rounded, 'ممنوع التدخين'),
                _info(Icons.mosque_outlined, 'وقفة للصلاة عالطريق'),
                _info(Icons.luggage_outlined, 'شنتاية وحدة متوسطة'),
                _info(Icons.event_seat_outlined, '${t.seatsLeft} مقاعد فاضية من ${t.seatsTotal}'),
                Align(alignment: AlignmentDirectional.centerStart, child: KindBadge(t.kind)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Enter(
            delay: 240,
            child: CardBox(
              onTap: () => go(context, RouteScreen(t)),
              child: Row(children: [
                const Icon(Icons.map_outlined, color: C.primary),
                const SizedBox(width: 10),
                Expanded(child: Text('المسار والوقفات: ${[t.from, ...t.stops, t.to].join(' ← ')}', style: T.label)),
                const Icon(Icons.chevron_left_rounded, color: C.muted),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          const InfoNote('الدفع كاش للسائق. رقم السائق بيظهر بعد ما يقبل الحجز.'),
        ]),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            color: Colors.white,
            child: Row(children: [
              SquareBtn(Icons.chat_bubble_outline_rounded, tooltip: 'مراسلة', onTap: () => go(context, ChatScreen(t.driver))),
              const SizedBox(width: 10),
              Expanded(child: Btn(t.instant ? 'احجز فوراً' : 'اطلب مقعد', onTap: () => go(context, BookReviewScreen(t)))),
            ]),
          ),
        ),
      );

  Widget _info(IconData i, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [Icon(i, color: C.primary, size: 20), const SizedBox(width: 10), Text(s, style: T.body)]),
      );
}

class RouteScreen extends StatefulWidget {
  final Trip t;
  const RouteScreen(this.t);
  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 8600))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final stops = [(t.dep, t.from, t.fromSpot), for (final s in t.stops) ('', s, 'وقفة واستراحة'), (t.arr, t.to, t.toSpot)];
    return Scaffold(
      appBar: const TopBar(title: 'المسار والوقفات'),
      body: Column(children: [
        Container(
          height: 300,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(26)),
          padding: const EdgeInsets.all(12),
          child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: SyriaMapPainter(t: _c.value), size: Size.infinite)),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            for (var i = 0; i < stops.length; i++)
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Column(children: [
                    Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: i == stops.length - 1 ? C.dark : C.primary, width: 3.5))),
                    if (i < stops.length - 1) Expanded(child: Container(width: 3, color: C.primary)),
                  ]),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 22),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(stops[i].$2, style: T.label), Text(stops[i].$3, style: T.small)])),
                        Text(stops[i].$1, style: T.label),
                      ]),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class DriverScreen extends StatelessWidget {
  final Person p;
  const DriverScreen(this.p);
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
          Row(children: [
            Hero(tag: 'av-${p.name}', child: Avatar(p, size: 84)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.name, style: T.h1.copyWith(fontSize: 28)), Text('${p.trips} رحلة · عضو من 2026', style: T.small)])),
          ]),
          const SizedBox(height: 14),
          const Wrap(spacing: 8, runSpacing: 8, children: [Badge2('✓ هوية موثقة'), Badge2('✓ رقم موثق'), Badge2('بيرد بسرعة')]),
          const SizedBox(height: 14),
          CardBox(
            child: Row(children: [
              Column(children: [
                Text('${p.rating}', style: const TextStyle(fontFamily: kFont, fontSize: 40, color: C.dark)),
                const Text('★★★★★', style: TextStyle(color: C.star, fontSize: 14)),
              ]),
              const SizedBox(width: 18),
              Expanded(
                child: Column(children: [
                  for (final (n, w) in const [(5, .88), (4, .1), (3, .02), (2, .0), (1, .0)])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Text('$n', style: T.small),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: w),
                              duration: const Duration(milliseconds: 900),
                              curve: Curves.easeOutCubic,
                              builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 7, backgroundColor: C.line, color: C.primary),
                            ),
                          ),
                        ),
                      ]),
                    ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Text('شو قالوا عنو', style: T.h3)),
            TextButton(onPressed: () => go(context, const ReviewsScreen()), child: const Text('الكل', style: TextStyle(fontFamily: kFont, color: C.primary))),
          ]),
          for (final r in reviews.take(3)) _ReviewCard(r),
          TextButton.icon(
            onPressed: () => go(context, const ReportScreen()),
            icon: const Icon(Icons.flag_outlined, color: C.danger),
            label: const Text('بلّغ عن هالعضو', style: TextStyle(fontFamily: kFont, color: C.danger)),
          ),
        ]),
      );
}

class _ReviewCard extends StatelessWidget {
  final Review r;
  const _ReviewCard(this.r);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: CardBox(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Avatar(Person(r.name, r.initial), size: 36),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.name, style: T.label), Text(r.date, style: T.small)])),
              Text('★' * r.stars, style: const TextStyle(color: C.star)),
            ]),
            const SizedBox(height: 8),
            Text(r.text, style: T.body),
          ]),
        ),
      );
}

class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(title: 'التقييمات', sub: '38 تقييم'),
        body: ListView(padding: const EdgeInsets.all(20), children: [for (var i = 0; i < reviews.length; i++) Enter(delay: i * 70, child: _ReviewCard(reviews[i]))]),
      );
}

class BookReviewScreen extends StatefulWidget {
  final Trip t;
  const BookReviewScreen(this.t);
  @override
  State<BookReviewScreen> createState() => _BookReviewScreenState();
}

class _BookReviewScreenState extends State<BookReviewScreen> {
  int _seats = 1;
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Scaffold(
      appBar: const TopBar(title: 'تأكيد الحجز'),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
        CardBox(
          child: Column(children: [
            Timeline(a: t.from, b: t.to, ta: t.dep, tb: t.arr, sa: t.fromSpot, sb: t.toSpot),
            const Divider(height: 24, color: C.line),
            Row(children: [Avatar(t.driver, size: 38), const SizedBox(width: 10), Expanded(child: Text('${t.driver.name} · ${t.car}', style: T.label)), Badge2('★ ${t.driver.rating}')]),
          ]),
        ),
        const SizedBox(height: 12),
        CardBox(
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('عدد المقاعد', style: T.label), Text('باقي ${t.seatsLeft}', style: T.small)])),
            Counter(value: _seats, max: t.seatsLeft, onChanged: (v) => setState(() => _seats = v)),
          ]),
        ),
        const SizedBox(height: 12),
        CardBox(
          child: Column(children: [
            _line('سعر المقعد', money(t.price)),
            _line('رسوم الخدمة', 'مجاناً', color: C.primary),
            const Divider(height: 20, color: C.line),
            _line('المجموع (كاش للسائق)', money(t.price * _seats), bold: true),
          ]),
        ),
        const SizedBox(height: 12),
        InfoNote(t.instant ? 'حجز فوري: رح يتأكد حجزك مباشرة.' : '${t.driver.name} بيوافق على الطلبات يدوياً. ما في دفع قبل الموافقة.', icon: Icons.back_hand_outlined, warn: !t.instant),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Btn('متابعة', onTap: () => go(context, BookMessageScreen(t))),
            const SizedBox(height: 8),
            Btn('مسافر مع عائلتي', kind: BtnKind.outline, icon: Icons.family_restroom_rounded, onTap: () => go(context, FamilyBookScreen(t))),
          ]),
        ),
      ),
    );
  }

  Widget _line(String a, String b, {Color color = C.dark, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Expanded(child: Text(a, style: bold ? T.label : T.body)), Text(b, style: TextStyle(fontFamily: kFont, fontSize: bold ? 18 : 15, color: color))]),
      );
}

class FamilyBookScreen extends StatefulWidget {
  final Trip t;
  const FamilyBookScreen(this.t);
  @override
  State<FamilyBookScreen> createState() => _FamilyBookScreenState();
}

class _FamilyBookScreenState extends State<FamilyBookScreen> {
  final _sel = {0, 1, 2};
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(title: 'مين مسافر معك؟'),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Floaty(child: Illus('family', height: 200)),
          const SizedBox(height: 12),
          const Text('ضيف أفراد عائلتك المسافرين معك. الحجز بيتعلّم "عائلي" وبينعرض هيك للسائق.', style: T.body),
          const SizedBox(height: 14),
          ChoiceCards(
            multi: true,
            options: const [('أنا', 'إيهاب · صاحب الحجز'), ('زوجتي', 'مرافقة'), ('ابني أحمد', '8 سنين'), ('أمي', 'مرافقة')],
            selected: _sel,
            onTap: (i) => setState(() => _sel.contains(i) ? _sel.remove(i) : _sel.add(i)),
          ),
          const InfoNote('سفر المرأة مع سائق رجل متاح فقط بوجود مَحرَم من العائلة بنفس الحجز.', warn: true),
        ]),
        bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Btn('تأكيد · ${_sel.length} مقاعد', onTap: () => go(context, BookMessageScreen(widget.t))))),
      );
}

class BookMessageScreen extends StatelessWidget {
  final Trip t;
  const BookMessageScreen(this.t);
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text('عرّف ${t.driver.name} عن حالك', style: T.h1),
          const Text('رسالة قصيرة بتزيد فرصة قبول حجزك.', style: T.body),
          const SizedBox(height: 16),
          const TextField(
            maxLines: 5,
            style: TextStyle(fontFamily: kFont, fontSize: 15, height: 1.7),
            decoration: InputDecoration(hintText: 'السلام عليكم، أنا طالب رايح عالجامعة، معي شنتاية وحدة...'),
          ),
        ]),
        bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Btn('إرسال طلب الحجز', icon: Icons.send_rounded, onTap: () => go(context, BookedScreen(t))))),
      );
}

class BookedScreen extends StatefulWidget {
  final Trip t;
  const BookedScreen(this.t);
  @override
  State<BookedScreen> createState() => _BookedScreenState();
}

class _BookedScreenState extends State<BookedScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: Stack(children: [
          Positioned.fill(child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: ConfettiPainter(_c.value)))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Spacer(),
                ScaleTransition(
                  scale: CurvedAnimation(parent: _c, curve: const Interval(0, .35, curve: Curves.elasticOut)),
                  child: const Illus('booked', height: 230, fallback: Icons.check_circle_rounded),
                ),
                const SizedBox(height: 12),
                const Enter(delay: 300, child: Text('انبعت طلبك!', style: T.h1)),
                Enter(delay: 420, child: Text('${widget.t.driver.name} رح يرد عليك بأقرب وقت، ورح يوصلك إشعار.', style: T.body, textAlign: TextAlign.center)),
                const SizedBox(height: 20),
                Enter(
                  delay: 520,
                  child: CardBox(
                    color: C.bg,
                    child: Column(children: [
                      _r('الرحلة', '${widget.t.from} ← ${widget.t.to}'),
                      _r('الموعد', widget.t.dep),
                      _r('المبلغ (كاش)', money(widget.t.price)),
                    ]),
                  ),
                ),
                const Spacer(),
                Btn('تابع حجزي', onTap: () => goReplace(context, const AppShell(initial: 2))),
                const SizedBox(height: 8),
                Btn('رجوع للرئيسية', kind: BtnKind.ghost, onTap: () => goReplace(context, const AppShell())),
              ]),
            ),
          ),
        ]),
      );

  Widget _r(String a, String b) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(a, style: T.body)), Text(b, style: T.label)]));
}

class ConfettiPainter extends CustomPainter {
  final double t;
  ConfettiPainter(this.t);
  static final _rnd = math.Random(7);
  static final _bits = List.generate(60, (_) => (_rnd.nextDouble(), _rnd.nextDouble() * .4, _rnd.nextDouble() * 6.28, _rnd.nextInt(4)));
  static const _colors = [C.primary, C.yellow, C.dark, C.primaryLight];
  @override
  void paint(Canvas canvas, Size size) {
    for (final (x, delay, rot, ci) in _bits) {
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final dx = x * size.width + math.sin(p * 8 + rot) * 20;
      final dy = -20 + p * size.height * .9;
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(rot + p * 10);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-4, -7, 8, 14), const Radius.circular(3)), Paint()..color = _colors[ci].withValues(alpha: 1 - p * .6));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ConfettiPainter o) => o.t != t;
}

class WomenRidesScreen extends StatelessWidget {
  const WomenRidesScreen();
  @override
  Widget build(BuildContext context) {
    final list = trips.where((t) => t.kind != RideKind.men).toList();
    return Scaffold(
      appBar: const TopBar(title: 'رحلات نسائية وعائلية'),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
        Container(
          height: 220,
          decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(28)),
          child: const Floaty(child: Illus('women_only', fit: BoxFit.contain)),
        ),
        const SizedBox(height: 16),
        const Text('بكل احترام وأمان', style: T.h1),
        const Text('الرحلات النسائية: سائقة موثّقة وراكبات فقط. الرحلات العائلية: عائلات مع مَحرَم.', style: T.body),
        const SizedBox(height: 16),
        for (final t in list) TripCard(t),
      ]),
    );
  }
}
