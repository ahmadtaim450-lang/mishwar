import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../data/store.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'driver_join.dart';

class PublishStartScreen extends StatelessWidget {
  const PublishStartScreen();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) => switch (Store.i.driverStatus) {
          DStatus.none => const DriverJoinIntro(),
          DStatus.approved => const _PublishHome(),
          _ => const SafeArea(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 0), child: Text('طلب السائق', style: T.h1)),
                Expanded(child: DriverStatusBody()),
              ]),
            ),
        },
      );
}

class _PublishHome extends StatelessWidget {
  const _PublishHome();
  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Enter(child: Badge2('✓ سائق موثّق', bg: C.dark, fg: Colors.white)),
          const SizedBox(height: 8),
          const Enter(child: Text('عندك مقاعد فاضية؟', style: T.h1)),
          const Enter(delay: 100, child: Text('انشر رحلتك بدقيقة وقسّم مصروف الطريق.', style: T.body)),
          const SizedBox(height: 16),
          Container(
            height: 260,
            child: const Floaty(child: Illus('onboard2', fit: BoxFit.contain)),
          ),
          const SizedBox(height: 20),
          for (final (i, t) in const [(Icons.route_rounded, 'حدد المسار والوقفات'), (Icons.payments_outlined, 'سعر مقترح عادل للمقعد'), (Icons.verified_user_outlined, 'اختار مين يطلع معك')])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(12)), child: Icon(i, color: C.primary, size: 20)),
                const SizedBox(width: 12),
                Text(t, style: T.label),
              ]),
            ),
          const SizedBox(height: 14),
          Btn('ابدأ النشر', icon: Icons.add_rounded, onTap: () => go(context, const PublishFlow())),
        ]),
      );
}

class PublishFlow extends StatefulWidget {
  final String? from, to;
  const PublishFlow({this.from, this.to});
  @override
  State<PublishFlow> createState() => _PublishFlowState();
}

class _PublishFlowState extends State<PublishFlow> {
  final _pc = PageController();
  int _step = 0;
  late String _from = widget.from ?? '', _to = widget.to ?? '';
  final _stops = <int>{};
  List<String> get _stopList => _from.isEmpty || _to.isEmpty ? const [] : stopsBetween(_from, _to);
  int get _suggest => _from.isEmpty || _to.isEmpty ? 75000 : suggestedPrice(_from, _to);
  late final bool _female = Store.i.female;
  int _day = 1;
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  int _seats = 3;
  int _price = 75000;
  late int _step0 = widget.from != null && widget.to != null ? 2 : 0;
  int _booking = 1;
  final _who = <int>{0};
  final _prefs = <int>{0, 1};

  static const _total = 8;

  @override
  void initState() {
    super.initState();
    if (_step0 > 0) {
      _step = _step0;
      _onRoute();
      WidgetsBinding.instance.addPostFrameCallback((_) => _pc.jumpToPage(_step));
    }
  }

  void _onRoute() {
    _stops
      ..clear()
      ..addAll(List.generate(_stopList.length, (i) => i));
    _price = _suggest;
  }

