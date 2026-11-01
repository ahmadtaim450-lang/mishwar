import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'store.dart';

/// موقع GPS حقيقي. بيرجع null إذا الموقع مسكّر أو ما في إذن.
Future<Position?> myPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
  } catch (_) {
    return null;
  }
}

/// إعدادات التتبع وقت الرحلة. على أندرويد بيشتغل كخدمة ظاهرة بإشعار،
/// فالتتبع بيكمّل لو الشاشة انطفت أو طلعت من التطبيق.
LocationSettings trackingSettings(int distanceMeters) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceMeters,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'مشوار',
        notificationText: 'عم نشارك موقعك مع رحلتك لحتى توصل',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }
  return LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: distanceMeters);
}

/// أقرب مدينة من القائمة لموقع معيّن.
String nearestCity(double lat, double lon, Iterable<String> names) {
  String best = names.first;
  var bd = double.infinity;
  for (final n in names) {
    final g = geo[n];
    if (g == null) continue;
    final d = math.pow(g.$1 - lat, 2) + math.pow((g.$2 - lon) * math.cos(lat * math.pi / 180), 2);
    if (d < bd) {
      bd = d.toDouble();
      best = n;
    }
  }
  return best;
}

String mapsLink(double lat, double lon) => 'https://maps.google.com/?q=${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
