import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../widgets/common.dart';
import '../widgets/real_map.dart';
import 'package:share_plus/share_plus.dart';
import 'messages.dart';
import 'profile.dart';
import 'shell.dart';

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen();
  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  int _tab = 0;
  final _req = <String, int>{'مازن': 0, 'حسام': 0}; // 0 بانتظار، 1 مقبول، 2 مرفوض

  @override
  Widget build(BuildContext context) {
    final booked = 1 + _req.values.where((v) => v == 1).length;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('رحلاتي', style: T.h1),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: const Color(0xFFE4EAEA), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            for (final (i, l) in const [(0, 'كراكب'), (1, 'كسائق')])
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 44,
                    decoration: BoxDecoration(color: _tab == i ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: Text(l, style: TextStyle(fontFamily: kFont, fontSize: 15, color: _tab == i ? C.dark : C.muted2)),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: _tab == 0
              ? Column(key: const ValueKey(0), children: [
                  Enter(
                    child: CardBox(
                      onTap: () => go(context, TicketScreen(trips[0])),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [const Expanded(child: Text('بكرا · 07:00', style: T.small)), const Badge2('مؤكّدة')]),
                        const SizedBox(height: 6),
                        const Text('اللاذقية ← دمشق', style: T.h3),
                        const Divider(height: 22, color: C.line),
                        Row(children: [Avatar(samer, size: 36), const SizedBox(width: 10), const Expanded(child: Text('سامر · كيا ريو', style: T.label)), const Icon(Icons.chevron_left_rounded, color: C.muted)]),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Enter(
                    delay: 100,
                    child: CardBox(
                      onTap: () => go(context, const RateScreen()),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [const Expanded(child: Text('الأحد الماضي', style: T.small)), const Badge2('انتهت', bg: C.line, fg: C.muted2)]),
                        const SizedBox(height: 6),
                        const Text('جبلة ← حمص', style: T.h3),
                        const Text('قيّم الرحلة ←', style: TextStyle(fontFamily: kFont, color: C.primary)),
                      ]),
                    ),
                  ),
                ])
              : Column(key: const ValueKey(1), crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(22)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('الرحلة الجاية · بكرا 07:00', style: TextStyle(fontFamily: kFont, color: C.tint)),
                      const Text('اللاذقية ← دمشق', style: TextStyle(fontFamily: kFont, fontSize: 20, color: Colors.white)),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: booked / 3),
                          duration: const Duration(milliseconds: 450),
                          builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 8, color: Colors.white, backgroundColor: C.primaryLight),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('$booked من 3 مقاعد محجوزة', style: const TextStyle(fontFamily: kFont, color: Colors.white)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  const Text('طلبات الحجز', style: T.h3),
                  const SizedBox(height: 8),
                  for (final name in _req.keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CardBox(
                        child: Column(children: [
                          Row(children: [
                            Avatar(name == 'مازن' ? mazen : hussam),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: T.label), Text(name == 'مازن' ? '★ 4.8 · راكب واحد · طالب' : '★ 4.6 · شنتاية صغيرة', style: T.small)])),
                            if (_req[name] == 1) const Badge2('مقبول'),
                            if (_req[name] == 2) const Badge2('مرفوض', bg: C.dangerBg, fg: C.danger),
                          ]),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            child: _req[name] == 0
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Row(children: [
                                      Expanded(child: Btn('قبول', onTap: () => setState(() => _req[name] = 1))),
                                      const SizedBox(width: 10),
                                      Expanded(child: Btn('رفض', kind: BtnKind.outline, onTap: () => setState(() => _req[name] = 2))),
                                    ]),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                        ]),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