  void _publish() {
    final d = DateTime.now().add(Duration(days: _day));
    final dep = _time.hour * 60 + _time.minute;
    final dur = durationMin(_from, _to);
    String hm(int m) => '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    final t = Trip(
      id: 'me-${d.millisecondsSinceEpoch}',
      from: _from,
      fromSpot: cities.firstWhere((c) => c.name == _from).sub.split(' · ').first,
      to: _to,
      toSpot: cities.firstWhere((c) => c.name == _to).sub.split(' · ').first,
      dep: hm(dep),
      arr: hm(dep + dur),
      duration: fmtDur(dur),
      price: _price,
      seatsLeft: _seats,
      seatsTotal: _seats,
      driver: me,
      car: Store.i.app == null ? 'سيارتي' : '${Store.i.app!.car} · ${Store.i.app!.color}',
      plate: Store.i.app?.plate ?? '',
      kind: _who.contains(1) ? RideKind.family : (_female ? RideKind.women : RideKind.men),
      instant: _booking == 0,
      stops: [for (var i = 0; i < _stopList.length; i++) if (_stops.contains(i)) _stopList[i]],
      day: _day,
    );
    Store.i.publish(t);
    goReplace(context, PublishedScreen(from: _from, to: _to));
  }

  void _next() {
    if ((_step == 0 && _from.isEmpty) || (_step == 1 && _to.isEmpty)) {
      toast(context, 'اختار المدينة أول');
      return;
    }
    if (_step == 1) _onRoute();
    if (_step == _total - 1) {
      _publish();
      return;
    }
    setState(() => _step++);
    _pc.animateToPage(_step, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _step--);
    _pc.animateToPage(_step, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(children: [
                SquareBtn(Icons.arrow_forward_rounded, tooltip: 'رجوع', onTap: _back),
                const SizedBox(width: 12),
                Text('الخطوة ${_step + 1} من $_total', style: T.small),
              ]),
            ),
            StepBar(_step + 1, _total),
            Expanded(
              child: PageView(
                controller: _pc,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _page('منين طالع؟', _cityPick(_from, (v) => setState(() => _from = v))),
                  _page('ولوين رايح؟', _cityPick(_to, (v) => setState(() => _to = v), exclude: _from)),
                  _page('بتوقف بمدن عالطريق؟', Column(children: [
                    Text(_stopList.isEmpty ? 'ما في مدن رئيسية بين $_from و$_to، الطريق مباشر.' : 'الوقفات بتجيبلك ركاب أكتر. هدول المدن عطريقك:', style: T.body),
                    const SizedBox(height: 12),
                    if (_stopList.isNotEmpty)
                      ChoiceCards(multi: true, options: [for (final c in _stopList) (c, '${roadKm(_from, c)} كم من $_from · +10 د')], selected: _stops, onTap: (i) => setState(() => _stops.contains(i) ? _stops.remove(i) : _stops.add(i))),
                    const InfoNote('رح نقترح عليك وقفة استراحة إذا الطريق أكتر من ساعتين.', icon: Icons.local_cafe_outlined),
                  ])),
                  _page('إيمتى طالع؟', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      height: 84,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: 7,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final d = DateTime.now().add(Duration(days: i));
                          const names = ['اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت', 'أحد'];
                          final on = i == _day;
                          return Press(
                            onTap: () => setState(() => _day = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 64,
                              decoration: BoxDecoration(color: on ? C.primary : Colors.white, borderRadius: BorderRadius.circular(18)),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text(i == 0 ? 'اليوم' : names[d.weekday - 1], style: TextStyle(fontFamily: kFont, fontSize: 12, color: on ? Colors.white : C.muted)),
                                Text('${d.day}', style: TextStyle(fontFamily: kFont, fontSize: 22, color: on ? Colors.white : C.dark)),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('ساعة الانطلاق', style: T.label),
                    const SizedBox(height: 8),
                    CardBox(
                      onTap: () async {
                        final t = await showTimePicker(context: context, initialTime: _time);
                        if (t != null) setState(() => _time = t);
                      },
                      child: Center(child: Text(_time.format(context), style: const TextStyle(fontFamily: kFont, fontSize: 44, color: C.dark))),
                    ),
                  ])),
                  _page('كم مقعد فاضي؟', Column(children: [
                    const SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var i = 0; i < 7; i++)
                        AnimatedOpacity(opacity: i < _seats ? 1 : .2, duration: const Duration(milliseconds: 200), child: const Icon(Icons.event_seat_rounded, color: C.primary, size: 36)),
                    ]),
                    const SizedBox(height: 30),
                    Counter(value: _seats, max: 7, big: true, onChanged: (v) => setState(() => _seats = v)),
                    const SizedBox(height: 16),
                    const Text('نصيحة: مقعدين ورا بيعطوا راحة أكتر للركاب', style: T.small),
                  ])),
                  _page('سعر المقعد', Column(children: [
                    Text('المسافة ${roadKm(_from.isEmpty ? 'اللاذقية' : _from, _to.isEmpty ? 'دمشق' : _to)} كم تقريباً. السعر المقترح ${money(_suggest)} محسوب على المسافة وسعر البنزين، والهدف تقسيم المصروف مو الربح.', style: T.body),
                    const SizedBox(height: 24),
                    CardBox(
                      child: Column(children: [
                        Counter(value: _price, min: 10000, max: 400000, big: true, fmt: (v) => '${(v / 1000).round()} ألف', onChanged: (v) => setState(() => _price = v > _price ? _price + 5000 : _price - 5000)),
                        const SizedBox(height: 10),
                        const Text('ليرة سورية للمقعد', style: T.small),
                        const SizedBox(height: 16),
                        Builder(builder: (_) {
                          final ok = (_price - _suggest).abs() <= _suggest * .2;
                          return Badge2(ok ? 'سعر عادل، رح تنحجز بسرعة' : (_price > _suggest ? 'أغلى من المقترح، ممكن يقلّوا الطلبات' : 'أرخص من المقترح بكتير'), bg: ok ? C.tint : C.warnBg, fg: ok ? C.dark : C.warn);
                        }),
                      ]),
                    ),
                  ])),
                  _page('مين بيطلع معك؟', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ChoiceCards(options: const [('حجز فوري', 'الركاب بينحجزلن مباشرة'), ('موافقة يدوية', 'بتراجع كل طلب')], selected: {_booking}, onTap: (i) => setState(() => _booking = i)),
                    const SizedBox(height: 8),
                    const Text('نوع الرحلة', style: T.label),
                    const SizedBox(height: 8),
                    ChoiceCards(
                      options: _female ? const [('راكبات بس', 'رحلة نسائية'), ('عائلات', 'مع أهلن')] : const [('رجال بس', 'ركاب شباب'), ('عائلات', 'عائلات مسافرة سوا')],
                      selected: {_who.contains(1) ? 1 : 0},
                      onTap: (i) => setState(() => _who
                        ..clear()
                        ..add(i)),
                    ),
                    InfoNote(_female ? 'الرحلة النسائية بتنعرض للراكبات بس.' : 'الراكبات بيحجزوا مع السائقات، أو ضمن عائلتها.', icon: Icons.shield_outlined),
                  ])),
                  _page('تفضيلات الرحلة', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ChipGroup(options: const ['ممنوع التدخين', 'وقفات استراحة', 'مكيّف', 'أغاني بالسيارة', 'بلا أغاني', 'شناتي كبيرة', 'بحب الهدوء'], selected: _prefs, onTap: (i) => setState(() => _prefs.contains(i) ? _prefs.remove(i) : _prefs.add(i))),
                    const SizedBox(height: 16),
                    const TextField(maxLines: 4, style: TextStyle(fontFamily: kFont, fontSize: 15), decoration: InputDecoration(hintText: 'ملاحظة للركاب (اختياري)')),
                  ])),
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: Btn(_step == _total - 1 ? 'انشر الرحلة' : 'متابعة', onTap: _next)),
          ]),
        ),
      ),
    );
  }

  Widget _page(String title, Widget child) => ListView(padding: const EdgeInsets.all(20), children: [Enter(child: Text(title, style: T.h1)), const SizedBox(height: 14), child]);

  Widget _cityPick(String value, ValueChanged<String> on, {String? exclude}) => Column(children: [
        for (final c in cities.where((c) => c.name != exclude))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Press(
              onTap: () {
                on(c.name);
                if (_step == 0 && c.name == _to) _to = '';
                Future.delayed(const Duration(milliseconds: 180), _next);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: value == c.name ? C.primary : Colors.white, width: 2)),
                child: Row(children: [
                  const Icon(Icons.place_outlined, color: C.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.name, style: T.label), Text(c.sub, style: T.small)])),
                ]),
              ),
            ),
          ),
      ]);
}

class PublishedScreen extends StatelessWidget {
  final String from, to;
  const PublishedScreen({required this.from, required this.to});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.primary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(),
              const Floaty(child: Illus('published', height: 260)),
              const SizedBox(height: 12),
              const Enter(child: Text('رحلتك منشورة!', style: TextStyle(fontFamily: kFont, fontSize: 42, color: Colors.white))),
              const Enter(delay: 120, child: Text('الركاب عم يشوفوها هلق. رح يوصلك إشعار مع كل طلب حجز.', textAlign: TextAlign.center, style: TextStyle(fontFamily: kFont, fontSize: 16, color: Colors.white))),
              const SizedBox(height: 12),
              Badge2('$from ← $to', bg: C.dark, fg: Colors.white),
              const Spacer(),
              Btn('شوف رحلتي', kind: BtnKind.white, onTap: () => goReplace(context, const AppShell(initial: 1))),
              const SizedBox(height: 10),
              Btn('انشر رحلة الرجعة', kind: BtnKind.dark, icon: Icons.swap_horiz_rounded, onTap: () => goReplace(context, PublishFlow(from: to, to: from))),
            ]),
          ),
        ),
      );
}
