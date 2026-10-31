import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../widgets/common.dart';
import 'search.dart';
import 'messages.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen();
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _from = 'اللاذقية', _to = 'دمشق';
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  int _pax = 1;

  String get _dateLabel {
    const months = ['كانون 2', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين 1', 'تشرين 2', 'كانون 1'];
    final diff = DateTime(_date.year, _date.month, _date.day).difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)).inDays;
    final prefix = diff == 0 ? 'اليوم، ' : diff == 1 ? 'بكرا، ' : '';
    return '$prefix${_date.day} ${months[_date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: EdgeInsets.zero, children: [
      Container(
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 90),
        decoration: const BoxDecoration(color: C.primary),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('السلام عليكم، إيهاب', style: TextStyle(fontFamily: kFont, fontSize: 16, color: Colors.white))),
            SquareBtn(Icons.notifications_none_rounded, tooltip: 'الإشعارات', onTap: () => go(context, const NotificationsScreen())),
          ]),
          const SizedBox(height: 6),
          const Enter(child: Text('لوين رايح اليوم؟', style: TextStyle(fontFamily: kFont, fontSize: 36, color: Colors.white))),
        ]),
      ),
      Transform.translate(
        offset: const Offset(0, -70),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Enter(
            delay: 120,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: C.dark.withValues(alpha: .1), blurRadius: 30, offset: const Offset(0, 12))]),
              child: Column(children: [
                Stack(children: [
                  Column(children: [
                    _field(Icons.radio_button_checked_rounded, 'من', _from, () async {
                      final r = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const PlacesScreen(title: 'منين طالع؟')));
                      if (r != null) setState(() => _from = r);
                    }),
                    const Divider(height: 1, color: C.line),
                    _field(Icons.place_rounded, 'إلى', _to, () async {
                      final r = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const PlacesScreen(title: 'لوين رايح؟')));
                      if (r != null) setState(() => _to = r);
                    }),
                  ]),
                  Positioned(
                    left: 0,
                    top: 38,
                    child: Press(
                      onTap: () => setState(() {
                        final t = _from;
                        _from = _to;
                        _to = t;
                      }),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: C.border, width: 1.5)),
                        child: const Icon(Icons.swap_vert_rounded, color: C.primary),
                      ),
                    ),
                  ),
                ]),
                const Divider(height: 1, color: C.line),
                Row(children: [
                  Expanded(child: _field(Icons.calendar_today_rounded, 'التاريخ', _dateLabel, () async {
                    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
                    if (d != null) setState(() => _date = d);
                  })),
                  Container(width: 1.5, height: 40, color: C.line),
                  const SizedBox(width: 12),
                  Expanded(child: _field(Icons.person_outline_rounded, 'الركاب', _pax == 1 ? 'راكب واحد' : '$_pax ركاب', () async {
                    final r = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => PassengersScreen(initial: _pax)));
                    if (r != null) setState(() => _pax = r);
                  })),
                ]),
                const SizedBox(height: 8),
                Btn('دوّر على رحلة', icon: Icons.search_rounded, onTap: () => go(context, ResultsScreen(from: _from, to: _to, date: _dateLabel, pax: _pax))),
              ]),
            ),
          ),
        ),
      ),
      Transform.translate(
        offset: const Offset(0, -50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Enter(
              delay: 220,
              child: CardBox(
                color: C.dark,
                onTap: () => go(context, const WomenRidesScreen()),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.verified_user_rounded, color: Colors.white)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('رحلات نسائية وعائلية', style: TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 16)),
                      Text('سائقات لراكبات، وسفر عائلي مع مَحرَم', style: TextStyle(fontFamily: kFont, color: C.tint, fontSize: 12.5)),
                    ]),
                  ),
                  const Icon(Icons.chevron_left_rounded, color: Colors.white),
                ]),
              ),
            ),
            const SizedBox(height: 22),
            const Text('وجهات شائعة', style: T.h3),
            const SizedBox(height: 10),
            SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cities.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => Enter(
                  delay: 260 + i * 60,
                  child: Press(
                    onTap: () => setState(() => _to = cities[i].name),
                    child: Container(
                      width: 150,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      clipBehavior: Clip.antiAlias,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Container(color: C.tint, width: double.infinity, child: Illus(cities[i].image, fit: BoxFit.cover, fallback: Icons.location_city_rounded))),
                        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: Text(cities[i].name, style: T.label)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text('عمليات بحث سابقة', style: T.h3),
            const SizedBox(height: 10),
            for (final (a, b, s) in const [('جبلة', 'حمص', 'الخميس، راكبين'), ('طرطوس', 'حلب', 'السبت، راكب واحد')])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CardBox(
                  onTap: () => go(context, ResultsScreen(from: a, to: b, date: s, pax: 1)),
                  child: Row(children: [
                    const Icon(Icons.history_rounded, color: C.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$a ← $b', style: T.label), Text(s, style: T.small)])),
                    const Icon(Icons.chevron_left_rounded, color: C.muted),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    ]);
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
