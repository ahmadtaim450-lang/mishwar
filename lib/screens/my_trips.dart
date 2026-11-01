import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../data/store.dart';
import '../data/location.dart';
import '../widgets/common.dart';
import '../widgets/real_map.dart';
import 'messages.dart';
import 'profile.dart';
import 'shell.dart';
import 'publish.dart' show PublishFlow;
import 'pick_point.dart';
import 'driver_join.dart';

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen();
  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  late int _tab = Store.i.rides.isNotEmpty && Store.i.driverPending > 0 ? 1 : 0;
  final _s = Store.i;

  @override
  void initState() {
    super.initState();
    _s.refreshAll();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _s,
        builder: (context, _) => SafeArea(
          child: RefreshIndicator(
            color: C.primary,
            onRefresh: _s.refreshAll,
            child: ListView(padding: const EdgeInsets.all(20), physics: const AlwaysScrollableScrollPhysics(), children: [
            const Text('رحلاتي', style: T.h1),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: const Color(0xFFE4EAEA), borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                for (final (i, l) in [(0, 'كراكب'), (1, _s.driverPending > 0 ? 'كسائق · ${_s.driverPending}' : 'كسائق')])
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
            AnimatedSwitcher(duration: const Duration(milliseconds: 260), child: _tab == 0 ? _rider() : _driver()),
          ]),
          ),
        ),
      );

  Widget _rider() {
    final up = _s.upcoming, past = _s.past;
    if (up.isEmpty && past.isEmpty) {
      return const EmptyState(key: ValueKey('r0'), image: 'empty_search', title: 'ما عندك رحلات لسا', body: 'دوّر على رحلة من الرئيسية، وحجوزاتك بتطلع هون.');
    }
    return Column(key: const ValueKey('r'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (up.isNotEmpty) ...[const Text('الجاية', style: T.h3), const SizedBox(height: 8)],
      for (var i = 0; i < up.length; i++) Padding(padding: const EdgeInsets.only(bottom: 10), child: Enter(delay: i * 70, child: _BookingCard(up[i]))),
      if (past.isNotEmpty) ...[const SizedBox(height: 8), const Text('السابقة', style: T.h3), const SizedBox(height: 8)],
      for (final b in past)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CardBox(
            onTap: b.rated ? null : () => go(context, RateScreen(b)),
            child: Row(children: [
              Avatar(b.t.driver, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${b.t.from} ← ${b.t.to}', style: T.label),
                  Text('${dayLabel(b.t.day)} · مع ${b.t.driver.name}', style: T.small),
                ]),
              ),
              b.rated ? const Badge2('قيّمتها ★', bg: C.line, fg: C.muted2) : const Text('قيّم ←', style: TextStyle(fontFamily: kFont, color: C.primary)),
            ]),
          ),
        ),
    ]);
  }

  Widget _driver() {
    if (_s.driverStatus != DStatus.approved) {
      final none = _s.driverStatus == DStatus.none;
      return Column(key: const ValueKey('dj'), children: [
        EmptyState(image: 'onboard2', title: none ? 'بس السائقين الموثّقين بينشروا' : 'طلبك عم يتراجع', body: none ? 'قدّم طلب انضمام، ومنتعرّف عليك بمقابلة وفحص سيارة. بعدها بتنشر رحلاتك.' : 'رح يوصلك إشعار بكل خطوة.'),
        Btn(none ? 'صير سائق موثّق' : 'تابع حالة طلبك', icon: Icons.verified_outlined, onTap: () => go(context, none ? const DriverApplyFlow() : const DriverStatusScreen())),
      ]);
    }
    if (_s.rides.isEmpty) {
      return Column(key: const ValueKey('d0'), children: [
        const EmptyState(image: 'onboard2', title: 'ما نشرت رحلات لسا', body: 'طالع مشوار وعندك مقاعد فاضية؟ انشرها وقسّم المصروف مع ركاب موثّقين.'),
        Btn('انشر رحلة', icon: Icons.add_rounded, onTap: () => go(context, const PublishFlow())),
      ]);
    }
    return Column(key: const ValueKey('d'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Btn('انشر رحلة جديدة', kind: BtnKind.outline, icon: Icons.add_rounded, onTap: () => go(context, const PublishFlow())),
      const SizedBox(height: 14),
      for (final r in _s.rides) ...[
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${dayLabel(r.t.day)} · ${r.t.dep}', style: const TextStyle(fontFamily: kFont, color: C.tint)),
            Text('${r.t.from} ← ${r.t.to}', style: const TextStyle(fontFamily: kFont, fontSize: 20, color: Colors.white)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: r.booked / r.t.seatsTotal),
                duration: const Duration(milliseconds: 450),
                builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 8, color: Colors.white, backgroundColor: C.primaryLight),
              ),
            ),
            const SizedBox(height: 6),
            Text(r.booked == 0 ? 'لسا ما في حجوزات · ${seatsLabel(r.t.seatsTotal)} فاضيين' : '${r.booked} من ${r.t.seatsTotal} محجوزين · بتجمع ${money(r.booked * r.t.price)}', style: const TextStyle(fontFamily: kFont, color: Colors.white)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            if (r.status == 'scheduled') ...[
              Expanded(child: AsyncBtn('بلّشت الرحلة', kind: BtnKind.dark, icon: Icons.play_arrow_rounded, onTap: () async {
                await _s.startRide(r);
                if (mounted) go(context, DriverLiveScreen(r));
              })),
              const SizedBox(width: 8),
              Expanded(child: AsyncBtn('إلغاء الرحلة', kind: BtnKind.outline, onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('تلغي الرحلة؟', style: TextStyle(fontFamily: kFont)),
                    content: Text(r.booked > 0 ? 'رح نبلّغ ${r.booked} ركاب إنو الرحلة انلغت.' : 'ما في حجوزات لسا.', style: const TextStyle(fontFamily: kFont)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لا', style: TextStyle(fontFamily: kFont))),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('إلغاء الرحلة', style: TextStyle(fontFamily: kFont, color: C.danger))),
                    ],
                  ),
                );
                if (ok == true) await _s.cancelRide(r);
              })),
            ],
            if (r.status == 'in_progress') ...[
              Expanded(child: Btn('شاشة الرحلة', kind: BtnKind.dark, icon: Icons.navigation_rounded, onTap: () => go(context, DriverLiveScreen(r)))),
              const SizedBox(width: 8),
              Expanded(child: AsyncBtn('وصلنا', icon: Icons.flag_rounded, onTap: () => _s.finishRide(r))),
            ],
            if (r.status == 'completed') const Expanded(child: Badge2('الرحلة خلصت ✓')),
          ]),
        ),
        if (r.status == 'scheduled')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Btn('حدد نقطة التجمع على الخريطة', kind: BtnKind.white, icon: Icons.pin_drop_rounded, onTap: () => go(context, PickPointScreen(r.t))),
          ),
        const SizedBox(height: 12),
        if (r.reqs.isEmpty && r.status == 'scheduled')
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Row(children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.primary)),
              SizedBox(width: 10),
              Text('رحلتك منشورة، عم نستنى أول طلب...', style: T.small),
            ]),
          ),
        for (final q in r.reqs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Enter(
              child: CardBox(
                child: Column(children: [
                  Row(children: [
                    Avatar(q.p),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(q.p.name, style: T.label), Text('★ ${q.p.rating} · ${q.note}', style: T.small)])),
                    if (q.state == 1 && r.status == 'completed')
                      q.reviewed
                          ? const Badge2('قيّمتو ★', bg: C.line, fg: C.muted2)
                          : TextButton(onPressed: () => go(context, RateRiderScreen(q)), child: const Text('قيّم', style: TextStyle(fontFamily: kFont, color: C.primary)))
                    else if (q.state == 1) const Badge2('مقبول'),
                    if (q.state == 2) const Badge2('مرفوض', bg: C.dangerBg, fg: C.danger),
                  ]),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    child: q.state == 0
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(children: [
                              Expanded(
                                child: AsyncBtn('قبول', onTap: r.booked + q.seats > r.t.seatsTotal ? null : () => _s.answer(q, true)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: AsyncBtn('رفض', kind: BtnKind.outline, onTap: () => _s.answer(q, false))),
                            ]),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

class _BookingCard extends StatelessWidget {
  final Booking b;
  const _BookingCard(this.b);
  @override
  Widget build(BuildContext context) {
    final pending = b.status == BStatus.pending;
    return CardBox(
      onTap: () => go(context, TicketScreen(b)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${dayLabel(b.t.day)} · ${b.t.dep}', style: T.small)),
          pending ? const Badge2('بانتظار الموافقة', bg: C.warnBg, fg: C.warn) : const Badge2('مؤكّدة'),
        ]),
        const SizedBox(height: 6),
        Text('${b.t.from} ← ${b.t.to}', style: T.h3),
        Text('${b.t.fromSpot} · ${seatsLabel(b.seats)}${b.family ? ' · عائلي' : ''}', style: T.small),
        const Divider(height: 22, color: C.line),
        Row(children: [
          Avatar(b.t.driver, size: 36),
          const SizedBox(width: 10),
          Expanded(child: Text('${b.t.driver.name} · ${b.t.car.split(' · ').first}', style: T.label)),
          Text(money(b.total), style: const TextStyle(fontFamily: kFont, color: C.primary)),
        ]),
      ]),
    );
  }
}

