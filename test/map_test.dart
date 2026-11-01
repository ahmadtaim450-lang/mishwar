// اختبارات نظام الخرائط: التجميع، حدود الخريطة، التحميل حسب المنطقة، البوصلة،
// الحسابات الجغرافية، كاش الصور، وقواعد الخرائط بالوضع التجريبي.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mishwar/core/errors.dart';
import 'package:mishwar/data/demo_backend.dart';
import 'package:mishwar/data/mock.dart';
import 'package:mishwar/data/store.dart';
import 'package:mishwar/map/cluster.dart';
import 'package:mishwar/map/geo_math.dart';
import 'package:mishwar/map/location_service.dart';
import 'package:mishwar/map/models.dart';
import 'package:mishwar/map/tiles.dart';
import 'package:mishwar/map/viewport.dart';

Matcher code(String c) => throwsA(isA<AppException>().having((e) => e.code, 'code', c));

const damascus = LatLng(33.5138, 36.2765);
const homs = LatLng(34.7324, 36.7137);
const latakia = LatLng(35.5196, 35.7832);

void main() {
  group('التجميع (Clustering)', () {
    test('نقاط متقاربة بتتجمع بالتكبير البعيد وبتتفرق بالقريب', () {
      final pts = [homs, const LatLng(34.7330, 36.7140), damascus];
      final far = clusterize<LatLng>(pts, (p) => p, 7);
      expect(far.length, 2);
      expect(far.firstWhere((c) => c.size == 2).point.latitude, closeTo(34.7327, 1e-3));
      final near = clusterize<LatLng>(pts, (p) => p, 18);
      expect(near.length, 3);
    });

    test('نفس النقطة بالزبط بتضل مجموعة حتى بأقرب تكبير', () {
      final same = List.filled(5, homs);
      expect(clusterize<LatLng>(same, (p) => p, 18).single.size, 5);
    });

    test('ما في عنصر بيضيع أو بيتكرر', () {
      final r = math.Random(1);
      final pts = [for (var i = 0; i < 2000; i++) LatLng(32.5 + r.nextDouble() * 4.5, 35.8 + r.nextDouble() * 6)];
      for (final z in [6.0, 8.0, 10.5, 13.0, 16.0]) {
        final c = clusterize<LatLng>(pts, (p) => p, z);
        expect(c.fold<int>(0, (a, x) => a + x.size), pts.length, reason: 'zoom $z');
      }
    });

    test('أداء: 10 آلاف نقطة بأقل من 150 ملي ثانية', () {
      final r = math.Random(2);
      final pts = [for (var i = 0; i < 10000; i++) LatLng(32.5 + r.nextDouble() * 4.5, 35.8 + r.nextDouble() * 6)];
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        clusterize<LatLng>(pts, (p) => p, 8 + i.toDouble());
      }
      sw.stop();
      expect(sw.elapsedMilliseconds / 5, lessThan(150));
    });

    test('حدود المجموعة والتكبير المقرّب', () {
      final c = Cluster<LatLng>(homs, [homs, damascus]);
      final (sw, ne) = c.bounds((p) => p);
      expect(sw, const LatLng(33.5138, 36.2765));
      expect(ne, const LatLng(34.7324, 36.7137));
      expect(clusterZoom(7.74), 7.5);
      expect(clusterZoom(8.01), 8);
    });

    test('الإسقاط: الشرق يمين والشمال فوق', () {
      final a = project(homs, 8), b = project(damascus, 8);
      expect(a.y, lessThan(b.y));
      expect(project(const LatLng(0, 0), 0), const math.Point(128.0, 128.0));
    });
  });

  group('حدود الخريطة والفلاتر', () {
    test('توسيع وتقريب وتقاطع', () {
      const b = GeoBounds(34, 36, 35, 37);
      expect(b.contains(homs), isTrue);
      expect(b.contains(damascus), isFalse);
      final e = b.expand(.25);
      expect(e.south, closeTo(33.75, 1e-9));
      expect(e.east, closeTo(37.25, 1e-9));
      expect(const GeoBounds(34.01, 36.02, 34.98, 36.97).snap(.25), const GeoBounds(34, 36, 35, 37));
      expect(b.intersect(const GeoBounds(34.5, 36.5, 40, 40)), const GeoBounds(34.5, 36.5, 35, 37));
      expect(b.intersect(const GeoBounds(40, 40, 41, 41)), isNull);
      expect(GeoBounds.syria.containsBounds(b), isTrue);
    });

    test('الفلتر: مفتاح ثابت ونسخ بتعديل', () {
      const f = MapFilter();
      expect(f.active, 0);
      final g = f.copyWith(day: 1, kinds: {RideKind.family}, maxPrice: 50000);
      expect(g.active, 3);
      expect(g.copyWith(day: null).day, isNull);
      expect(g.copyWith(seats: 2).maxPrice, 50000);
      expect(MapFilter(kinds: {RideKind.men, RideKind.family}) == MapFilter(kinds: {RideKind.family, RideKind.men}), isTrue);
    });
  });

  group('التحميل حسب المنطقة الظاهرة', () {
    test('بيستنى يوقف التحريك، وبيطلب مرة وحدة', () async {
      final loader = ViewportLoader<int>((a, f) async => [1, 2, 3], debounce: const Duration(milliseconds: 30));
      final results = <List<int>>[];
      for (var i = 0; i < 5; i++) {
        loader.request(GeoBounds(34 + i * .01, 36, 35, 37), const MapFilter(), (r) => results.add(r.items));
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(loader.requests, 1);
      expect(results.single, [1, 2, 3]);
    });

    test('تحريك بسيط جوّا المنطقة المحمّلة ما بيطلب شي', () async {
      final loader = ViewportLoader<int>((a, f) async => [1], debounce: Duration.zero);
      await loader.load(const GeoBounds(34, 36, 35, 37), const MapFilter(), (_) {});
      loader.request(const GeoBounds(34.1, 36.1, 34.9, 36.9), const MapFilter(), (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(loader.requests, 1);
      // فلتر مختلف = طلب جديد
      await loader.load(const GeoBounds(34.1, 36.1, 34.9, 36.9), const MapFilter(day: 1), (_) {});
      expect(loader.requests, 2);
    });

    test('الكاش بيرجع نفس المنطقة بلا طلب، وبينتهي بعد المدة', () async {
      var now = DateTime(2026);
      final loader = ViewportLoader<int>((a, f) async => [7], debounce: Duration.zero, now: () => now);
      const v = GeoBounds(34, 36, 35, 37);
      ViewportResult<int>? last;
      await loader.load(v, const MapFilter(), (r) => last = r);
      await loader.load(v, const MapFilter(), (r) => last = r);
      expect(loader.requests, 1);
      expect(last!.fromCache, isTrue);
      now = now.add(const Duration(minutes: 3));
      await loader.load(v, const MapFilter(), (r) => last = r);
      expect(loader.requests, 2);
      loader.invalidate();
      await loader.load(v, const MapFilter(), (r) => last = r);
      expect(loader.requests, 3);
    });

    test('الرد القديم بينرمى إذا إجا بعد الأحدث', () async {
      final loader = ViewportLoader<String>((a, f) async {
        await Future<void>.delayed(Duration(milliseconds: a.south < 34 ? 60 : 5));
        return [a.south < 34 ? 'قديم' : 'جديد'];
      }, debounce: Duration.zero);
      final got = <String>[];
      final slow = loader.load(const GeoBounds(33, 36, 35, 37), const MapFilter(), (r) => got.add(r.items.single));
      final fast = loader.load(const GeoBounds(35.5, 36, 36, 37), const MapFilter(), (r) => got.add(r.items.single));
      await Future.wait([slow, fast]);
      expect(got, ['جديد']);
    });

    test('الخطأ بيوصل، والمنطقة بتتوسع وتتقرّب', () async {
      final loader = ViewportLoader<int>((a, f) async => throw const AppException('NETWORK', 'x'), debounce: Duration.zero);
      Object? err;
      await loader.load(const GeoBounds(34, 36, 35, 37), const MapFilter(), (_) {}, onError: (e) => err = e);
      expect(err, isA<AppException>());
      final area = ViewportLoader.areaFor(const GeoBounds(34.02, 36.03, 34.98, 36.96));
      expect(area.containsBounds(const GeoBounds(34.02, 36.03, 34.98, 36.96)), isTrue);
      expect(area.south * 20 % 1, closeTo(0, 1e-9));
    });
  });

  group('البوصلة والاتجاه', () {
    // الجهاز مسطّح، والحقل المغناطيسي فيه مركّبة لتحت (نصف الكرة الشمالي)
    const flat = [0.0, 0.0, 9.8];
    test('شمال، شرق، جنوب، غرب', () {
      expect(headingFromSensors(flat, [0, 20, -40]), closeTo(0, .5));
      expect(headingFromSensors(flat, [-20, 0, -40]), closeTo(90, .5));
      expect(headingFromSensors(flat, [0, -20, -40]), closeTo(180, .5));
      expect(headingFromSensors(flat, [20, 0, -40]), closeTo(270, .5));
    });

    test('الميلان ما بيغيّر الاتجاه', () {
      // الجهاز مايل لقدّام 30 درجة حول محور x، ومتجه للشمال
      const t = 30 * math.pi / 180;
      final a = [0.0, 9.8 * math.sin(t), 9.8 * math.cos(t)];
      // نفس الحقل (0, 20, -40) بإحداثيات الجهاز المايل
      final m = [0.0, 20 * math.cos(t) - 40 * math.sin(t), -20 * math.sin(t) - 40 * math.cos(t)];
      expect(headingFromSensors(a, m), closeTo(0, 1));
    });

    test('قراءات مستحيلة بترجع null', () {
      expect(headingFromSensors([0, 0, 0], [0, 20, -40]), isNull);
      expect(headingFromSensors(flat, [0, 0, 0]), isNull);
    });

    test('فرق الزوايا والتنعيم عند 359→0', () {
      expect(angleDelta(350, 10), 20);
      expect(angleDelta(10, 350), -20);
      expect(smoothAngle(350, 10, .5), closeTo(0, 1e-9));
      expect(locMessage(LocStatus.serviceOff), contains('GPS'));
    });
  });

  group('حسابات جغرافية', () {
    test('المسافة دمشق ← حمص', () => expect(kmBetween(damascus, homs), inInclusiveRange(135, 148)));

    test('مسار تقريبي واضح إنو تقريبي', () {
      final r = approximateRoute([latakia, homs, damascus]);
      expect(r.approximate, isTrue);
      expect(r.km, greaterThan(kmBetween(latakia, damascus)));
      expect(r.seconds, greaterThan(3600));
      expect(r.line.length, 3);
    });

    test('تنسيق المسافة والوقت والسعر', () {
      expect(fmtKm(.42), '420 م');
      expect(fmtKm(12.44), '12.4 كم');
      expect(fmtKm(182.6), '183 كم');
      expect(fmtSeconds(30), '1 د');
      expect(fmtSeconds(45 * 60), '45 د');
      expect(fmtSeconds(2 * 3600 + 10 * 60), 'ساعتين و10 د');
      expect(fmtPriceShort(75000), '75 ألف');
    });

    test('بُعد نقطة عن الطريق', () {
      final line = [latakia, homs];
      expect(distanceToLineKm(latakia, line), closeTo(0, .01));
      expect(distanceToLineKm(damascus, line), greaterThan(100));
      final b = boundsOf([latakia, damascus, homs]);
      expect(b.south, damascus.latitude);
      expect(b.north, latakia.latitude);
    });
  });

  group('صور الخريطة', () {
    test('اسم ملف الكاش ثابت وما فيه المفتاح', () {
      final a = TileCache.fileName('https://x.test/7/80/50.png?key=SECRET');
      expect(a, TileCache.fileName('https://x.test/7/80/50.png?key=OTHER'));
      expect(a, isNot(contains('SECRET')));
      expect(a, isNot(TileCache.fileName('https://x.test/7/80/51.png?key=SECRET')));
    });

    test('عدد الصور لمنطقة طريق معقول', () {
      final t = tilesFor((south: 33.4, west: 35.7, north: 35.6, east: 36.8), 7, 11);
      expect(t, isNotEmpty);
      expect(t.length, lessThan(1200));
      expect(t.every((x) => x.$1 >= 7 && x.$1 <= 11), isTrue);
    });

    test('بلا إعدادات: OSM مع فلتر داكن', () {
      expect(MapTiles.url(false), MapTiles.osm);
      expect(MapTiles.needsDarkFilter(true), isTrue);
      expect(MapTiles.needsDarkFilter(false), isFalse);
      expect(MapTiles.allowOffline, isFalse);
    });
  });

  group('الخرائط بالوضع التجريبي (نفس قواعد السيرفر)', () {
    late DemoBackend b;
    setUp(() async {
      b = DemoBackend(delay: Duration.zero);
      await b.verifyOtp('+963912345678', '123456');
      await b.completeProfile('سامي الراكب', false);
    });
    tearDown(() => b.dispose());

    test('رحلات ضمن حدود المنطقة بس، ومرتبة حسب القرب', () async {
      const view = GeoBounds(35.3, 35.6, 35.7, 36.0); // اللاذقية وجبلة
      final list = await b.mapTrips(view, const MapFilter(day: 1), me: latakia);
      expect(list, isNotEmpty);
      expect(list.every((t) => view.contains(t.point)), isTrue);
      expect(list.first.board, 'اللاذقية');
      for (var i = 1; i < list.length; i++) {
        expect(list[i].distanceKm! >= list[i - 1].distanceKm!, isTrue);
      }
    });

    test('فلترة الجنس والنوع والسعر والوجهة والمقاعد', () async {
      final all = await b.mapTrips(GeoBounds.syria, const MapFilter(day: 1));
      expect(all.any((t) => t.kind == RideKind.women), isFalse, reason: 'الرجال ما بيشوفوا النسائية');
      final fam = await b.mapTrips(GeoBounds.syria, const MapFilter(day: 1, kinds: {RideKind.family}));
      expect(fam.every((t) => t.kind == RideKind.family), isTrue);
      final cheap = await b.mapTrips(GeoBounds.syria, const MapFilter(day: 1, maxPrice: 40000));
      expect(cheap.every((t) => t.price <= 40000), isTrue);
      final toHoms = await b.mapTrips(GeoBounds.syria, const MapFilter(day: 1, to: 'حمص'));
      expect(toHoms.every((t) => t.to == 'حمص'), isTrue);
      final big = await b.mapTrips(GeoBounds.syria, const MapFilter(day: 1, seats: 4));
      expect(big.every((t) => t.seats >= 4), isTrue);
      await expectLater(() => b.mapTrips(GeoBounds.syria, const MapFilter(seats: 0)), code('INVALID_INPUT'));
      await expectLater(() => b.mapTrips(const GeoBounds(36, 36, 35, 37), const MapFilter()), code('INVALID_INPUT'));
    });

    test('رحلات قريبة ضمن مسافة', () async {
      final near = await b.tripsNear(homs, 20, const MapFilter(day: 1));
      expect(near, isNotEmpty);
      expect(near.every((t) => t.distanceKm! <= 20), isTrue);
      await expectLater(() => b.tripsNear(homs, 1000, const MapFilter()), code('INVALID_INPUT'));
    });

    test('بحث محلي وأقرب مدينة وعنوان تقريبي', () async {
      expect((await b.searchPlaces('حمص')).first.name, 'حمص');
      expect((await b.searchPlaces('اللاذقيه')).first.name, 'اللاذقية');
      expect((await b.searchPlaces('', near: const LatLng(35.36, 35.93))).first.name, 'جبلة');
      expect((await b.nearestCity(const LatLng(35.40, 35.90)))!.$1, 'جبلة');
      final rv = await b.reverseGeocode(const LatLng(35.45, 35.85));
      expect(rv!.name, contains('قرب'));
      expect(await b.geocodeSuggest('شارع بغداد'), isEmpty, reason: 'التجريبي ما بيتصل بمزود عناوين');
    });

    test('مسار تقريبي بالاختبارات (بلا شبكة) ورفض نقاط غلط', () async {
      final r = await b.route([latakia, damascus]);
      expect(r.single.approximate, isTrue);
      await expectLater(() => b.route([latakia]), code('INVALID_INPUT'));
    });

    test('الأماكن المحفوظة: بيت واحد، برّا سوريا مرفوض، الحذف', () async {
      await b.savePlace('البيت', latakia, kind: 'home');
      await b.savePlace('بيت أهلي', homs, kind: 'home');
      expect((await b.myPlaces()).where((p) => p.kind == 'home').length, 1);
      await expectLater(() => b.savePlace('برلين', const LatLng(52.5, 13.4)), code('OUTSIDE_SYRIA'));
      await expectLater(() => b.savePlace('', homs), code('INVALID_INPUT'));
      final p = await b.savePlace('الجامعة', damascus);
      expect((await b.searchPlaces('جامع')).first.kind, PlaceKind.saved);
      await b.deletePlace(p.id);
      await expectLater(() => b.deletePlace(p.id), code('NOT_FOUND'));
    });

    test('نقطة التجمع لازم تكون قريبة من مدينة الانطلاق وبتطلع على الخريطة', () async {
      final t = tripsFor('اللاذقية', 'دمشق', day: 1).firstWhere((t) => t.kind != RideKind.women);
      await expectLater(() => b.setTripPoints(t, pickup: damascus), code('POINT_TOO_FAR'));
      const spot = LatLng(35.515, 35.79);
      await b.setTripPoints(t, pickup: spot);
      expect((await b.tripPoints(t)).$1, spot);
      final onMap = await b.mapTrips(const GeoBounds(35.3, 35.6, 35.7, 36.0), const MapFilter(day: 1));
      final m = onMap.firstWhere((x) => x.tripId == t.id);
      expect(m.exact, isTrue);
      expect(m.point, spot);
    });

    test('من علامة على الخريطة للرحلة الكاملة', () async {
      await Store.i.start(b);
      final m = (await Store.i.mapTrips(GeoBounds.syria, const MapFilter(day: 1))).first;
      final t = await Store.i.tripOf(m);
      expect(t, isNotNull);
      expect(t!.id, m.tripId);
      expect(dayOffset(m.departure), 1);
    });
  });

  test('آخر الأماكن: حفظ واسترجاع', () {
    const p = GeoPlace(name: 'حمص', label: 'مركز', point: homs, kind: PlaceKind.city, city: 'حمص');
    final back = GeoPlace.fromJson(p.toJson())!;
    expect(back.name, 'حمص');
    expect(back.kind, PlaceKind.city);
    expect(back.point, homs);
    expect(GeoPlace.fromJson({'x': 1}), isNull);
  });
}
