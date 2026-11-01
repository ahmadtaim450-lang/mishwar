// تحميل حسب حدود الخريطة الظاهرة (Viewport-Based Loading):
//  · انتظار قصير بعد ما يوقف التحريك (debounce) بدل طلب مع كل حركة
//  · حدود موسّعة ومقرّبة لشبكة: التحريك البسيط ما بيطلب شي جديد
//  · كاش قصير لآخر المناطق والفلاتر
//  · الرد القديم بينرمى إذا إجا بعد طلب أحدث
import 'dart:async';
import 'models.dart';

class ViewportResult<T> {
  final List<T> items;
  final GeoBounds area; // المنطقة اللي انجابت (أكبر من الظاهرة)
  final bool fromCache;
  const ViewportResult(this.items, this.area, {this.fromCache = false});
}

class ViewportLoader<T> {
  final Future<List<T>> Function(GeoBounds area, MapFilter filter) fetch;
  final Duration debounce;
  final Duration ttl;
  final int maxEntries;
  final DateTime Function() now;
  ViewportLoader(this.fetch, {this.debounce = const Duration(milliseconds: 350), this.ttl = const Duration(minutes: 2), this.maxEntries = 12, DateTime Function()? now})
      : now = now ?? DateTime.now;

  final _cache = <String, (DateTime, GeoBounds, List<T>)>{};
  Timer? _timer;
  int _seq = 0;
  GeoBounds? _lastArea;
  MapFilter? _lastFilter;
  int requests = 0; // عدد الطلبات الفعلية (للاختبارات والمراقبة)

  /// المنطقة اللي لازم تنجاب لحدود ظاهرة معيّنة.
  static GeoBounds areaFor(GeoBounds view) {
    final span = (view.north - view.south).abs();
    final step = span > 4 ? 1.0 : span > 1 ? .25 : span > .25 ? .05 : .01;
    return view.expand(.25).snap(step);
  }

  /// بيطلب بعد ما يهدا التحريك. [onResult] بينادى بس لآخر طلب.
  void request(GeoBounds view, MapFilter filter, void Function(ViewportResult<T>) onResult, {void Function(Object error)? onError, void Function()? onLoading}) {
    // المنطقة الظاهرة لسا جوّا آخر منطقة انجابت بنفس الفلاتر؟ ما في داعي
    if (_lastArea != null && _lastFilter == filter && _lastArea!.containsBounds(view)) return;
    _timer?.cancel();
    final seq = ++_seq;
    _timer = Timer(debounce, () => _run(seq, view, filter, onResult, onError, onLoading));
  }

  /// طلب فوري (بلا انتظار)، مثلاً بعد تغيير فلتر أو زر "إعادة المحاولة".
  Future<void> load(GeoBounds view, MapFilter filter, void Function(ViewportResult<T>) onResult, {void Function(Object error)? onError, void Function()? onLoading}) {
    _timer?.cancel();
    return _run(++_seq, view, filter, onResult, onError, onLoading);
  }

  Future<void> _run(int seq, GeoBounds view, MapFilter filter, void Function(ViewportResult<T>) onResult, void Function(Object)? onError, void Function()? onLoading) async {
    final area = areaFor(view);
    final key = '${area.key}#${filter.key}';
    final hit = _cache[key];
    if (hit != null && now().difference(hit.$1) < ttl) {
      _lastArea = area;
      _lastFilter = filter;
      if (seq == _seq) onResult(ViewportResult(hit.$3, area, fromCache: true));
      return;
    }
    onLoading?.call();
    try {
      requests++;
      final items = await fetch(area, filter);
      _cache[key] = (now(), area, items);
      while (_cache.length > maxEntries) {
        _cache.remove(_cache.keys.first);
      }
      if (seq != _seq) return; // في طلب أحدث
      _lastArea = area;
      _lastFilter = filter;
      onResult(ViewportResult(items, area));
    } catch (e) {
      if (seq == _seq) onError?.call(e);
    }
  }

  /// بعد تغيير البيانات (حجز، نشر...) منمسح الكاش.
  void invalidate() {
    _cache.clear();
    _lastArea = null;
  }

  void dispose() => _timer?.cancel();
}
