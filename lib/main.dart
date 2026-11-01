import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme.dart';
import 'screens/splash.dart';
import 'data/store.dart';
import 'core/config.dart';
import 'core/push.dart';
import 'core/log.dart';
import 'data/demo_backend.dart';
import 'data/supabase_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // معالجة مركزية للأخطاء: منسجّلها، وما منعرض شاشة حمرا للمستخدم
  FlutterError.onError = (d) {
    logEvent('flutter_error', error: d.exception, stack: d.stack);
    if (kDebugMode) FlutterError.presentError(d);
  };
  PlatformDispatcher.instance.onError = (e, s) {
    logEvent('uncaught', error: e, stack: s);
    return true;
  };
  if (kReleaseMode) {
    ErrorWidget.builder = (_) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('صار خطأ بعرض هالجزء. ارجع وجرّب مرة تانية.', textAlign: TextAlign.center, textDirection: TextDirection.rtl),
          ),
        );
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light));
  Store.onSignedIn = Push.start;
  Store.onSigningOut = Push.stop;
  // Supabase إذا في مفاتيح، غير هيك الوضع التجريبي
  try {
    await Store.i.start(AppConfig.live ? SupabaseBackend() : DemoBackend());
  } catch (e, s) {
    // بالنسخة الحقيقية ما منتحوّل للتجريبي بصمت: الشاشة الأولى بتعرض إعادة المحاولة
    logEvent('startup_failed', error: e, stack: s);
    Store.i.startupFailed = true;
  }
  runApp(const MishwarApp());
}

class MishwarApp extends StatelessWidget {
  const MishwarApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'مشوار',
        scaffoldMessengerKey: Store.i.messenger,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const SplashScreen(),
      );
}
