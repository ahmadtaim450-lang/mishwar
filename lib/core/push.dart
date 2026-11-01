import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../data/store.dart';

/// إشعارات الموبايل (FCM). بتشتغل بس إذا انمرقت مفاتيح Firebase وقت البناء:
///   --dart-define=FIREBASE_API_KEY=... FIREBASE_APP_ID=... FIREBASE_SENDER_ID=... FIREBASE_PROJECT_ID=...
/// المفاتيح هي إعدادات تطبيق عامة (مو أسرار). السر الحقيقي (حساب الخدمة) بالسيرفر بس.
class Push {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _sender = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static bool _started = false;
  static String? _token;

  /// عند الخروج: هالجهاز ما عاد لازم يوصلو إشعارات هالحساب.
  static Future<void> stop() async {
    final t = _token;
    _token = null;
    _started = false;
    if (t != null) await Store.i.unregisterDevice(t);
  }

  static bool get configured =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android && _apiKey.isNotEmpty && _appId.isNotEmpty && _sender.isNotEmpty && _project.isNotEmpty;

  /// بيسجّل الجهاز بعد الدخول. أي فشل هون ما بيوقف التطبيق.
  static Future<void> start() async {
    if (!configured || _started || !Store.i.live) return;
    _started = true;
    try {
      await Firebase.initializeApp(options: const FirebaseOptions(apiKey: _apiKey, appId: _appId, messagingSenderId: _sender, projectId: _project));
      final m = FirebaseMessaging.instance;
      await m.requestPermission();
      final token = await m.getToken();
      _token = token;
      if (token != null) await Store.i.registerDevice(token, 'android');
      m.onTokenRefresh.listen((t) {
        _token = t;
        Store.i.registerDevice(t, 'android');
      });
      // التطبيق مفتوح: منحدّث البيانات ومنعرض الإشعار جوا التطبيق
      FirebaseMessaging.onMessage.listen((_) => Store.i.refreshAll());
      FirebaseMessaging.onMessageOpenedApp.listen((_) => Store.i.refreshAll());
    } catch (_) {
      _started = false;
    }
  }
}