class TicketScreen extends StatelessWidget {
  final Trip t;
  const TicketScreen(this.t);
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(title: 'رحلتك بكرا'),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
          Enter(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(26)),
              child: Column(children: [
                const Row(children: [Expanded(child: Text('بكرا', style: TextStyle(fontFamily: kFont, color: Colors.white))), Badge2('مؤكّدة', bg: C.dark, fg: Colors.white)]),
                const SizedBox(height: 14),
                Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t.dep, style: const TextStyle(fontFamily: kFont, fontSize: 28, color: Colors.white)), Text(t.from, style: const TextStyle(fontFamily: kFont, color: Colors.white))]),
                  const Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.directions_car_filled_rounded, color: Colors.white, size: 30))),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(t.arr, style: const TextStyle(fontFamily: kFont, fontSize: 28, color: Colors.white)), Text(t.to, style: const TextStyle(fontFamily: kFont, color: Colors.white))]),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Enter(
            delay: 100,
            child: CardBox(
              child: Row(children: [
                Avatar(t.driver, size: 48),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t.driver.name, style: T.label), Text(t.car, style: T.small)])),
                SquareBtn(Icons.chat_bubble_outline_rounded, tooltip: 'مراسلة', onTap: () => go(context, ChatScreen(t.driver))),
                const SizedBox(width: 8),
                SquareBtn(Icons.call_rounded, solid: true, tooltip: 'اتصال', onTap: () => toast(context, 'جاري الاتصال...')),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Enter(
            delay: 180,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(22)),
              child: const Column(children: [
                Text('دعاء السفر', style: TextStyle(fontFamily: kFont, color: C.yellow, fontSize: 14)),
                SizedBox(height: 8),
                Text('سُبحانَ الَّذي سَخَّرَ لَنا هذا وما كُنّا لَهُ مُقرِنين، وإنّا إلى رَبِّنا لَمُنقَلِبون', textAlign: TextAlign.center, style: TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 17, height: 2)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Group([
            RowItem(Icons.share_location_rounded, 'شارك الرحلة مع أهلك', onTap: () => go(context, const ShareTripScreen())),
            RowItem(Icons.close_rounded, 'إلغاء الحجز', danger: true, onTap: () => go(context, const CancelBookingScreen())),
          ]),
        ]),
        bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Btn('بلّشت الرحلة؟ تابعها', icon: Icons.route_rounded, onTap: () => go(context, const LiveTripScreen())))),
      );
}

class LiveTripScreen extends StatefulWidget {
  const LiveTripScreen();
  @override
  State<LiveTripScreen> createState() => _LiveTripScreenState();
}

class _LiveTripScreenState extends State<LiveTripScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: Stack(children: [
          Positioned.fill(
            bottom: 200,
            child: AnimatedBuilder(animation: _c, builder: (_, __) => TripMap(cities: const ['اللاذقية', 'طرطوس', 'حمص', 'دمشق'], carProgress: .15 + _c.value * .8)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                SquareBtn(Icons.arrow_forward_rounded, tooltip: 'رجوع', onTap: () => Navigator.pop(context)),
                const Spacer(),
                Press(
                  onTap: () => go(context, const SosScreen()),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(color: const Color(0xFFD93A22), borderRadius: BorderRadius.circular(16)),
                    child: const Row(children: [Icon(Icons.sos_rounded, color: Colors.white), SizedBox(width: 6), Text('طوارئ', style: TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 16))]),
                  ),
                ),
              ]),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(5)))),
                const SizedBox(height: 12),
                const Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('الوصول المتوقع', style: T.small), Text('11:20', style: TextStyle(fontFamily: kFont, fontSize: 32, color: C.dark))])),
                  Text('باقي 142 كم', style: TextStyle(fontFamily: kFont, color: C.primary, fontSize: 16)),
                ]),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: .3 + _c.value * .6, minHeight: 8, backgroundColor: C.line, color: C.primary)),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Avatar(samer),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('سامر · كيا ريو', style: T.label)),
                  SquareBtn(Icons.share_location_rounded, tooltip: 'مشاركة', onTap: () => go(context, const ShareTripScreen())),
                  const SizedBox(width: 8),
                  SquareBtn(Icons.flag_rounded, solid: true, tooltip: 'وصلت', onTap: () => go(context, const TripDoneScreen())),
                ]),
              ]),
            ),
          ),
        ]),
      );
}

class ShareTripScreen extends StatefulWidget {
  const ShareTripScreen();
  @override
  State<ShareTripScreen> createState() => _ShareTripScreenState();
}

class _ShareTripScreenState extends State<ShareTripScreen> {
  final _sel = {0};
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(title: 'شارك رحلتك'),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Container(
            height: 220,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: const TripMap(cities: ['اللاذقية', 'طرطوس', 'حمص', 'دمشق'], carProgress: .55, interactive: false),
          ),
          const SizedBox(height: 12),
          const Text('أهلك بيقدروا يتابعوا موقعك ووقت وصولك برابط، بدون ما ينزلوا التطبيق.', style: T.body),
          const SizedBox(height: 14),
          ChoiceCards(multi: true, options: const [('أمي', '+963 9•• ••• •12'), ('أخي أحمد', '+963 9•• ••• •48'), ('أبي', '+963 9•• ••• •07')], selected: _sel, onTap: (i) => setState(() => _sel.contains(i) ? _sel.remove(i) : _sel.add(i))),
        ]),
        bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Btn('شارك هلق', icon: Icons.ios_share_rounded, onTap: () {
          Share.share('أنا بالطريق مع مشوار 🚗\nاللاذقية ← دمشق مع سامر (كيا ريو فضي)\nالوصول المتوقع 11:20\nموقعي الحالي: https://www.openstreetmap.org/?mlat=34.73&mlon=36.71#map=9/34.73/36.71', subject: 'رحلتي مع مشوار');
        }))),
      );
}

