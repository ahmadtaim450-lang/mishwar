// لقطات شاشة للمراجعة البصرية (مو اختبار مقارنة): بتشتغل بس بالـ CI مع
//   flutter test test/screenshots_test.dart --update-goldens --dart-define=SCREENSHOTS=true
// وبتنرفع كـ artifact. صور الخريطة نفسها ما بتنحمّل بالاختبارات (بلا نت)، فالخلفية رمادية.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishwar/core/theme.dart';
import 'package:mishwar/data/demo_backend.dart';
import 'package:mishwar/data/store.dart';
import 'package:mishwar/data/wallet.dart';
import 'package:mishwar/map/tiles.dart';
import 'package:mishwar/screens/map_explore.dart';
import 'package:mishwar/screens/map_search.dart';
import 'package:mishwar/screens/pick_point.dart';
import 'package:mishwar/screens/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const enabled = bool.fromEnvironment('SCREENSHOTS');

Widget wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      scaffoldMessengerKey: Store.i.messenger,
      home: child,
    );

Future<void> loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final f in manifest.cast<Map>()) {
    final loader = FontLoader(f['family'] as String);
    for (final a in (f['fonts'] as List).cast<Map>()) {
      loader.addFont(rootBundle.load(a['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(() async {
    if (!enabled) return;
    TileCache.disabled = true;
    SharedPreferences.setMockInitialValues({});
    await loadFonts();
    await Store.i.start(DemoBackend(delay: Duration.zero));
    await Store.i.sendOtp('0912345678');
    await Store.i.verifyOtp('0912345678', '123456');
    await Store.i.completeProfile('إيهاب أحمد', false);
  });

  Future<void> shot(WidgetTester t, String name, Widget w, {Future<void> Function()? then, Size size = const Size(390, 844)}) async {
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(w));
    await settle(t);
    if (then != null) {
      await then();
      await settle(t);
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
  }

  testWidgets('الخريطة: كل سوريا', (t) => shot(t, 'map_all', const MapExploreScreen(day: 1)), skip: !enabled);
  testWidgets('الخريطة: حمص', (t) => shot(t, 'map_homs', const MapExploreScreen(focusCity: 'حمص', day: 1)), skip: !enabled);
  testWidgets('الخريطة: نقطة مختارة', (t) => shot(t, 'map_pick', const MapExploreScreen(focusCity: 'حمص', day: 1), then: () => t.longPressAt(const Offset(195, 330))), skip: !enabled);
  testWidgets('الخريطة: الفلاتر', (t) => shot(t, 'map_filters', const MapExploreScreen(day: 1), then: () => t.tap(find.byIcon(Icons.tune_rounded).first)), skip: !enabled);
  testWidgets('الخريطة: الطبقات', (t) => shot(t, 'map_layers', const MapExploreScreen(day: 1), then: () => t.tap(find.byTooltip('طبقات الخريطة'))), skip: !enabled);
  testWidgets('الخريطة: مسار', (t) => shot(t, 'map_route', const MapExploreScreen(focusCity: 'حمص', day: 1), then: () async {
        await t.longPressAt(const Offset(195, 330));
        await settle(t);
        await t.tap(find.text('ابدأ المسار من هون'));
        await settle(t);
        await t.longPressAt(const Offset(120, 250));
        await settle(t);
        await t.tap(find.textContaining('لهون').first);
      }), skip: !enabled);
  testWidgets('الخريطة: داكنة', (t) async {
    Store.i.setMapDark(true);
    addTearDown(() => Store.i.setMapDark(false));
    await shot(t, 'map_dark', const MapExploreScreen(focusCity: 'دمشق', day: 1));
  }, skip: !enabled);
  testWidgets('بحث الخريطة', (t) => shot(t, 'map_search', const MapSearchScreen(), then: () => t.enterText(find.byType(TextField), 'حم')), skip: !enabled);
  testWidgets('نقطة التجمع', (t) => shot(t, 'pick_point', PickPointScreen(tripsFor('اللاذقية', 'دمشق').first)), skip: !enabled);
  testWidgets('الخريطة: موبايل صغير', (t) => shot(t, 'map_small', const MapExploreScreen(day: 1), size: const Size(320, 568)), skip: !enabled);
  testWidgets('الخريطة: تابلت', (t) => shot(t, 'map_tablet', const MapExploreScreen(focusCity: 'اللاذقية', day: 1), size: const Size(768, 1024)), skip: !enabled);
  testWidgets('المحفظة', (t) async {
    final b = DemoBackend(delay: Duration.zero);
    await t.runAsync(() async {
      await b.verifyOtp('+963912345678', '123456');
      await b.completeProfile('سامر السائق', false);
      await b.submitApplication(DriverApp()..city = 'اللاذقية'..car = 'كيا'..year = '2015'..color = 'فضي'..plate = 'ب 1'..slot = '10:00', (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      b.approveAfterInterview();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await Store.i.start(b);
      final tr = await b.publishTrip(tripsFor('اللاذقية', 'دمشق').first);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await b.respond((await b.myRides()).firstWhere((r) => r.t.id == tr.id).reqs.first, true);
      await b.requestTopup(100000, TopupMethod.shamCash, 'SC-1234');
    });
    await shot(t, 'wallet', const WalletScreen());
  }, skip: !enabled);
}
