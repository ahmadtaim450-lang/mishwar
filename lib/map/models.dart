// نماذج نظام الخرائط (مشتركة بين السيرفر والوضع التجريبي والواجهة).
import 'package:latlong2/latlong.dart';
import '../data/mock.dart' show RideKind;

/// مستطيل جغرافي (حدود الخريطة الظاهرة).
class GeoBounds {
  final double south, west, north, east;
  const GeoBounds(this.south, this.west, this.north, this.east);

  /// حدود سوريا التقريبية.
  static const syria = GeoBounds(32.2, 35.5, 37.4, 42.5);

  bool contains(LatLng p) => p.latitude >= south && p.latitude <= north && p.longitude >= west && p.longitude <= east;
  bool containsBounds(GeoBounds o) => o.south >= south && o.north <= north && o.west >= west && o.east <= east;
  LatLng get center => LatLng((south + north) / 2, (west + east) / 2);

  /// توسيع بنسبة من كل جهة (لحتى التحريك البسيط ما يحتاج طلب جديد).
  GeoBounds expand(double ratio) {
    final dy = (north - south) * ratio, dx = (east - west) * ratio;
    return GeoBounds((south - dy).clamp(-90, 90), (west - dx).clamp(-180, 180), (north + dy).clamp(-90, 90), (east + dx).clamp(-180, 180));
  }

  /// تقريب لشبكة ثابتة: حدود متقاربة بتعطي نفس المفتاح (فالكاش بيفيد).
  GeoBounds snap(double step) {
    double down(double v) => (v / step).floorToDouble() * step;
    double up(double v) => (v / step).ceilToDouble() * step;
    return GeoBounds(down(south), down(west), up(north), up(east));
  }

  /// القسم المشترك مع حدود تانية (أو null إذا ما في تقاطع).
  GeoBounds? intersect(GeoBounds o) {
    final s = south > o.south ? south : o.south, n = north < o.north ? north : o.north;
    final w = west > o.west ? west : o.west, e = east < o.east ? east : o.east;
    return s > n || w > e ? null : GeoBounds(s, w, n, e);
  }

  String get key => '${south.toStringAsFixed(3)},${west.toStringAsFixed(3)},${north.toStringAsFixed(3)},${east.toStringAsFixed(3)}';
  @override
  bool operator ==(Object o) => o is GeoBounds && o.key == key;
  @override
  int get hashCode => key.hashCode;
  @override
  String toString() => 'GeoBounds($key)';
}

/// فلاتر الرحلات على الخريطة.
class MapFilter {
  /// null = كل الأيام الجاية، 0 اليوم، 1 بكرا...
  final int? day;
  final String? to; // اسم مدينة الوصول بالعربي
  final Set<RideKind> kinds; // فاضي = الكل
  final int seats;
  final int? maxPrice;
  final bool instantOnly;
  const MapFilter({this.day, this.to, this.kinds = const {}, this.seats = 1, this.maxPrice, this.instantOnly = false});

  MapFilter copyWith({Object? day = _keep, Object? to = _keep, Set<RideKind>? kinds, int? seats, Object? maxPrice = _keep, bool? instantOnly}) => MapFilter(
        day: day == _keep ? this.day : day as int?,
        to: to == _keep ? this.to : to as String?,
        kinds: kinds ?? this.kinds,
        seats: seats ?? this.seats,
        maxPrice: maxPrice == _keep ? this.maxPrice : maxPrice as int?,
        instantOnly: instantOnly ?? this.instantOnly,
      );

  /// عدد الفلاتر المفعّلة (للشارة على زر الفلاتر).
  int get active => (day != null ? 1 : 0) + (to != null ? 1 : 0) + (kinds.isNotEmpty ? 1 : 0) + (seats > 1 ? 1 : 0) + (maxPrice != null ? 1 : 0) + (instantOnly ? 1 : 0);

  String get key => '${day ?? '-'}|${to ?? '-'}|${(kinds.map((k) => k.name).toList()..sort()).join(',')}|$seats|${maxPrice ?? '-'}|$instantOnly';
  @override
  bool operator ==(Object o) => o is MapFilter && o.key == key;
  @override
  int get hashCode => key.hashCode;
}

const _keep = Object();

/// رحلة على الخريطة: نقطة صعود (انطلاق أو وقفة) مع سعر ووقت الجزء.
class MapTrip {
  final String tripId;
  final String board, to; // أسماء المدن بالعربي
  final LatLng point;
  final bool exact; // نقطة تجمع حددها السائق
  final DateTime departure; // UTC
  final DateTime arrival;
  final int price, seats;
  final RideKind kind;
  final bool instant;
  final String driver;
  final double rating;
  final double? distanceKm;
  const MapTrip({
    required this.tripId,
    required this.board,
    required this.to,
    required this.point,
    this.exact = false,
    required this.departure,
    required this.arrival,
    required this.price,
    required this.seats,
    this.kind = RideKind.men,
    this.instant = false,
    required this.driver,
    this.rating = 0,
    this.distanceKm,
  });
  String get id => '$tripId@$board';
}

enum PlaceKind { city, garage, meetingPoint, landmark, saved, address }

/// نتيجة بحث جغرافي (مدينة، نقطة تجمع، مكان محفوظ أو عنوان من المزود).
class GeoPlace {
  final String name, label;
  final LatLng point;
  final PlaceKind kind;
  final String? city; // المدينة (بالعربي) إذا معروفة
  final double? distanceKm;
  const GeoPlace({required this.name, this.label = '', required this.point, this.kind = PlaceKind.address, this.city, this.distanceKm});

  Map<String, dynamic> toJson() => {'n': name, 'l': label, 'a': point.latitude, 'o': point.longitude, 'k': kind.name, 'c': city};
  static GeoPlace? fromJson(Map<String, dynamic> j) {
    try {
      return GeoPlace(
        name: j['n'] as String,
        label: (j['l'] as String?) ?? '',
        point: LatLng((j['a'] as num).toDouble(), (j['o'] as num).toDouble()),
        kind: PlaceKind.values.firstWhere((k) => k.name == j['k'], orElse: () => PlaceKind.address),
        city: j['c'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// مكان محفوظ للمستخدم.
class SavedPlace {
  final String id, label, kind; // kind: home / work / other
  final LatLng point;
  final String? address;
  const SavedPlace({required this.id, required this.label, this.kind = 'other', required this.point, this.address});
  GeoPlace get asPlace => GeoPlace(name: label, label: address ?? '', point: point, kind: PlaceKind.saved);
}

/// خيار مسار (مع البدائل).
class RouteOption {
  final List<LatLng> line;
  final int meters, seconds;
  final String summary;
  /// تقريبي = محسوب محلياً لأن المزود ما رد (بلا نت أو بلا مفتاح)
  final bool approximate;
  const RouteOption({required this.line, required this.meters, required this.seconds, this.summary = '', this.approximate = false});
  double get km => meters / 1000;
}

/// نشاط مدينة (عدد الرحلات الطالعة منها بالأيام الجاية).
class CityActivity {
  final String city;
  final LatLng point;
  final int departures;
  const CityActivity(this.city, this.point, this.departures);
}
