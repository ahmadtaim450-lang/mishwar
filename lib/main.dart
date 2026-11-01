import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme.dart';
import 'screens/splash.dart';
import 'data/store.dart';
import 'core/config.dart';
import 'core/push.dart';
import 'data/demo_backend.dart';
import 'data/supabase_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light));
  Store.onSignedIn = Push.start;
  // Supabase إذا في مفاتيح، غير هيك الوضع التجريبي
  try {
    await Store.i.start(AppConfig.live ? SupabaseBackend() : DemoBackend());
  } catch (_) {
    await Store.i.start(DemoBackend());
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
