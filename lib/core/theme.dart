import 'package:flutter/material.dart';

class C {
  static const primary = Color(0xFF0AAFF5);
  static const primaryLight = Color(0xFF3DC0F7);
  static const dark = Color(0xFF064854);
  static const bg = Color(0xFFF3F5F5);
  static const border = Color(0xFFDDE3E3);
  static const line = Color(0xFFEEF1F1);
  static const muted = Color(0xFF5E7676);
  static const muted2 = Color(0xFF4A6363);
  static const tint = Color(0xFFE3F5FE);
  static const yellow = Color(0xFFFFD25E);
  static const star = Color(0xFFF5A623);
  static const danger = Color(0xFF9A2A17);
  static const dangerBg = Color(0xFFFDE6E2);
  static const warnBg = Color(0xFFFFF4D6);
  static const warn = Color(0xFF7A4F00);
  static const sos = Color(0xFFC8321C);
}

const kFont = 'Lalezar';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: kFont,
    scaffoldBackgroundColor: C.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: C.primary, primary: C.primary, secondary: C.dark, surface: Colors.white),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.dark, displayColor: C.dark, fontFamily: kFont),
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(allowEnterRouteSnapshotting: false),
    }),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: C.border, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: C.border, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: C.primary, width: 2)),
      hintStyle: const TextStyle(color: C.muted, fontFamily: kFont),
    ),
  );
}

class T {
  static const h1 = TextStyle(fontSize: 34, height: 1.3, color: C.dark, fontFamily: kFont);
  static const h2 = TextStyle(fontSize: 22, height: 1.3, color: C.dark, fontFamily: kFont);
  static const h3 = TextStyle(fontSize: 18, color: C.dark, fontFamily: kFont);
  static const body = TextStyle(fontSize: 15, height: 1.7, color: C.muted2, fontFamily: kFont);
  static const label = TextStyle(fontSize: 15, color: C.dark, fontFamily: kFont);
  static const small = TextStyle(fontSize: 12.5, color: C.muted, fontFamily: kFont);
}
