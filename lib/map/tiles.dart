// طبقة الخريطة: مزود الصور (Tiles) قابل للتغيير بالإعدادات، وضع فاتح/داكن،
// وكاش على الجهاز لحتى المناطق اللي انشافت تضل ظاهرة بلا نت.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

/// إعدادات مزود الخريطة (بتنمرق وقت البناء):
///   --dart-define=MAP_TILES_LIGHT=https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=KEY
///   --dart-define=MAP_TILES_DARK=https://api.maptiler.com/maps/streets-v2-dark/256/{z}/{x}/{y}.png?key=KEY
///   --dart-define=MAP_ATTRIBUTION=© MapTiler © OpenStreetMap contributors
/// مفتاح الخرائط من نوع "عام" (مقيّد على اسم التطبيق/الدومين من لوحة المزود)، مو سر.
/// بلا إعدادات: صور OpenStreetMap العامة — للتجربة بس، سياستن ما بتسمح بحمل إنتاجي.
class MapTiles {
  static const _light = String.fromEnvironment('MAP_TILES_LIGHT');
  static const _dark = String.fromEnvironment('MAP_TILES_DARK');
  static const _attribution = String.fromEnvironment('MAP_ATTRIBUTION');
  static const osm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// تنزيل منطقة للاستعمال بلا نت: بس إذا شروط المزود بتسمح (OSM العام ما بيسمح).
  static const allowOffline = bool.fromEnvironment('MAP_ALLOW_OFFLINE');

  static bool get configured => _light.isNotEmpty;
  static String url(bool dark) => dark && _dark.isNotEmpty ? _dark : (_light.isNotEmpty ? _light : osm);

  /// إذا ما في نسخة داكنة من المزود، منقلب ألوان الفاتحة.
  static bool needsDarkFilter(bool dark) => dark && _dark.isEmpty;
  static String get attribution => _attribution.isNotEmpty ? _attribution : '© OpenStreetMap contributors';
  static const maxZoom = 18.0;
}

/// طبقة الصور الجاهزة للاستعمال بأي خريطة.
TileLayer mishwarTiles({bool dark = false}) => TileLayer(
      urlTemplate: MapTiles.url(dark),
      userAgentPackageName: 'com.mishwar.mishwar',
      maxZoom: MapTiles.maxZoom,
      maxNativeZoom: 18,
      keepBuffer: 3,
      panBuffer: 1,
      tileBuilder: MapTiles.needsDarkFilter(dark) ? darkModeTileBuilder : null,
      tileProvider: TileCache.provider(),
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
    );

/// كاش الصور على الجهاز (أندرويد/آيفون). على الويب المتصفح عندو كاش لحالو.
class TileCache {
  static const maxBytes = 150 * 1024 * 1024; // 150 ميغا
  static const maxAge = Duration(days: 30);
  static Directory? _dir;
  static Future<Directory?>? _opening;
  static bool disabled = false; // الاختبارات بتسكّرو

  static TileProvider provider() => kIsWeb || disabled ? NetworkTileProvider(silenceExceptions: true) : _CachedTileProvider();

  static Future<Directory?> dir() => _opening ??= () async {
        try {
          final base = await getApplicationCacheDirectory();
          final d = Directory('${base.path}/map_tiles');
          await d.create(recursive: true);
          return _dir = d;
        } catch (_) {
          return null;
        }
      }();