class TripDoneScreen extends StatelessWidget {
  const TripDoneScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.primary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(),
              Floaty(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 6),
                    boxShadow: [BoxShadow(color: C.dark.withValues(alpha: .25), blurRadius: 30, offset: const Offset(0, 14))],
                  ),
                  child: const ClipOval(child: Illus('arrived_damascus', fit: BoxFit.cover)),
                ),
              ),
              const SizedBox(height: 12),
              const Enter(child: Text('وصلت بالسلامة، الحمد لله', style: TextStyle(fontFamily: kFont, fontSize: 32, color: Colors.white))),
              const SizedBox(height: 14),
              Row(children: [
                for (final (a, b) in const [('350', 'كم'), ('4:20', 'ساعة'), ('3', 'مدن')])
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(18)),
                      child: Column(children: [Text(a, style: const TextStyle(fontFamily: kFont, fontSize: 22, color: Colors.white)), Text(b, style: const TextStyle(fontFamily: kFont, color: Colors.white))]),
                    ),
                  ),
              ]),
              const Spacer(),
              Btn('قيّم سامر', kind: BtnKind.white, icon: Icons.star_rounded, onTap: () => go(context, const RateScreen())),
              const SizedBox(height: 10),
              Btn('رجوع للرئيسية', kind: BtnKind.dark, onTap: () => goReplace(context, const AppShell())),
            ]),
          ),
        ),
      );
}

class RateScreen extends StatefulWidget {
  const RateScreen();
  @override
  State<RateScreen> createState() => _RateScreenState();
}

class _RateScreenState extends State<RateScreen> {
  int _r = 4;
  final _tags = <int>{0};
  static const _words = ['', 'سيئة', 'مقبولة', 'منيحة', 'كتير حلوة', 'ممتازة!'];
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: const TopBar(close: true),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Center(child: Avatar(samer, size: 96)),
          const SizedBox(height: 12),
          const Text('كيف كانت رحلتك مع سامر؟', style: T.h2, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: () => setState(() => _r = i),
                icon: AnimatedScale(
                  scale: i <= _r ? 1.15 : 1,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.elasticOut,
                  child: Icon(i <= _r ? Icons.star_rounded : Icons.star_outline_rounded, size: 44, color: i <= _r ? C.star : const Color(0xFFC7D1D1)),
                ),
              ),
          ]),
          Center(child: Text(_words[_r], style: const TextStyle(fontFamily: kFont, color: C.primary, fontSize: 18))),
          const SizedBox(height: 16),
          ChipGroup(options: const ['عالوقت', 'سواقة آمنة', 'سيارة نضيفة', 'محترم', 'وقف للصلاة'], selected: _tags, onTap: (i) => setState(() => _tags.contains(i) ? _tags.remove(i) : _tags.add(i))),
          const SizedBox(height: 16),
          const TextField(maxLines: 3, style: TextStyle(fontFamily: kFont), decoration: InputDecoration(hintText: 'بدك تضيف شي؟ (اختياري)')),
        ]),
        bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Btn('إرسال التقييم', onTap: () {
          toast(context, 'شكراً عالتقييم');
          Navigator.pop(context);
        }))),
      );
}

class CancelBookingScreen extends StatefulWidget {
  const CancelBookingScreen();
  @override
  State<CancelBookingScreen> createState() => _CancelBookingScreenState();
}

class _CancelBookingScreenState extends State<CancelBookingScreen> {
  int _w = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('أكيد بدك تلغي حجزك؟', style: T.h1),
          const SizedBox(height: 14),
          ChoiceCards(options: const [('تغيّرت خطتي', ''), ('لقيت طريقة تانية', ''), ('السائق طلب إلغي', ''), ('سبب تاني', '')], selected: {_w}, onTap: (i) => setState(() => _w = i)),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Btn('إلغاء الحجز', kind: BtnKind.danger, onTap: () => goReplace(context, const _CancelDone())),
              Btn('خلّي الحجز', kind: BtnKind.ghost, onTap: () => Navigator.pop(context)),
            ]),
          ),
        ),
      );
}

class _CancelDone extends StatelessWidget {
  const _CancelDone();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: EmptyState(
            image: 'cancelled',
            title: 'انلغى حجزك',
            body: 'بلّغنا السائق، والمقعد رجع متاح لغيرك. ما في أي رسوم.',
            actions: [Btn('رجوع للرئيسية', onTap: () => goReplace(context, const AppShell()))],
          ),
        ),
      );
}