class TicketScreen extends StatefulWidget {
  final Booking b;
  const TicketScreen(this.b);
  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  late Booking b = widget.b;

  @override
  void initState() {
    super.initState();
    // الرقم والرمز بيوصلوا من السيرفر بعد التأكيد
    Store.i.details(widget.b).then((d) {
      if (mounted) setState(() => b = d);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) {
          for (final x in Store.i.bookings) {
            if (x.id == b.id) b = x;
          }
          final t = b.t;
          final pending = b.status == BStatus.pending;
          final canStart = b.status == BStatus.confirmed && t.day <= 0;
          return Scaffold(
            appBar: TopBar(title: 'رحلتك ${dayLabel(t.day)}'),
            body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
              Enter(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: pending ? C.dark : C.primary, borderRadius: BorderRadius.circular(26)),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: Text('${dayLabel(t.day)} · ${t.duration}', style: const TextStyle(fontFamily: kFont, color: Colors.white))),
                      Badge2(pending ? 'بانتظار ${t.driver.name}' : 'مؤكّدة', bg: pending ? C.yellow : C.dark, fg: pending ? C.dark : Colors.white),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [FittedBox(fit: BoxFit.scaleDown, child: Text(t.dep, style: const TextStyle(fontFamily: kFont, fontSize: 28, color: Colors.white))), Text(t.from, style: const TextStyle(fontFamily: kFont, color: Colors.white)), Text(t.fromSpot, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kFont, fontSize: 12, color: C.tint))])),
                      const Spacer(),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.directions_car_filled_rounded, color: Colors.white, size: 30)),
                      const Spacer(),
                      Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [FittedBox(fit: BoxFit.scaleDown, child: Text(t.arr, style: const TextStyle(fontFamily: kFont, fontSize: 28, color: Colors.white))), Text(t.to, style: const TextStyle(fontFamily: kFont, color: Colors.white)), Text(t.toSpot, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kFont, fontSize: 12, color: C.tint))])),
                    ]),
                    const Divider(height: 26, color: Colors.white24),
                    Row(children: [
                      Expanded(child: Text('${seatsLabel(b.seats)}${b.family ? ' · عائلي' : ''}', style: const TextStyle(fontFamily: kFont, color: Colors.white))),
                      Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text('${money(b.total)} كاش', style: const TextStyle(fontFamily: kFont, fontSize: 17, color: C.yellow)))),
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
                    SquareBtn(Icons.chat_bubble_outline_rounded, tooltip: 'مراسلة', onTap: () => go(context, ChatScreen(t.driver, b.id))),
                    const SizedBox(width: 8),
                    SquareBtn(Icons.call_rounded, solid: true, tooltip: 'اتصال', onTap: () async {
                      final phone = b.driverPhone;
                      if (pending || phone == null || phone.contains('•')) {
                        toast(context, pending ? 'الرقم بيظهر بعد ما ${t.driver.name} يقبل' : 'بالنسخة التجريبية ما في اتصال حقيقي');
                        return;
                      }
                      if (!await launchUrl(Uri(scheme: 'tel', path: phone)) && context.mounted) toast(context, phone);
                    }),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Enter(
                delay: 140,
                child: Row(children: [
                  Expanded(
                    child: CardBox(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('رقم السيارة', style: T.small),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.dark, width: 2)),
                          child: Text(pending ? '••••••' : (b.plate ?? t.plate), style: const TextStyle(fontFamily: kFont, fontSize: 16, color: C.dark)),
                        ),
                        const SizedBox(height: 4),
                        Text(t.car.split(' · ').last, style: T.small),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CardBox(
                      color: C.yellow,
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('رمز الرحلة', style: TextStyle(fontFamily: kFont)),
                          content: const Text('قبل ما تطلع بالسيارة، اسأل السائق عن رمز رحلتك. إذا ما عرفو، لا تطلع وبلّغنا فوراً.', style: TextStyle(fontFamily: kFont, height: 1.7)),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('فهمت', style: TextStyle(fontFamily: kFont)))],
                        ),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('رمز الرحلة ⓘ', style: TextStyle(fontFamily: kFont, fontSize: 12.5, color: C.warn)),
                        Text(pending || b.pin == null ? '••••' : b.pin!, style: const TextStyle(fontFamily: kFont, fontSize: 30, letterSpacing: 6, color: C.dark)),
                        const Text('السائق لازم يعرفو', style: TextStyle(fontFamily: kFont, fontSize: 12, color: C.dark)),
                      ]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Enter(
                delay: 180,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(22)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('قبل ما تطلع', style: TextStyle(fontFamily: kFont, color: C.yellow, fontSize: 14)),
                    const SizedBox(height: 8),
                    for (final (i, s) in [(Icons.schedule_rounded, 'كون بنقطة الانطلاق قبل 10 دقايق'), (Icons.place_outlined, 'المكان: ${t.fromSpot}، ${t.from}'), (Icons.payments_outlined, 'جهّز ${money(b.total)} كاش'), (Icons.pin_outlined, 'تأكد من رقم السيارة ورمز الرحلة قبل ما تطلع'), (Icons.share_location_rounded, 'شارك موقعك مع أهلك وقت تطلع')])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [Icon(i, color: Colors.white70, size: 18), const SizedBox(width: 10), Expanded(child: Text(s, style: const TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 15)))]),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Group([
                RowItem(Icons.share_location_rounded, 'شارك موقعك مع أهلك', onTap: () => go(context, ShareTripScreen(b))),
                RowItem(Icons.close_rounded, 'إلغاء الحجز', danger: true, onTap: () => go(context, CancelBookingScreen(b))),
              ]),
            ]),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Btn(
                  pending ? 'عم نستنى موافقة السائق' : (canStart ? 'بلّشت الرحلة؟ تابعها' : 'شوف كيف بتنتابع الرحلة'),
                  icon: Icons.route_rounded,
                  onTap: pending ? null : () => go(context, LiveTripScreen(b)),
                ),
              ),
            ),
          );
        },
      );
}

