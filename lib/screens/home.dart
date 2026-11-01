import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../data/store.dart';
import '../data/location.dart';
import '../widgets/common.dart';
import '../widgets/dest_map.dart';
import 'search.dart';
import 'messages.dart';
import 'my_trips.dart';
import 'driver_join.dart' show HowWeVerifyScreen;

class HomeScreen extends StatefulWidget {
  const HomeScreen();
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _from = 'اللاذقية', _to = 'دمشق';
  int _day = 1;
  final _s = Store.i;
  late final _fromCtl = TextEditingController(text: _from);
  late final _toCtl = TextEditingController(text: _to);
  final _fromFocus = FocusNode(), _toFocus = FocusNode();
  int _active = 0; // 0 ولا شي، 1 من، 2 إلى
  double _turns = 0;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _fromFocus.addListener(() => _focusChanged(1, _fromFocus.hasFocus));
    _toFocus.addListener(() => _focusChanged(2, _toFocus.hasFocus));
  }

  @override
  void dispose() {
    _fromCtl.dispose();
    _toCtl.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  void _focusChanged(int field, bool has) {
    if (has) {
      final ctl = field == 1 ? _fromCtl : _toCtl;
      ctl.selection = TextSelection(baseOffset: 0, extentOffset: ctl.text.length);
      setState(() => _active = field);
      return;
    }
    // طلع من الخانة: إذا الكتابة مدينة صحيحة منثبتها، غير هيك منرجّع آخر مدينة
    final ctl = field == 1 ? _fromCtl : _toCtl;
    final c = cityNamed(ctl.text);
    setState(() {
      if (c != null && c.name != (field == 1 ? _to : _from)) {
        if (field == 1) {
          _from = c.name;
        } else {
          _to = c.name;
        }
      }
      ctl.text = field == 1 ? _from : _to;
      if (_active == field) _active = 0;
    });
  }

  void _choose(String name) {
    final f = _active == 0 ? 2 : _active;
    setState(() {
      if (f == 1) {
        if (name == _to) {
          _to = _from;
          _toCtl.text = _to;
        }
        _from = name;
        _fromCtl.text = name;
      } else {
        _to = name;
        _toCtl.text = name;
      }
    });
    if (f == 1) {
      _toFocus.requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  void _swap() {
    FocusScope.of(context).unfocus();
    setState(() {
      _turns += .5;
      final t = _from;
      _from = _to;
      _to = t;
      _fromCtl.text = _from;
      _toCtl.text = _to;
    });
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final p = await myPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (p == null) {
      toast(context, 'ما قدرنا نحدد موقعك، تأكد إنو الموقع مشغّل');
      return;
    }
    _choose(nearestCity(p.latitude, p.longitude, cities.map((c) => c.name)));
  }

  String get _greet {
    final h = DateTime.now().hour;
    if (h >= 4 && h < 12) return 'صباح الخير';
    if (h >= 12 && h < 17) return 'نهارك سعيد';
    return 'مسا الخير';
  }

  void _search(String from, String to) {
    if (from == to) {
      toast(context, 'اختار مدينتين مختلفتين');
      return;
    }
    _s.pax = _s.pax.clamp(1, 4);
    _s.search(from, to);
    go(context, ResultsScreen(from: from, to: to, day: _day, pax: _s.pax));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final next = _s.next;
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(padding: EdgeInsets.zero, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
          SizedBox(
            height: 270 + MediaQuery.of(context).padding.top,
            child: Stack(children: [
              const Positioned.fill(child: HomeScene()),
              Padding(
                padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 14, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('$_greet يا ${_s.name}', style: const TextStyle(fontFamily: kFont, fontSize: 16, color: Colors.white))),
                    SquareBtn(Icons.notifications_none_rounded, tooltip: 'الإشعارات', onTap: () => go(context, const NotificationsScreen())),
                  ]),
                  const SizedBox(height: 4),
                  const Enter(child: Text('لوين المشوار؟', style: TextStyle(fontFamily: kFont, fontSize: 38, color: Colors.white, height: 1.2))),
                ]),
              ),
            ]),
          ),
          Transform.translate(
            offset: const Offset(0, -64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Enter(delay: 120, child: _searchCard()),
                const SizedBox(height: 10),
                Enter(
                  delay: 160,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => go(context, const HowWeVerifyScreen()),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Row(children: [
                        Icon(Icons.verified_rounded, color: C.primary, size: 20),
                        SizedBox(width: 8),
                        Expanded(child: Text('كل السائقين موثّقين بمقابلة وفحص سيارة', style: TextStyle(fontFamily: kFont, fontSize: 13.5, color: C.dark))),
                        Text('كيف؟', style: TextStyle(fontFamily: kFont, fontSize: 13.5, color: C.primary)),
                      ]),
                    ),
                  ),
                ),
                if (next != null) ...[
                  const SizedBox(height: 14),
                  Enter(delay: 180, child: _NextTrip(next)),
                ],
                const SizedBox(height: 14),
                Enter(delay: 220, child: _kindCard()),
                const SizedBox(height: 24),
                DestinationsMap(from: _from, day: _day, onSearch: (city) => _search(_from, city)),
                if (_s.recent.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('رجّع آخر بحث', style: T.h3),
                  const SizedBox(height: 10),
                  for (final (a, b) in _s.recent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CardBox(
                        onTap: () => _search(a, b),
                        child: Row(children: [
                          Container(width: 40, height: 40, decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.history_rounded, color: C.muted)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('$a ← $b', style: T.label),
                              Text('${dayLabel(_day)} · ${roadKm(a, b)} كم · حوالي ${money(suggestedPrice(a, b))}', style: T.small),
                            ]),
                          ),
                          const Icon(Icons.chevron_left_rounded, color: C.muted),
                        ]),
                      ),
                    ),
                ],
              ]),
            ),
          ),
        ]),
        );
      },
    );
  }

  Widget _searchCard() {
    final q = _active == 1 ? _fromCtl.text : _toCtl.text;
    final current = _active == 1 ? _from : _to;
    final sugg = _active == 0 ? const <City>[] : searchCities(q == current ? '' : q, exclude: _active == 1 ? null : _from).take(6).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: C.dark.withValues(alpha: .12), blurRadius: 30, offset: const Offset(0, 12))]),
      child: Column(children: [
        Stack(children: [
          Column(children: [
            _input(Icons.radio_button_checked_rounded, 'من', 'منين طالع؟', _fromCtl, _fromFocus, 1),
            const Divider(height: 1, color: C.line),
            _input(Icons.place_rounded, 'إلى', 'لوين رايح؟', _toCtl, _toFocus, 2),
          ]),
          Positioned(
            left: 0,
            top: 38,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(side: BorderSide(color: C.border, width: 1.5)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _swap,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: AnimatedRotation(turns: _turns, duration: const Duration(milliseconds: 350), curve: Curves.easeOutBack, child: const Icon(Icons.swap_vert_rounded, color: C.primary)),
                ),
              ),
            ),
          ),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _active == 0
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(18)),
                  child: Column(children: [
                    if (_active == 1 && (q.isEmpty || q == current))
                      _suggRow(Icons.my_location_rounded, _locating ? 'عم نحدد موقعك...' : 'استخدم موقعي الحالي', null, _locating ? null : _locate),
                    for (final c in sugg) _suggRow(Icons.place_outlined, c.name, c.sub, () => _choose(c.name), selected: c.name == current),
                    if (sugg.isEmpty)
                      const Padding(padding: EdgeInsets.all(16), child: Text('ما لقينا هالمدينة. جرّب اسم تاني', style: T.small)),
                  ]),
                ),
        ),
        const Divider(height: 1, color: C.line),
        Row(children: [
          Expanded(child: _field(Icons.calendar_today_rounded, 'إيمتى', dayLabel(_day), () async {
            FocusScope.of(context).unfocus();
            final now = DateTime.now();
            final d = await showDatePicker(context: context, initialDate: now.add(Duration(days: _day)), firstDate: now, lastDate: now.add(const Duration(days: 60)));
            if (d != null) setState(() => _day = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays);
          })),
          Container(width: 1.5, height: 40, color: C.line),
          const SizedBox(width: 12),
          Expanded(child: _field(Icons.person_outline_rounded, 'الركاب', paxLabel(_s.pax), () async {
            FocusScope.of(context).unfocus();
            final r = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => PassengersScreen(initial: _s.pax)));
            if (r != null) setState(() => _s.pax = r);
          })),
        ]),
        const SizedBox(height: 8),
        Btn('دوّر على رحلة', icon: Icons.search_rounded, onTap: () {
          FocusScope.of(context).unfocus();
          _search(_from, _to);
        }),
      ]),
    );
  }

  Widget _input(IconData icon, String label, String hint, TextEditingController ctl, FocusNode focus, int field) => SizedBox(
        height: 64,
        child: Row(children: [
          Icon(icon, color: C.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label, style: T.small),
              TextField(
                controller: ctl,
                focusNode: focus,
                onChanged: (_) => setState(() {}),
                onTapOutside: (_) {},
                onSubmitted: (_) {
                  final r = searchCities(ctl.text, exclude: field == 2 ? _from : null);
                  if (r.isNotEmpty && ctl.text.trim().isNotEmpty) _choose(r.first.name);
                },
                textInputAction: field == 1 ? TextInputAction.next : TextInputAction.search,
                style: T.label,
                cursorColor: C.primary,
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  hintText: hint,
                  contentPadding: const EdgeInsets.only(top: 2, bottom: 2, left: 48),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ]),
          ),
          if (_active == field && ctl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 44),
              child: IconButton(
                tooltip: 'مسح',
                icon: const Icon(Icons.close_rounded, size: 18, color: C.muted),
                onPressed: () => setState(() => ctl.clear()),
              ),
            ),
        ]),
      );

  Widget _suggRow(IconData i, String title, String? sub, VoidCallback? onTap, {bool selected = false}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(i, size: 20, color: C.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: T.label),
                if (sub != null) Text(sub, style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (selected) const Icon(Icons.check_rounded, color: C.primary, size: 18),
          ]),
        ),
      );

  Widget _kindCard() {
    final f = _s.female;
    return CardBox(
      color: C.dark,
      onTap: () => go(context, const WomenRidesScreen()),
      child: Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(14)), child: Icon(f ? Icons.verified_user_rounded : Icons.family_restroom_rounded, color: C.dark)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f ? 'رحلات نسائية' : 'سفر عائلي', style: const TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 16)),
            Text(f ? 'سائقات موثّقات وراكبات بس' : 'سافر مع أهلك، والحجز بيتعلّم عائلي', style: const TextStyle(fontFamily: kFont, color: C.tint, fontSize: 12.5)),
          ]),
        ),
        const Icon(Icons.chevron_left_rounded, color: Colors.white),
      ]),
    );
  }

  Widget _field(IconData icon, String label, String value, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 62,
          child: Row(children: [
            Icon(icon, color: C.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label, style: T.small),
                Text(value, style: T.label, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      );
}

/// بطاقة "رحلتك الجاية" مع عدّاد للوقت المتبقي.
class _NextTrip extends StatelessWidget {
  final Booking b;
  const _NextTrip(this.b);

  String get _left {
    final p = b.t.dep.split(':');
    final now = DateTime.now();
    final at = DateTime(now.year, now.month, now.day + b.t.day, int.parse(p[0]), int.parse(p[1]));
    final m = at.difference(now).inMinutes;
    if (m <= 0) return 'هلق';
    if (m < 60) return 'بعد $m دقيقة';
    final h = (m / 60).round();
    if (h < 24) return h == 1 ? 'بعد ساعة' : h == 2 ? 'بعد ساعتين' : 'بعد $h ساعات';
    final d = (h / 24).round();
    return d == 1 ? 'بعد يوم' : d == 2 ? 'بعد يومين' : 'بعد $d أيام';
  }

  @override
  Widget build(BuildContext context) {
    final pending = b.status == BStatus.pending;
    return Press(
      onTap: () => go(context, TicketScreen(b)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [C.yellow, Color(0xFFFFE08F)], begin: Alignment.topRight, end: Alignment.bottomLeft),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(children: [
          Avatar(b.t.driver, size: 50),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pending ? 'بانتظار موافقة ${b.t.driver.name}' : 'رحلتك الجاية · $_left', style: const TextStyle(fontFamily: kFont, fontSize: 12.5, color: C.warn)),
              Text('${b.t.from} ← ${b.t.to}', style: const TextStyle(fontFamily: kFont, fontSize: 19, color: C.dark)),
              Text('${dayLabel(b.t.day)} ${b.t.dep} · ${b.t.fromSpot}', style: const TextStyle(fontFamily: kFont, fontSize: 12.5, color: C.dark)),
            ]),
          ),
          Container(width: 40, height: 40, decoration: const BoxDecoration(color: C.dark, shape: BoxShape.circle), child: const Icon(Icons.confirmation_number_outlined, color: Colors.white, size: 20)),
        ]),
      ),
    );
  }
}

