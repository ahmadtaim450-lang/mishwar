import 'package:flutter_test/flutter_test.dart';
import 'package:mishwar/core/errors.dart';
import 'package:mishwar/data/mock.dart';
import 'package:mishwar/data/store.dart';

void main() {
  group('البحث عن المدن', () {
    test('بيفهم أخطاء الكتابة الشائعة', () {
      expect(searchCities('حماه').first.name, 'حماة');
      expect(searchCities('لاذقية').first.name, 'اللاذقية');
      expect(searchCities('الحسكه').first.name, 'الحسكة');
      expect(searchCities('كورنيش').map((c) => c.name), contains('طرطوس'));
    });
    test('الاستثناء والفراغ', () {
      expect(searchCities('', exclude: 'دمشق').any((c) => c.name == 'دمشق'), isFalse);
      expect(searchCities('xyz'), isEmpty);
      expect(cityNamed('حماه')?.name, 'حماة');
      expect(cityNamed('مدينة مو موجودة'), isNull);
    });
    test('كل مدينة إلها إحداثيات ومعرّف بالسيرفر', () {
      for (final c in cities) {
        expect(geo.containsKey(c.name), isTrue, reason: c.name);
        expect(cityIds.containsKey(c.name), isTrue, reason: c.name);
      }
    });
  });

  group('رقم الموبايل', () {
    test('صيغ مختلفة لنفس الرقم', () {
      expect(normalizePhone('0912345678'), '+963912345678');
      expect(normalizePhone('912 345 678'), '+963912345678');
      expect(normalizePhone('+963 912345678'), '+963912345678');
      expect(normalizePhone('00963912345678'), '+963912345678');
      expect(normalizePhone('٠٩١٢٣٤٥٦٧٨'), '+963912345678');
    });
    test('الأرقام الغلط بترفض', () {
      expect(() => normalizePhone('12345'), throwsA(isA<AppException>().having((e) => e.code, 'code', 'INVALID_PHONE')));
      expect(() => normalizePhone('0812345678'), throwsA(isA<AppException>()));
      expect(() => normalizePhone(''), throwsA(isA<AppException>()));
    });
  });

  group('المسافات والأسعار', () {
    test('اللاذقية ← دمشق منطقية', () {
      final km = roadKm('اللاذقية', 'دمشق');
      expect(km, inInclusiveRange(280, 360));
      expect(suggestedPrice('اللاذقية', 'دمشق'), inInclusiveRange(65000, 90000));
      expect(stopsBetween('اللاذقية', 'دمشق'), contains('طرطوس'));
      expect(suggestedPrice('اللاذقية', 'جبلة'), 15000); // أقل سعر
    });
    test('صيغ العدد', () {
      expect(seatsLabel(1), 'مقعد واحد');
      expect(seatsLabel(2), 'مقعدين');
      expect(seatsLabel(3), '3 مقاعد');
      expect(paxLabel(2), 'راكبين');
      expect(tripsLabel(0), 'ما في رحلات');
      expect(fmtDur(125), 'ساعتين 5 د');
    });
    test('رحلات التجربة ثابتة ومنطقية', () {
      final a = tripsFor('اللاذقية', 'دمشق', day: 1);
      final b = tripsFor('اللاذقية', 'دمشق', day: 1);
      expect(a.map((t) => t.id), b.map((t) => t.id));
      expect(tripsFor('دمشق', 'دمشق'), isEmpty);
      for (final t in a) {
        expect(t.seatsLeft, inInclusiveRange(1, t.seatsTotal));
        expect(t.kind == RideKind.women, t.driver.name == 'ريم' || t.driver.name == 'أم أحمد');
      }
    });
  });

  group('رسائل الأخطاء', () {
    test('رموز السيرفر بتتحوّل لعربي', () {
      final e = AppException.from(Exception('PostgrestException(message: NOT_ENOUGH_SEATS, code: P0001)'));
      expect(e.code, 'NOT_ENOUGH_SEATS');
      expect(e.message, contains('مقاعد'));
      expect(AppException.from(Exception('TRIP_NOT_FOUND')).code, 'TRIP_NOT_FOUND');
    });
    test('الأخطاء المجهولة ما بتكشف تفاصيل', () {
      final e = AppException.from(Exception('relation "secret_table" does not exist at line 42'));
      expect(e.code, 'UNKNOWN');
      expect(e.message.contains('secret'), isFalse);
    });
  });
}