/// متابعة الرحلة: موقع GPS الحقيقي على الطريق، ووقت وصول محسوب منه.
class LiveTripScreen extends StatefulWidget {
  final Booking b;
  const LiveTripScreen(this.b);
  @override
  State<LiveTripScreen> createState() => _LiveTripScreenState();
}

class _LiveTripScreenState extends State<LiveTripScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 90))..repeat();
  StreamSubscription<Position>? _sub;
  LatLng? _me;
  bool _gps = false;

  Trip get t => widget.b.t;

  @override
  void initState() {
    super.initState();
    _startGps();
  }

  Future<void> _startGps() async {
    final p = await myPosition();
    if (!mounted || p == null) return;
    _update(p);
    _sub = Geolocator.getPositionStream(locationSettings: trackingSettings(25)).listen((p) {
      if (mounted) _update(p);
    });
  }

  /// منعتمد الموقع الحقيقي بس إذا الجهاز فعلاً عالطريق، غير هيك منعرض معاينة.
  void _update(Position p) {
    final me = LatLng(p.latitude, p.longitude);
    final dest = geo[t.to]!;
    final km = const Distance().as(LengthUnit.Kilometer, me, LatLng(dest.$1, dest.$2));
    final onRoute = km <= roadKm(t.from, t.to) * 1.1;
    setState(() {
      _me = me;
      _gps = onRoute;
    });
    if (onRoute && Store.i.live) {
      Store.i.updateLocation(t, p.latitude, p.longitude, accuracy: p.accuracy, heading: p.heading);
    }
    if (onRoute) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _c.dispose();
    super.dispose();
  }

  (int km, String eta) _remaining(double progress) {
    final dest = geo[t.to]!;
    int km;
    if (_gps && _me != null) {
      km = (const Distance().as(LengthUnit.Kilometer, _me!, LatLng(dest.$1, dest.$2)) * 1.3).round();
    } else {
      km = (roadKm(t.from, t.to) * (1 - progress)).round();
    }
    final at = DateTime.now().add(Duration(minutes: (km / 75 * 60).round()));
    return (km, '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final cities = [t.from, ...t.stops, t.to];
    return Scaffold(
      backgroundColor: C.bg,
      body: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final prog = .1 + _c.value * .85;
          final (km, eta) = _remaining(prog);
          return Stack(children: [
            Positioned.fill(bottom: 220, child: TripMap(cities: cities, carProgress: _gps ? null : prog, me: _gps ? _me : null)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  SquareBtn(Icons.arrow_forward_rounded, tooltip: 'رجوع', onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: _gps ? const Color(0xFF1E9E5A) : C.warnBg, borderRadius: BorderRadius.circular(12)),
                      child: Text(_gps ? '● موقعك الحقيقي' : (_me == null ? 'معاينة · شغّل الموقع' : 'معاينة · انت مو عالطريق'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: kFont, fontSize: 12, color: _gps ? Colors.white : C.warn)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Press(
                    onTap: () => go(context, const SosScreen()),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
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
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('الوصول المتوقع', style: T.small), FittedBox(fit: BoxFit.scaleDown, child: Text(eta, style: const TextStyle(fontFamily: kFont, fontSize: 32, color: C.dark)))])),
                    Flexible(child: Text('باقي $km كم لـ${t.to}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kFont, color: C.primary, fontSize: 16))),
                  ]),
                  const SizedBox(height: 8),
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: (1 - km / roadKm(t.from, t.to)).clamp(0.02, 1.0), minHeight: 8, backgroundColor: C.line, color: C.primary)),
                  const SizedBox(height: 14),
                  Row(children: [
                    Avatar(t.driver),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${t.driver.name} · ${t.car.split(' · ').first}', style: T.label)),
                    SquareBtn(Icons.share_location_rounded, tooltip: 'مشاركة', onTap: () => go(context, ShareTripScreen(widget.b))),
                    const SizedBox(width: 8),
                    SquareBtn(Icons.flag_rounded, solid: true, tooltip: 'وصلت', onTap: () {
                      Store.i.finish(widget.b);
                      goReplace(context, TripDoneScreen(widget.b));
                    }),
                  ]),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// شاشة السائق أثناء الرحلة: موقعو الحقيقي بينبعت كل شوي، فالركاب وأهلن بيتابعوا.
class DriverLiveScreen extends StatefulWidget {
  final MyRide r;
  const DriverLiveScreen(this.r);
  @override
  State<DriverLiveScreen> createState() => _DriverLiveScreenState();
}

class _DriverLiveScreenState extends State<DriverLiveScreen> {
  StreamSubscription<Position>? _sub;
  LatLng? _me;
  DateTime? _sent;
  bool _noGps = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final p = await myPosition();
    if (!mounted) return;
    if (p == null) {
      setState(() => _noGps = true);
      return;
    }
    _push(p);
    _sub = Geolocator.getPositionStream(locationSettings: trackingSettings(50)).listen((p) {
      if (mounted) _push(p);
    });
  }

  void _push(Position p) {
    setState(() => _me = LatLng(p.latitude, p.longitude));
    // كل 20 ثانية عالأكتر، لحتى ما نستهلك البطارية والباقة
    if (_sent == null || DateTime.now().difference(_sent!).inSeconds >= 20) {
      _sent = DateTime.now();
      Store.i.updateLocation(widget.r.t, p.latitude, p.longitude, accuracy: p.accuracy, heading: p.heading);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.r.t;
    final riders = widget.r.reqs.where((q) => q.state == 1).toList();
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(bottom: 230, child: TripMap(cities: [t.from, ...t.stops, t.to], me: _me)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              SquareBtn(Icons.arrow_forward_rounded, tooltip: 'رجوع', onTap: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: _noGps ? C.warnBg : const Color(0xFF1E9E5A), borderRadius: BorderRadius.circular(12)),
                child: Text(_noGps ? 'شغّل الموقع لحتى يتابعك الركاب' : (_me == null ? 'عم نحدد موقعك...' : '● موقعك عم ينشارك'), style: TextStyle(fontFamily: kFont, fontSize: 12, color: _noGps ? C.warn : Colors.white)),
              ),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t.from} ← ${t.to}', style: T.h3),
                Text(riders.isEmpty ? 'ما في ركاب مؤكّدين' : 'معك: ${riders.map((q) => q.p.name).join('، ')}', style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                const InfoNote('قبل ما تنطلق، تأكد من رمز الرحلة مع كل راكب.', icon: Icons.pin_outlined),
                const SizedBox(height: 10),
                AsyncBtn('وصلنا، خلصت الرحلة', icon: Icons.flag_rounded, onTap: () async {
                  await Store.i.finishRide(widget.r);
                  if (context.mounted) Navigator.pop(context);
                }),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// مشاركة موقع GPS الحالي (لقطة دقيقة). المشاركة الحية بتحتاج سيرفر.
class ShareTripScreen extends StatefulWidget {
  final Booking b;
  const ShareTripScreen(this.b);
  @override
  State<ShareTripScreen> createState() => _ShareTripScreenState();
}

class _ShareTripScreenState extends State<ShareTripScreen> {
  Position? _p;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    myPosition().then((p) {
      if (mounted) setState(() {
        _p = p;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.b.t;
    return Scaffold(
      appBar: const TopBar(title: 'شارك موقعك'),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(
          height: 240,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: TripMap(cities: [t.from, ...t.stops, t.to], interactive: false, me: _p == null ? null : LatLng(_p!.latitude, _p!.longitude)),
        ),
        const SizedBox(height: 14),
        CardBox(
          child: Row(children: [
            Icon(_p != null ? Icons.gps_fixed_rounded : Icons.gps_off_rounded, color: _p != null ? const Color(0xFF1E9E5A) : C.warn),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _loading ? 'عم نحدد موقعك...' : _p != null ? 'موقعك محدد بدقة ${_p!.accuracy.round()} متر' : 'الموقع مسكّر. شغّله لنبعت موقعك الحقيقي',
                style: T.label,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        InfoNote(Store.i.live ? 'أهلك بيفتحوا الرابط بالمتصفح وبيشوفوا موقعك مباشرة لحتى توصل. الرابط بينتهي لحالو بعد الرحلة.' : 'بالنسخة التجريبية بنبعت لقطة لموقعك هلق. المتابعة المباشرة بتشتغل بعد ربط السيرفر.', icon: Icons.info_outline_rounded),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: AsyncBtn('شارك هلق', icon: Icons.ios_share_rounded, onTap: _loading
              ? null
              : () async {
                  var link = '';
                  if (widget.b.status == BStatus.confirmed) link = await Store.i.shareLink(widget.b);
                  final loc = link.isNotEmpty ? '\nتابعني مباشرة: $link' : (_p == null ? '' : '\nموقعي هلق: ${mapsLink(_p!.latitude, _p!.longitude)}');
                  final plate = (widget.b.plate ?? '').isEmpty ? '' : ' · ${widget.b.plate}';
                  await Share.share('أنا مسافر مع مشوار\n${t.from} ← ${t.to} · ${dayLabel(t.day)} ${t.dep}\nالسائق: ${t.driver.name} · ${t.car}$plate\nالوصول المتوقع: ${t.arr}$loc', subject: 'رحلتي مع مشوار');
                }),
        ),
      ),
    );
  }
}

class TripDoneScreen extends StatelessWidget {
  final Booking b;
  const TripDoneScreen(this.b);
  @override
  Widget build(BuildContext context) {
    final t = b.t;
    return Scaffold(
      backgroundColor: C.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            Floaty(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 6),
                  boxShadow: [BoxShadow(color: C.dark.withValues(alpha: .25), blurRadius: 30, offset: const Offset(0, 14))],
                ),
                child: ClipOval(child: Illus(t.to == 'دمشق' ? 'arrived_damascus' : (cities.firstWhere((c) => c.name == t.to, orElse: () => cities.first).image.isEmpty ? 'welcome' : cities.firstWhere((c) => c.name == t.to).image), fit: BoxFit.cover)),
              ),
            ),
            const SizedBox(height: 16),
            Enter(child: Text('وصلت ${t.to} بالسلامة', style: const TextStyle(fontFamily: kFont, fontSize: 30, color: Colors.white))),
            Enter(delay: 80, child: Text('نوّرت ${t.to}', style: const TextStyle(fontFamily: kFont, fontSize: 16, color: C.tint))),
            const SizedBox(height: 14),
            Row(children: [
              for (final (a, c) in [('${roadKm(t.from, t.to)}', 'كم'), (t.duration, 'المدة'), ('${t.stops.length + 2}', 'مدن')])
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(18)),
                    child: Column(children: [Text(a, style: const TextStyle(fontFamily: kFont, fontSize: 20, color: Colors.white)), Text(c, style: const TextStyle(fontFamily: kFont, color: Colors.white))]),
                  ),
                ),
            ]),
            const Spacer(),
            Btn('قيّم ${t.driver.name}', kind: BtnKind.white, icon: Icons.star_rounded, onTap: () => goReplace(context, RateScreen(b))),
            const SizedBox(height: 10),
            Btn('رجوع للرئيسية', kind: BtnKind.dark, onTap: () => goReplace(context, const AppShell())),
          ]),
        ),
      ),
    );
  }
}

