import 'dart:async';
import 'dart:io' show SocketException;

/// خطأ موحّد بالتطبيق: رمز ثابت + رسالة عربية للمستخدم.
class AppException implements Exception {
  final String code;
  final String message;
  const AppException(this.code, this.message);

  /// بيحوّل أي خطأ (من السيرفر أو الشبكة) لرسالة مفهومة، بلا ما يكشف تفاصيل داخلية.
  factory AppException.from(Object e) {
    if (e is AppException) return e;
    if (e is SocketException || e is TimeoutException) return const AppException('NETWORK', 'ما في اتصال بالإنترنت. جرّب كمان شوي');
    final text = e.toString();
    for (final code in messages.keys) {
      if (text.contains(code)) return AppException(code, messages[code]!);
    }
    if (text.contains('Invalid login credentials') || text.contains('Token has expired or is invalid') || text.contains('otp_expired')) {
      return const AppException('OTP_INVALID', 'الرمز غلط أو انتهت صلاحيتو');
    }
    if (text.contains('rate limit') || text.contains('over_sms_send_rate_limit')) return AppException('RATE_LIMITED', messages['RATE_LIMITED']!);
    if (text.contains('Failed host lookup') || text.contains('ClientException') || text.contains('XMLHttpRequest')) {
      return const AppException('NETWORK', 'ما في اتصال بالإنترنت. جرّب كمان شوي');
    }
    return const AppException('UNKNOWN', 'صار خطأ غير متوقع. جرّب مرة تانية');
  }

  @override
  String toString() => 'AppException($code)';

  static const messages = <String, String>{
    'NOT_AUTHENTICATED': 'لازم تسجّل دخول أول',
    'PROFILE_INCOMPLETE': 'كمّل معلومات حسابك أول (الاسم والجنس)',
    'PROFILE_NOT_FOUND': 'ما لقينا حسابك، سجّل دخول من جديد',
    'INVALID_NAME': 'اكتب اسمك الكامل (3 أحرف عالأقل)',
    'GENDER_LOCKED': 'ما فيك تغيّر الجنس بعد التسجيل، تواصل مع الدعم',
    'INVALID_INPUT': 'في معلومة ناقصة أو غلط',
    'INVALID_ROUTE': 'الطريق مو صحيح، تأكد من المدن والوقفات',
    'INVALID_DEPARTURE': 'وقت الانطلاق لازم يكون بعد نص ساعة عالأقل، وخلال شهرين',
    'INVALID_PRICE': 'السعر لازم يكون بين ألف ومليونين ليرة',
    'INVALID_SEATS': 'عدد المقاعد مو مناسب',
    'INVALID_VEHICLE': 'معلومات السيارة ناقصة، والموديل لازم يكون 2005 وطالع',
    'INVALID_INTERVIEW': 'موعد المقابلة لازم يكون بعد 12 ساعة عالأقل',
    'PLATE_TAKEN': 'رقم السيارة هاد مسجّل بحساب تاني',
    'NOT_APPROVED_DRIVER': 'بس السائقين الموثّقين بيقدروا ينشروا رحلات',
    'VEHICLE_NOT_VERIFIED': 'السيارة لسا ما انفحصت',
    'GENDER_RESTRICTED': 'هالرحلة مو متاحة إلك حسب نوعها',
    'FAMILY_ONLY': 'هالرحلة للعائلات بس، احجز كعائلة',
    'TRIP_NOT_FOUND': 'الرحلة مو موجودة أو انحذفت',
    'TRIP_NOT_BOOKABLE': 'الرحلة ما عاد فيها حجز',
    'TRIP_OVERLAP': 'عندك رحلة تانية بنفس الوقت',
    'OWN_TRIP': 'ما فيك تحجز برحلتك',
    'NOT_ENOUGH_SEATS': 'ما في مقاعد كافية، المقاعد انحجزت',
    'ALREADY_BOOKED': 'عندك حجز فعّال بهالرحلة',
    'BOOKING_NOT_FOUND': 'الحجز مو موجود',
    'ALREADY_REVIEWED': 'قيّمت هالرحلة من قبل',
    'APPLICATION_ACTIVE': 'عندك طلب سائق عم يتراجع',
    'DOCUMENTS_MISSING': 'في أوراق ناقصة بالطلب',
    'ACCOUNT_SUSPENDED': 'حسابك موقوف مؤقتاً، تواصل مع الدعم',
    'TRACKING_CLOSED': 'التتبع بيشتغل بس وقت الرحلة',
    'TOO_EARLY': 'لسا بكير على هالخطوة',
    'INVALID_STATE': 'هالعملية ما عاد ممكنة',
    'FORBIDDEN': 'ما عندك صلاحية لهالعملية',
    'NOT_FOUND': 'مو موجود',
    'RATE_LIMITED': 'عملت محاولات كتير، استنى شوي وجرّب',
    'WALLET_LOW': 'رصيدك ما بيكفي لعمولة هالحجز. اشحن رصيدك وارجع اقبل الطلب',
    'INVALID_AMOUNT': 'المبلغ مو ضمن الحد المسموح',
    'TOPUP_PENDING_LIMIT': 'عندك طلبات شحن لسا عم تتراجع، استنى لحد ما يخلصوا',
    'DUPLICATE_REFERENCE': 'رقم العملية هاد مستعمل من قبل',
    'DRIVER_NOT_FOUND': 'ما في سائق موثّق بهالرقم',
    'AGENT_LIMIT': 'وصلت للحد اليومي للشحن',
    'POINT_TOO_FAR': 'النقطة بعيدة كتير عن المدينة',
    'OUTSIDE_SYRIA': 'المكان لازم يكون جوّا سوريا',
    'LIMIT_REACHED': 'وصلت للحد الأقصى، احذف شي قديم أول',
    'MAP_SERVICE_DOWN': 'خدمة الخرائط مو متاحة هلأ، جرّب بعد شوي',
    'NO_ROUTE': 'ما في طريق بين النقطتين',
    'UPLOAD_FAILED': 'ما قدرنا نرفع الصورة، جرّب مرة تانية',
    'OTP_INVALID': 'الرمز غلط أو انتهت صلاحيتو',
    'INVALID_PHONE': 'رقم الموبايل مو صحيح',
    'NETWORK': 'ما في اتصال بالإنترنت. جرّب كمان شوي',
  };
}
