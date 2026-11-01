import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishwar/core/theme.dart';
import 'package:mishwar/data/demo_backend.dart';
import 'package:mishwar/data/store.dart';
import 'package:mishwar/screens/auth.dart';
import 'package:mishwar/screens/driver_join.dart';
import 'package:mishwar/screens/home.dart';
import 'package:mishwar/screens/my_trips.dart';
import 'package:mishwar/screens/profile.dart';
import 'package:mishwar/screens/search.dart';
import 'package:mishwar/screens/trip.dart';
import 'package:mishwar/screens/messages.dart';
import 'package:mishwar/screens/publish.dart';
import 'package:mishwar/screens/map_explore.dart';
import 'package:mishwar/screens/map_search.dart';
import 'package:mishwar/screens/pick_point.dart';
import 'package:mishwar/screens/wallet.dart';
import 'package:mishwar/map/map_widgets.dart';
import 'package:mishwar/map/models.dart';
import 'package:mishwar/map/tiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: buildTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      scaffoldMessengerKey: Store.i.messenger,
      home: child,
    );

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

const sizes = {'موبايل صغير': Size(320, 568), 'موبايل': Size(390, 844), 'تابلت': Size(768, 1024)};

void main() {
  setUpAll(() async {
    TileCache.disabled = true;
    SharedPreferences.setMockInitialValues({});
    await Store.i.start(DemoBackend(delay: Duration.zero));
    await Store.i.sendOtp('0912345678');
    await Store.i.verifyOtp('0912345678', '123456');
    await Store.i.completeProfile('إيهاب أحمد', false);
    await Store.i.refreshAll();
  });

  final screens = <String, Widget Function()>{
    'الرئيسية': () => const Scaffold(body: HomeScreen()),
    'النتائج': () => const ResultsScreen(from: 'اللاذقية', to: 'دمشق'),
    'تفاصيل الرحلة': () => TripDetailsScreen(tripsFor('اللاذقية', 'دمشق').first),
    'رحلاتي': () => const Scaffold(body: MyTripsScreen()),
    'التذكرة': () => TicketScreen(Store.i.upcoming.first),
    'حسابي': () => const Scaffold(body: ProfileScreen()),
    'الدخول': () => const LoginScreen(),
    'صير سائق': () => const Scaffold(body: DriverJoinIntro()),
    'طلب الانضمام': () => const DriverApplyFlow(),
    'كيف منوثّق': () => const HowWeVerifyScreen(),
    'ملف السائق': () => DriverScreen(tripsFor('اللاذقية', 'دمشق').first.driver),
    'تعديل الملف': () => const EditProfileScreen(),
    'تفضيلات السفر': () => const TravelPrefsScreen(),
    'سياراتي': () => const CarsScreen(),
    'السجل': () => const HistoryScreen(),
    'التوثيق': () => const VerifyScreen(),
    'الطوارئ': () => const SosScreen(),
    'الإشعارات': () => const NotificationsScreen(),
    'الرسائل': () => const Scaffold(body: InboxScreen()),
    'نشر رحلة': () => const PublishFlow(),
    'شاشة السائق': () => DriverLiveScreen(MyRide(tripsFor('حمص', 'حلب').first)),
    'تقييم راكب': () => RateRiderScreen(RideReq(tripsFor('حمص', 'حلب').first.driver, '')),
    'تقييم السائق': () => RateScreen(Store.i.past.first),
    'مشاركة الموقع': () => ShareTripScreen(Store.i.upcoming.first),
    'متابعة الرحلة': () => LiveTripScreen(Store.i.upcoming.first),
    'المسار': () => RouteScreen(tripsFor('اللاذقية', 'دمشق').first),
    'الخريطة': () => const MapExploreScreen(),
    'الخريطة لطريق': () => const MapExploreScreen(focusCity: 'حمص', to: 'دمشق', day: 1),
    'بحث الخريطة': () => const MapSearchScreen(),
    'نقطة التجمع': () => PickPointScreen(tripsFor('اللاذقية', 'دمشق').first),
    'المحفظة (مو سائق)': () => const WalletScreen(),
  };

  for (final s in sizes.entries) {
    for (final sc in screens.entries) {
      testWidgets('${sc.key} بدون overflow على ${s.key}', (t) async {
        t.view.physicalSize = s.value * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        await t.pumpWidget(wrap(sc.value()));
        await settle(t);
        expect(t.takeException(), isNull);
      });
    }
  }

  // خط مكبّر (إعدادات إمكانية الوصول) على موبايل عادي
  for (final name in ['الرئيسية', 'النتائج', 'تفاصيل الرحلة', 'رحلاتي', 'التذكرة', 'حسابي', 'الدخول', 'طلب الانضمام', 'الخريطة', 'نقطة التجمع']) {
    testWidgets('$name بخط مكبّر 130%', (t) async {
      t.view.physicalSize = const Size(390, 844) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), textScaler: TextScaler.linear(1.3)),
        child: wrap(screens[name]!()),
      ));
      await settle(t);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('البحث من الرئيسية بيفتح نتائج حقيقية', (t) async {
    t.view.physicalSize = const Size(390, 844) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(const Scaffold(body: HomeScreen())));
    await settle(t);
    await t.tap(find.text('دوّر على رحلة'));
    await settle(t);
    expect(find.byType(ResultsScreen), findsOneWidget);
    expect(find.byType(TripCard), findsWidgets);
  });

  testWidgets('زر التبديل بيقلب المدن', (t) async {
    t.view.physicalSize = const Size(390, 844) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(const Scaffold(body: HomeScreen())));
    await settle(t);
    final fields = find.byType(TextField);
    expect((t.widget<TextField>(fields.at(0))).controller!.text, 'اللاذقية');
    await t.tap(find.byIcon(Icons.swap_vert_rounded));
    await settle(t);
    expect((t.widget<TextField>(fields.at(0))).controller!.text, 'دمشق');
    expect((t.widget<TextField>(fields.at(1))).controller!.text, 'اللاذقية');
  });

  testWidgets('الكتابة بخانة المدينة بتطلع اقتراحات', (t) async {
    t.view.physicalSize = const Size(390, 844) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(const Scaffold(body: HomeScreen())));
    await settle(t);
    await t.tap(find.byType(TextField).at(1));
    await t.pump();
    await t.enterText(find.byType(TextField).at(1), 'حماه');
    await settle(t);
    expect(find.text('حماة'), findsWidgets);
  });

  testWidgets('رقم غلط بالدخول بيعطي رسالة واضحة', (t) async {
    t.view.physicalSize = const Size(390, 844) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(const LoginScreen()));
    await settle(t);
    await t.enterText(find.byType(TextField), '123');
    await t.ensureVisible(find.text('متابعة'));
    await t.pump();
    await t.tap(find.text('متابعة'));
    await settle(t);
    expect(find.textContaining('رقم الموبايل مو صحيح'), findsOneWidget);
  });

  testWidgets('الخريطة بتعرض الرحلات مجمّعة وبتفتح قائمة المجموعة', (t) async {
    t.view.physicalSize = const Size(390, 844) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(const MapExploreScreen(day: 1)));
    await settle(t);
    expect(find.byType(ClusterBubble), findsWidgets, reason: 'تكبير بعيد = مجموعات');
    expect(find.textContaining('بهالمنطقة'), findsOneWidget);
    expect(find.byType(MapTripTile), findsWidgets);
    // فلتر "اليوم" بيعيد التحميل بلا أخطاء
    await t.tap(find.text('بكرا').first);
    await settle(t);
    await t.tap(find.text('اليوم').first);
    await settle(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('الضغط المطوّل على الخريطة بيختار نقطة وبيعرض الخيارات', (t) async {
    t.view.physicalSize = const Size(390, 844) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(const MapExploreScreen(focusCity: 'حمص', day: 1)));
    await settle(t);
    await t.longPressAt(const Offset(195, 300));
    await settle(t);
    expect(find.text('رحلات من هون'), findsOneWidget);
    expect(find.text('المسار لهون'), findsOneWidget);
    expect(find.textContaining('قرب'), findsWidgets, reason: 'العنوان التقريبي من أقرب مدينة');
    await t.tap(find.text('رحلات من هون'));
    await settle(t);
    expect(find.textContaining('قريبة من'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('بحث الخريطة بيلاقي المدينة وبيرجعها', (t) async {
    t.view.physicalSize = const Size(390, 844) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    GeoPlace? picked;
    await t.pumpWidget(wrap(Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => picked = await Navigator.of(c).push<GeoPlace>(MaterialPageRoute(builder: (_) => const MapSearchScreen())),
            child: const Text('افتح'),
          ),
        ),
      ),
    )));
    await t.tap(find.text('افتح'));
    await settle(t);
    await t.enterText(find.byType(TextField), 'طرطو');
    await settle(t);
    await t.tap(find.text('طرطوس').first);
    await settle(t);
    expect(picked?.name, 'طرطوس');
    expect(picked?.kind, PlaceKind.city);
  });

  testWidgets('السائق بيحدد نقطة التجمع وبتنحفظ', (t) async {
    t.view.physicalSize = const Size(390, 844) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final trip = tripsFor('اللاذقية', 'دمشق').first;
    await t.pumpWidget(wrap(PickPointScreen(trip)));
    await settle(t);
    await t.tap(find.text('هون نقطة الانطلاق'));
    await settle(t);
    await t.tap(find.text('احفظ هيك'));
    await settle(t);
    final pts = await Store.i.tripPoints(trip);
    expect(pts.$1, isNotNull);
    expect(pts.$1!.latitude, closeTo(35.52, .05));
  });
}