class RateScreen extends StatefulWidget {
  final Booking b;
  const RateScreen(this.b);
  @override
  State<RateScreen> createState() => _RateScreenState();
}

class _RateScreenState extends State<RateScreen> {
  int _r = 5;
  final _tags = <int>{0};
  final _comment = TextEditingController();
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  static const _words = ['', 'سيئة', 'مقبولة', 'منيحة', 'كتير حلوة', 'ممتازة!'];
  @override
  Widget build(BuildContext context) {
    final d = widget.b.t.driver;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const TopBar(close: true),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Center(child: Avatar(d, size: 96)),
        const SizedBox(height: 12),
        Text('كيف كانت رحلتك مع ${d.name}؟', style: T.h2, textAlign: TextAlign.center),
        Text('${widget.b.t.from} ← ${widget.b.t.to}', style: T.small, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
        ])),
        Center(child: Text(_words[_r], style: const TextStyle(fontFamily: kFont, color: C.primary, fontSize: 18))),
        const SizedBox(height: 16),
        ChipGroup(
          options: _r >= 4 ? const ['عالوقت', 'سواقة آمنة', 'سيارة نضيفة', 'محترم', 'وقف للاستراحة'] : const ['تأخر', 'سواقة سريعة', 'السيارة مو نضيفة', 'غيّر المسار'],
          selected: _tags,
          onTap: (i) => setState(() => _tags.contains(i) ? _tags.remove(i) : _tags.add(i)),
        ),
        const SizedBox(height: 16),
        TextField(controller: _comment, maxLines: 3, maxLength: 500, style: const TextStyle(fontFamily: kFont), decoration: const InputDecoration(hintText: 'بدك تضيف شي؟ (اختياري)')),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: AsyncBtn('إرسال التقييم', onTap: () async {
            final opts = _r >= 4 ? const ['عالوقت', 'سواقة آمنة', 'سيارة نضيفة', 'محترم', 'وقف للاستراحة'] : const ['تأخر', 'سواقة سريعة', 'السيارة مو نضيفة', 'غيّر المسار'];
            await Store.i.rate(widget.b, _r, [for (final i in _tags) if (i < opts.length) opts[i]], _comment.text);
            Store.i.say('شكراً عالتقييم');
            if (context.mounted) Navigator.pop(context);
          }),
        ),
      ),
    );
  }
}