  static String fileName(String url) {
    // اسم ثابت وقصير لكل رابط، بلا ما نخزّن المفتاح بالاسم
    final clean = url.replaceAll(RegExp(r'[?&](key|api_key|access_token|token)=[^&]*'), '');
    // FNV-1a مرتين ببذرتين مختلفتين (32 بت لكل وحدة)
    var a = 0x811c9dc5, b = 0x050c5d1f;
    for (final c in utf8.encode(clean)) {
      a = ((a ^ c) * 0x01000193) & 0xFFFFFFFF;
      b = ((b ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return '${a.toRadixString(16)}${b.toRadixString(16)}_${clean.length}.tile';
  }

  static final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent = 'Mishwar/1.0 (com.mishwar.mishwar)';

  /// بيجيب صورة: من الكاش إذا جديدة، وإلا من النت، وإذا النت مقطوع من الكاش القديم.
  static Future<Uint8List?> load(String url, {bool forceNetwork = false}) async {
    final d = _dir ?? await dir();
    final f = d == null ? null : File('${d.path}/${fileName(url)}');
    if (f != null && !forceNetwork && await f.exists()) {
      final age = DateTime.now().difference(await f.lastModified());
      if (age < maxAge) return f.readAsBytes();
    }
    try {
      final req = await _client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('tile ${res.statusCode}');
      }
      final bytes = await consolidateHttpClientResponseBytes(res);
      if (f != null) unawaited(f.writeAsBytes(bytes, flush: false).then((_) => _maybeTrim()).catchError((_) => _maybeTrim()));
      return bytes;
    } catch (_) {
      if (f != null && await f.exists()) return f.readAsBytes(); // قديمة بس أحسن من فاضية
      return null;
    }
  }

  static int _writes = 0;
  static Future<void> _maybeTrim() async {
    if (++_writes % 200 != 0) return;
    await trim();
  }

  /// بيمسح الأقدم لحتى الحجم يرجع تحت الحد.
  static Future<int> trim({int limit = maxBytes}) async {
    final d = _dir ?? await dir();
    if (d == null) return 0;
    final files = <(File, FileStat)>[];
    var total = 0;
    await for (final e in d.list()) {
      if (e is File) {
        final s = await e.stat();
        files.add((e, s));
        total += s.size;
      }
    }
    if (total <= limit) return total;
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (f, s) in files) {
      if (total <= limit * .8) break;
      try {
        await f.delete();
        total -= s.size;
      } catch (_) {}
    }
    return total;
  }

  static Future<int> sizeBytes() async {
    final d = _dir ?? await dir();
    if (d == null) return 0;
    var total = 0;
    await for (final e in d.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  static Future<void> clear() async {
    final d = _dir ?? await dir();
    if (d == null) return;
    await for (final e in d.list()) {
      try {
        await e.delete();
      } catch (_) {}
    }
  }
}

class _CachedTileProvider extends TileProvider {
  _CachedTileProvider();
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => _CachedTile(getTileUrl(coordinates, options));
}

class _CachedTile extends ImageProvider<_CachedTile> {
  final String url;
  const _CachedTile(this.url);

  @override
  Future<_CachedTile> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_CachedTile key, ImageDecoderCallback decode) => MultiFrameImageStreamCompleter(codec: _codec(decode), scale: 1);

  Future<ui.Codec> _codec(ImageDecoderCallback decode) async {
    final bytes = await TileCache.load(url) ?? _transparent;
    try {
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      return decode(await ui.ImmutableBuffer.fromUint8List(_transparent));
    }
  }

  @override
  bool operator ==(Object other) => other is _CachedTile && other.url == url;
  @override
  int get hashCode => url.hashCode;
}

// صورة شفافة 1×1 (لما ما في نت ولا كاش: بلا أخطاء حمرا)
final _transparent = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

/// تنزيل منطقة (مثلاً طريق رحلة) للاستعمال بلا نت. بيرجّع عدد الصور اللي انحفظت.
/// محدود بعدد صور لحتى ما يستهلك باقة النت أو يخالف شروط المزود.
Future<int> downloadRegion(LatLngBoundsLike bounds, {int minZoom = 7, int maxZoom = 12, int maxTiles = 1200, bool dark = false, void Function(double)? onProgress}) async {
  if (kIsWeb || !MapTiles.allowOffline) return 0;
  final tiles = tilesFor(bounds, minZoom, maxZoom);
  if (tiles.length > maxTiles) throw StateError('too_many_tiles');
  var done = 0;
  for (final t in tiles) {
    final url = MapTiles.url(dark).replaceAll('{z}', '${t.$1}').replaceAll('{x}', '${t.$2}').replaceAll('{y}', '${t.$3}').replaceAll('{s}', 'a');
    await TileCache.load(url);
    done++;
    onProgress?.call(done / tiles.length);
  }
  return done;
}

/// حدود بسيطة (جنوب، غرب، شمال، شرق) بلا اعتماد على نوع flutter_map.
typedef LatLngBoundsLike = ({double south, double west, double north, double east});

/// كل الصور اللي بتغطي منطقة بين تكبيرين.
List<(int, int, int)> tilesFor(LatLngBoundsLike b, int minZoom, int maxZoom) {
  int lon2x(double lon, int z) => ((lon + 180) / 360 * (1 << z)).floor().clamp(0, (1 << z) - 1);
  int lat2y(double lat, int z) {
    final r = lat * math.pi / 180;
    final n = (1 - (math.log(math.tan(r) + 1 / math.cos(r)) / math.pi)) / 2 * (1 << z);
    return n.floor().clamp(0, (1 << z) - 1);
  }

  final out = <(int, int, int)>[];
  for (var z = minZoom; z <= maxZoom; z++) {
    final x0 = lon2x(b.west, z), x1 = lon2x(b.east, z);
    final y0 = lat2y(b.north, z), y1 = lat2y(b.south, z);
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        out.add((z, x, y));
      }
    }
  }
  return out;
}