/// مشهد الرئيسية: سما حسب الوقت، تلال، مدينة، وسيارة ماشية عالطريق.
class HomeScene extends StatefulWidget {
  const HomeScene({super.key});
  @override
  State<HomeScene> createState() => _HomeSceneState();
}

class _HomeSceneState extends State<HomeScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  final _night = DateTime.now().hour >= 19 || DateTime.now().hour < 5;
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _ScenePainter(_c.value, _night)));
}

class _ScenePainter extends CustomPainter {
  final double t;
  final bool night;
  _ScenePainter(this.t, this.night);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final base = h - 66; // فوق بطاقة البحث
    final sky = night ? const [Color(0xFF053744), Color(0xFF0A7FB5)] : const [C.primary, Color(0xFF6FD0FA)];
    canvas.drawRect(Offset.zero & s, Paint()..shader = LinearGradient(colors: sky, begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(Offset.zero & s));

    // شمس أو هلال
    final sun = Offset(w * .2, h * .3);
    if (night) {
      final r = math.Random(3);
      for (var i = 0; i < 28; i++) {
        final tw = .4 + .6 * (math.sin(t * 6.28 * 2 + i) * .5 + .5);
        canvas.drawCircle(Offset(r.nextDouble() * w, r.nextDouble() * h * .55), r.nextDouble() * 1.3 + .4, Paint()..color = Colors.white.withValues(alpha: tw * .8));
      }
      canvas.drawCircle(sun, 18, Paint()..color = C.yellow);
      canvas.drawCircle(sun + const Offset(-8, -5), 16, Paint()..color = sky[0]);
    } else {
      canvas.drawCircle(sun, 34, Paint()..color = Colors.white.withValues(alpha: .18));
      canvas.drawCircle(sun, 22, Paint()..color = C.yellow);
    }

    // غيمات بتتحرك
    if (!night) {
      final cp = Paint()..color = Colors.white.withValues(alpha: .55);
      for (final (y, sp, sc) in const [(.22, 1.0, 1.0), (.4, .6, .7)]) {
        final x = ((t * sp) % 1) * (w + 160) - 80;
        canvas.drawOval(Rect.fromCenter(center: Offset(x, h * y), width: 70 * sc, height: 22 * sc), cp);
        canvas.drawOval(Rect.fromCenter(center: Offset(x + 18 * sc, h * y - 8 * sc), width: 40 * sc, height: 24 * sc), cp);
      }
    }

    // تلال بعيدة مع مدينة وسرو
    final far = Paint()..color = Colors.white.withValues(alpha: night ? .08 : .16);
    final hill = Path()..moveTo(0, base - 40);
    for (var x = 0.0; x <= w; x += 8) {
      hill.lineTo(x, base - 46 + math.sin(x / w * math.pi * 2.2 + .6) * 14);
    }
    hill
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hill, far);
    final cx = w * .72, by = base - 54;
    final city = Path()
      ..addRect(Rect.fromLTWH(cx - 70, by - 6, 26, 14))
      ..addRect(Rect.fromLTWH(cx - 42, by - 22, 18, 30))
      ..addRect(Rect.fromLTWH(cx - 22, by - 12, 30, 20))
      ..addRect(Rect.fromLTWH(cx + 10, by - 34, 14, 42))
      ..addRect(Rect.fromLTWH(cx + 26, by - 18, 22, 26))
      ..addRect(Rect.fromLTWH(cx + 50, by - 8, 20, 16));
    canvas.drawPath(city, far);
    for (final x in [w * .08, w * .14, w * .48]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x, base - 52), width: 9, height: 30), far);
    }

    // تلّة قريبة والطريق
    final near = Path()..moveTo(0, base - 22);
    for (var x = 0.0; x <= w; x += 8) {
      near.lineTo(x, base - 24 + math.sin(x / w * math.pi * 1.4) * 8);
    }
    near
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(near, Paint()..color = Colors.white.withValues(alpha: night ? .12 : .24));
    final roadY = base - 10;
    canvas.drawRect(Rect.fromLTWH(0, roadY - 3, w, 6), Paint()..color = C.dark.withValues(alpha: .35));
    final dash = Paint()..color = Colors.white.withValues(alpha: .7);
    final off = (t * 40 * 14) % 40;
    for (var x = -off; x < w; x += 40) {
      canvas.drawRect(Rect.fromLTWH(x, roadY - .8, 18, 1.6), dash);
    }

    // السيارة: من اليمين لليسار مع ارتجاج خفيف
    final carX = w + 60 - ((t * 1.0) % 1) * (w + 120);
    final bob = math.sin(t * 6.28 * 18) * .8;
    canvas.save();
    canvas.translate(carX, roadY - 10 + bob);
    final body = Paint()..color = C.yellow;
    canvas.drawRRect(RRect.fromLTRBR(-26, -8, 26, 6, const Radius.circular(6)), body);
    final cabin = Path()
      ..moveTo(-14, -8)
      ..lineTo(-8, -18)
      ..lineTo(10, -18)
      ..lineTo(18, -8)
      ..close();
    canvas.drawPath(cabin, body);
    final glass = Paint()..color = night ? const Color(0xFFFFF1C2) : const Color(0xFFBDEBFF);
    canvas.drawPath(
        Path()
          ..moveTo(-11, -9)
          ..lineTo(-7, -16)
          ..lineTo(0, -16)
          ..lineTo(0, -9)
          ..close(),
        glass);
    canvas.drawPath(
        Path()
          ..moveTo(2, -9)
          ..lineTo(2, -16)
          ..lineTo(9, -16)
          ..lineTo(15, -9)
          ..close(),
        glass);
    if (night) {
      canvas.drawPath(
          Path()
            ..moveTo(-26, -3)
            ..lineTo(-90, -14)
            ..lineTo(-90, 10)
            ..close(),
          Paint()..color = const Color(0xFFFFF1C2).withValues(alpha: .25));
    }
    canvas.drawCircle(const Offset(-24, -3), 2, Paint()..color = Colors.white);
    final wheel = Paint()..color = C.dark;
    for (final wx in [-15.0, 15.0]) {
      canvas.drawCircle(Offset(wx, 6), 6, wheel);
      canvas.drawCircle(Offset(wx, 6), 2.4, Paint()..color = Colors.white70);
      final a = -t * 6.28 * 40;
      canvas.drawLine(Offset(wx + math.cos(a) * 4, 6 + math.sin(a) * 4), Offset(wx - math.cos(a) * 4, 6 - math.sin(a) * 4), Paint()
        ..color = Colors.white54
        ..strokeWidth = 1);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScenePainter o) => o.t != t;
}