/// السائق بيقيّم الراكب بعد الرحلة.
class RateRiderScreen extends StatefulWidget {
  final RideReq q;
  const RateRiderScreen(this.q);
  @override
  State<RateRiderScreen> createState() => _RateRiderScreenState();
}

class _RateRiderScreenState extends State<RateRiderScreen> {
  int _r = 5;
  final _tags = <int>{0};
  static const _good = ['عالموعد', 'محترم', 'دفع كامل', 'شناتي حسب الاتفاق'];
  static const _bad = ['تأخر', 'غيّر المكان', 'ما دفع كامل', 'تصرف مزعج'];
  @override
  Widget build(BuildContext context) {
    final opts = _r >= 4 ? _good : _bad;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const TopBar(close: true),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Center(child: Avatar(widget.q.p, size: 96)),
        const SizedBox(height: 12),
        Text('كيف كان ${widget.q.p.name} كراكب؟', style: T.h2, textAlign: TextAlign.center),
        const Text('تقييمك بيساعد السائقين التانيين يقرروا', style: T.small, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              tooltip: '$i نجوم',
              onPressed: () => setState(() {
                _r = i;
                _tags.clear();
              }),
              icon: Icon(i <= _r ? Icons.star_rounded : Icons.star_outline_rounded, size: 44, color: i <= _r ? C.star : const Color(0xFFC7D1D1)),
            ),
        ])),
        const SizedBox(height: 16),
        ChipGroup(options: opts, selected: _tags, onTap: (i) => setState(() => _tags.contains(i) ? _tags.remove(i) : _tags.add(i))),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: AsyncBtn('إرسال التقييم', onTap: () async {
            await Store.i.rateRider(widget.q, _r, [for (final i in _tags) if (i < opts.length) opts[i]], null);
            if (context.mounted) Navigator.pop(context);
          }),
        ),
      ),
    );
  }
}

