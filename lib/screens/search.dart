import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../data/store.dart';
import '../data/location.dart';
import '../widgets/common.dart';
import 'trip.dart';

export 'trip.dart' show WomenRidesScreen;

class PlacesScreen extends StatefulWidget {
  final String title;
  final String? exclude;
  const PlacesScreen({this.title = 'لوين رايح؟', this.exclude});
  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  String _q = '';
  bool _locating = false;

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    final p = await myPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (p == null) {
      toast(context, 'ما قدرنا نحدد موقعك، تأكد إنو الموقع مشغّل');
      return;
    }
    final names = cities.map((c) => c.name).where((n) => n != widget.exclude);
    Navigator.pop(context, nearestCity(p.latitude, p.longitude, names));
  }

  @override
  Widget build(BuildContext context) {
    final list = searchCities(_q, exclude: widget.exclude);
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
        RowItem(Icons.my_location_rounded, _locating ? 'عم نحدد موقعك...' : 'استخدم موقعي الحالي', onTap: _locating ? null : _useLocation),
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
  final String from, to;
  final int day, pax;
  const ResultsScreen({required this.from, required this.to, this.day = 1, this.pax = 1});
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  int _sort = 0;
  bool _loading = true;
  Object? _error;
  List<Trip> _all = const [];
  late final bool _female = Store.i.female;
  late final List<RideKind> _allowed = _female ? const [RideKind.women, RideKind.family] : const [RideKind.men, RideKind.family];
  late Set<RideKind> _kinds = {..._allowed};
  bool _instantOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Store.i.searchTrips(widget.from, widget.to, widget.day, widget.pax);
      if (mounted) setState(() => _all = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _all.where((t) => _allowed.contains(t.kind)).toList();
    final list = all.where((t) => _kinds.contains(t.kind) && (!_instantOnly || t.instant)).toList();
    list.sort((a, b) => _sort == 1 ? a.price.compareTo(b.price) : a.dep.compareTo(b.dep));
    final hidden = all.length - list.length;
    return Scaffold(
      appBar: TopBar(
        title: '${widget.from} ← ${widget.to}',
        sub: '${dayLabel(widget.day)} · ${paxLabel(widget.pax)} · ${roadKm(widget.from, widget.to)} كم',
        actions: [SquareBtn(Icons.tune_rounded, solid: true, tooltip: 'فلترة', onTap: _openFilters)],
      ),
      body: _loading
          ? ListView(padding: const EdgeInsets.all(20), children: List.generate(4, (_) => const _Skeleton()))
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
          : list.isEmpty
              ? EmptyState(
                  image: 'empty_search',
                  title: hidden > 0 ? 'الفلتر مخبّي $hidden' : 'ما في رحلات لهاد اليوم',
                  body: hidden > 0 ? 'في رحلات بس ما بتطابق الفلتر. خفّف الفلترة لتشوفها.' : 'فعّل تنبيه ورح نبعتلك إشعار أول ما حدا ينشر رحلة على هالطريق.',
                  actions: [
                    Btn('فعّل تنبيه', icon: Icons.notifications_active_outlined, onTap: () => go(context, const AlertCreatedScreen())),
                  ],
                )
              : RefreshIndicator(
                  color: C.primary,
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
                  if (!Store.i.live) const DemoBanner(),
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
                  Text('${tripsLabel(list.length)} ${dayLabel(widget.day)} · السعر المقترح ${money(suggestedPrice(widget.from, widget.to))}', style: T.small),
                  const SizedBox(height: 8),
                  for (var i = 0; i < list.length; i++) Enter(delay: i * 80, child: TripCard(list[i], pax: widget.pax)),
                  const SizedBox(height: 6),
                  CardBox(
                    color: C.tint,
                    onTap: () => go(context, const AlertCreatedScreen()),
                    child: const Row(children: [
                      Icon(Icons.notifications_active_outlined, color: C.primary),
                      SizedBox(width: 10),
                      Expanded(child: Text('ما لقيت الوقت المناسب؟ فعّل تنبيه لهالطريق', style: T.label)),
                    ]),
                  ),
                ]),
                ),
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
              options: [for (final k in _allowed) kindLabel(k)],
              selected: {for (var i = 0; i < _allowed.length; i++) if (_kinds.contains(_allowed[i])) i},
              onTap: (i) => upd(() {
                final k = _allowed[i];
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
  final int pax;
  const TripCard(this.t, {this.pax = 1});
  @override
  Widget build(BuildContext context) {
    final full = t.seatsLeft < pax;
    final mine = Store.i.bookingOf(t) != null;
    return Opacity(
      opacity: full ? .55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: CardBox(
          onTap: () => go(context, TripDetailsScreen(t, pax: pax)),
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
              if (mine)
                const Badge2('حجزت فيها', bg: C.dark, fg: Colors.white)
              else
                Badge2(full ? 'باقي ${seatsLabel(t.seatsLeft)} بس' : 'باقي ${seatsLabel(t.seatsLeft)}', bg: t.seatsLeft == 1 ? C.warnBg : C.tint, fg: t.seatsLeft == 1 ? C.warn : C.dark),
            ]),
            if (t.stops.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const Icon(Icons.alt_route_rounded, size: 16, color: C.muted),
                  const SizedBox(width: 6),
                  Text('عبر ${t.stops.join('، ')} · ${t.duration}', style: T.small),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
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
