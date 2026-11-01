import 'dart:typed_data';
import 'mock.dart';
import 'store.dart';

/// طبقة الخدمات: الواجهات ما بتعرف إذا البيانات من Supabase أو من الوضع التجريبي.
abstract class Backend {
  bool get isLive;
  bool get signedIn;

  /// بتطلق حدث كل ما تغيّر شي بالسيرفر (حجز، إشعار...) لحتى نحدّث.
  Stream<void> get changes;

  Future<void> init();

  // الدخول برقم الموبايل
  Future<void> sendOtp(String phone);
  Future<void> verifyOtp(String phone, String code);
  Future<void> signOut();
  Future<UserProfile?> loadProfile();
  Future<void> completeProfile(String fullName, bool female, {String? music});
  Future<void> updateProfile({String? name, String? music, Map<String, String>? prefs});
  Future<void> requestDeletion();
  Future<void> uploadAvatar(Uint8List jpeg);
  Future<DriverPublic> driverPublic(Person p);

  // البحث
  Future<List<Trip>> searchTrips(String from, String to, int day, int seats);
  Future<Map<String, (int, int)>> destinationStats(String from, int day);

  // الحجز
  Future<Booking> requestBooking(Trip t, int seats, {bool family = false, String? message});
  Future<List<Booking>> myBookings();
  Future<Booking> bookingDetails(Booking b);
  Future<void> cancelBooking(Booking b, String reason);
  Future<void> submitReview(Booking b, int stars, List<String> tags, String? comment);
  Future<void> report(String targetId, String? tripId, String reason, String? details);

  // السائق
  Future<List<MyRide>> myRides();
  Future<Trip> publishTrip(Trip draft, {List<String> prefs = const [], String? note});
  Future<void> respond(RideReq q, bool accept);
  Future<void> cancelTrip(Trip t);
  Future<void> startTrip(Trip t);
  Future<void> completeTrip(Trip t);
  Future<void> submitApplication(DriverApp a, void Function(double progress) onProgress);
  Future<(DStatus, DriverApp?)> application();
  Future<void> cancelApplication();

  // التتبع والرسائل والإشعارات
  Future<void> updateLocation(Trip t, double lat, double lon, double? accuracy, double? heading);
  Future<String> createShareLink(Booking b);
  Stream<List<ChatMessage>> messages(String bookingId);
  Future<void> sendMessage(String bookingId, String body);
  Future<List<AppNotification>> notifications();
  Future<void> markNotificationsRead();
  Future<void> registerDevice(String token, String platform);
  Future<void> unregisterDevice(String token);
}