class CancelBookingScreen extends StatefulWidget {
  final Booking b;
  const CancelBookingScreen(this.b);
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
          Text('${widget.b.t.from} ← ${widget.b.t.to} · ${dayLabel(widget.b.t.day)} ${widget.b.t.dep}', style: T.body),
          const SizedBox(height: 14),
          ChoiceCards(options: const [('تغيّرت خطتي', ''), ('لقيت طريقة تانية', ''), ('السائق طلب إلغي', ''), ('سبب تاني', '')], selected: {_w}, onTap: (i) => setState(() => _w = i)),
          const InfoNote('الإلغاء قبل 12 ساعة من الرحلة ما بيأثر على تقييمك.', icon: Icons.schedule_rounded),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AsyncBtn('إلغاء الحجز', kind: BtnKind.danger, onTap: () async {
                const reasons = ['تغيّرت خطتي', 'لقيت طريقة تانية', 'السائق طلب إلغي', 'سبب تاني'];
                await Store.i.cancel(widget.b, reason: reasons[_w]);
                if (context.mounted) goReplace(context, const _CancelDone());
              }),
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
            body: 'بلّغنا السائق، والمقعد رجع متاح لغيرك.',
            actions: [Btn('رجوع للرئيسية', onTap: () => goReplace(context, const AppShell()))],
          ),
        ),
      );
}
