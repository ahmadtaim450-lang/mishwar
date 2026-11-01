import 'dart:developer' as dev;

/// سجل الأحداث المهمة والأخطاء. ما منسجّل أي معلومات شخصية (أرقام، مواقع، رسائل).
/// لاحقاً بينربط بخدمة مراقبة (مثلاً Sentry) من هون بس.
void logEvent(String name, {Object? error, StackTrace? stack}) {
  dev.log(name, name: 'mishwar', error: error, stackTrace: stack);
}
