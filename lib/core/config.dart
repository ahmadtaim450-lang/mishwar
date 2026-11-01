/// إعدادات التشغيل. القيم بتنمرق وقت البناء:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// مفتاح anon عام بطبيعته (الحماية من RLS)، وما في أي سر جوا التطبيق.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// صفحة متابعة الأهل (بتنفتح بالمتصفح بلا تطبيق).
  static const trackBaseUrl = String.fromEnvironment('TRACK_BASE_URL', defaultValue: 'https://ahmadtaim450-lang.github.io/mishwar/track/');

  /// رقم الدعم للطوارئ والمساعدة.
  static const supportPhone = String.fromEnvironment('SUPPORT_PHONE', defaultValue: '');

  /// إذا ما في مفاتيح، التطبيق بيشتغل بوضع تجريبي محلي واضح للمستخدم.
  static bool get live => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
