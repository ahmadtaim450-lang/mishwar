import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../widgets/common.dart';
import 'trip.dart';

export 'trip.dart' show WomenRidesScreen;

class PlacesScreen extends StatefulWidget {
  final String title;
  const PlacesScreen({this.title = 'لوين رايح؟'});
  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final list = cities.where((c) => _q.isEmpty || c.name.contains(_q) || c.sub.contains(_q)).toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: TopBar(title: widget.title, close: true),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
        TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _q = v.trim()),
          style: const TextStyle(fontFamily: kFont, fontSize: 17),
          decoration: const InputDecoration(hintText: 'مدينة، حي، أو كراج', prefixIcon: Icon(Icons.search_rounded, color: C.primary)),
        ),
        const SizedBox(height: 8),
        RowItem(Icons.my_location_rounded, 'استخدم موقعي الحالي', onTap: () => Navigator.pop(context, 'اللاذقية')),
        Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(_q.isEmpty ? 'مدن شائعة' : 'نتائج', style: T.small)),
        for (var i = 0; i < list.length; i++)
          Enter(
            delay: i * 40,
            child: RowItem(Icons.place_outlined, list[i].name, sub: list[i].sub, onTap: () => Navigator.pop(context, list[i].name)),
          ),
      ]),
    );
  }
}

class PassengersScreen extends StatefulWidget {
  final int initial;
  const PassengersScreen({this.initial = 1});
  @override
  State<PassengersScreen> createState() => _PassengersScreenState();
}

class _PassengersScreenState extends State<PassengersScreen> {
  late int _n = widget.initial;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Text('كم راكب؟', style: T.h1),
            const SizedBox(height: 30),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 4; i++)
                AnimatedScale(
                  scale: i < _n ? 1 : .85,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(Icons.person_rounded, size: 48, color: i < _n ? C.primary : const Color(0xFFC7D1D1)),
                ),
            ]),
            const SizedBox(height: 30),
            Counter(value: _n, max: 4, big: true, onChanged: (v) => setState(() => _n = v)),
            const SizedBox(height: 16),
            const Text('فيك تحجز لحد 4 مقاعد بنفس الرحلة.', style: T.small),
            const Spacer(),
            Btn('تأكيد', onTap: () => Navigator.pop(context, _n)),
          ]),
        ),
      );
}

class ResultsScreen extends StatefulWidget {
  final String from, to, date;
  final int pax;
  const ResultsScreen({required this.from, required this.to, required this.date, required this.pax});
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  int _sort = 0;
  bool _loading = true;
  Set<RideKind> _kinds = {RideKind.men, RideKind.family};
  bool _instantOnly = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    var list = trips.where((t) => t.to == widget.to && _kinds.contains(t.kind) && (!_instantOnly || t.instant)).toList();
    if (_sort == 1) list.sort((a, b) => a.price.compareTo(b.price));
    return Scaffold(
      appBar: TopBar(
        title: '${widget.from} ← ${widget.to}',
        sub: '${widget.date} · ${widget.pax == 1 ? 'راكب واحد' : '${widget.pax} ركاب'}',
        actions: [SquareBtn(Icons.tune_rounded, solid: true, tooltip: 'فلترة', onTap: _openFilters)],
      ),
      body: _loading
          ? ListView(padding: const EdgeInsets.all(20), children: List.generate(4, (_) => const _Skeleton()))
          : list.isEmpty
              ? EmptyState(
                  image: 'empty_search',
                  title: 'ما في رحلات لهاد اليوم',
                  body: 'فعّل تنبيه ورح نبعتلك إشعار أول ما حدا ينشر رحلة على هالطريق.',
                  actions: [
                    Btn('فعّل تنبيه', icon: Icons.notifications_active_outlined, onTap: () => go(context, const AlertCreatedScreen())),
                  ],
                )
              : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
                  SizedBox(
                    height: 42,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final (i, l) in const [(0, 'الأبكر'), (1, 'الأرخص')])
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Text(l, style: TextStyle(fontFamily: kFont, color: _sort == i ? Colors.white : C.dark)),
                            selected: _sort == i,
                            selectedColor: C.dark,
                            backgroundColor: Colors.white,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _sort = i),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Text('${list.length} رحلات متاحة', style: T.small),
                  const SizedBox(height: 8),
                  for (var i = 0; i < list.length; i++) Enter(delay: i * 80, child: TripCard(list[i])),
                ]),
    );
  }

  void _openFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (_) => StatefulBuilder(builder: (ctx, set) {
        void upd(VoidCallback f) {
          set(f);
          setState(() {});
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(5)))),
            const SizedBox(height: 16),
            const Text('رتّب وفلتر', style: T.h2),
            const SizedBox(height: 14),
            const Text('رتّب حسب', style: T.label),
            const SizedBox(height: 8),
            ChoiceCards(options: const [('الأبكر', 'حسب ساعة الانطلاق'), ('الأرخص', 'أقل سعر للمقعد')], selected: {_sort}, onTap: (i) => upd(() => _sort = i)),
            const Text('نوع الرحلة', style: T.label),
            const SizedBox(height: 8),
            ChipGroup(
              options: const ['رجال', 'نسائية', 'عائلية'],
              selected: {for (final k in _kinds) k.index},
              onTap: (i) => upd(() {
                final k = RideKind.values[i];
                _kinds = _kinds.contains(k) ? ({..._kinds}..remove(k)) : {..._kinds, k};
              }),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _instantOnly,
              activeColor: C.primary,
              title: const Text('حجز فوري فقط', style: T.label),
              onChanged: (v) => upd(() => _instantOnly = v),
            ),
            const SizedBox(height: 8),
            Btn('اعرض النتائج', onTap: () => Navigator.pop(ctx)),
          ]),
        );
      }),
    );
  }
}

class _Skeleton extends StatefulWidget {
  const _Skeleton();
  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: .45, end: 1.0).animate(_c),
        child: Container(
          height: 150,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 60, width: 160, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(12))),
            const Spacer(),
            Row(children: [
              Container(width: 38, height: 38, decoration: const BoxDecoration(color: C.line, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Container(height: 14, width: 120, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(8))),
            ]),
          ]),
        ),
      );
}

class TripCard extends StatelessWidget {
  final Trip t;
  const TripCard(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: CardBox(
          onTap: () => go(context, TripDetailsScreen(t)),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Timeline(a: t.from, b: t.to, ta: t.dep, tb: t.arr, sa: t.fromSpot, sb: t.toSpot)),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(t.price), style: const TextStyle(fontFamily: kFont, fontSize: 17, color: C.primary)),
                const Text('للمقعد', style: T.small),
                const SizedBox(height: 6),
                if (t.instant) const Badge2('⚡ فوري', bg: C.warnBg, fg: C.warn),
              ]),
            ]),
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: C.line)),
            Row(children: [
              Avatar(t.driver, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.driver.name, style: T.label),
                  Text('★ ${t.driver.rating} · ${t.car}', style: T.small),
                ]),
              ),
              KindBadge(t.kind),
              const SizedBox(width: 6),
              Badge2('${t.seatsLeft} مقاعد'),
            ]),
          ]),
        ),
      );
}

class AlertCreatedScreen extends StatelessWidget {
  const AlertCreatedScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: EmptyState(
            image: 'alert_bell',
            title: 'التنبيه شغّال',
            body: 'رح نبعتلك إشعار أول ما تنتشر رحلة على هالطريق.',
            actions: [Btn('تمام', onTap: () => Navigator.pop(context))],
          ),
        ),
      );
}
