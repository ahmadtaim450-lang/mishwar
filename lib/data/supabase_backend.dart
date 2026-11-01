import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';
import '../core/errors.dart';
import 'backend.dart';
import 'mock.dart';
import 'store.dart';

/// الربط الحقيقي مع Supabase: كل العمليات الحساسة عن طريق دوال RPC محمية بالسيرفر.
class SupabaseBackend implements Backend {
  /// العميل ممكن ينمرق جاهز (اختبارات التكامل)، غير هيك منستعمل Supabase.instance.
  final SupabaseClient? _client;
  SupabaseBackend({SupabaseClient? client}) : _client = client;
  SupabaseClient get _c => _client ?? Supabase.instance.client;
  final _changes = StreamController<void>.broadcast();
  RealtimeChannel? _channel;

  @override
  bool get isLive => true;
  @override
  bool get signedIn => _c.auth.currentSession != null;
  @override
  Stream<void> get changes => _changes.stream;
  String get _uid => _c.auth.currentUser?.id ?? (throw const AppException('NOT_AUTHENTICATED', 'لازم تسجّل دخول أول'));

  @override
  Future<void> init() async {
    if (_client != null) return;
    await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
    _c.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn || s.event == AuthChangeEvent.initialSession) _subscribe();
      if (s.event == AuthChangeEvent.signedOut) _unsubscribe();
    });
    if (signedIn) _subscribe();
  }

  /// تحديثات لحظية: إشعار جديد أو تغيّر بحالة حجز.
  void _subscribe() {
    final uid = _c.auth.currentUser?.id;
    if (uid == null || _channel != null) return;
    _channel = _c
        .channel('user-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (_) => _changes.add(null),
        )
        .subscribe();
  }

  void _unsubscribe() {
    final ch = _channel;
    _channel = null;
    if (ch != null) _c.removeChannel(ch);
  }

  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) => _c.rpc(fn, params: params).timeout(const Duration(seconds: 20));

  // ── الدخول ─────────────────────────────────────────────────────────
  @override
  Future<void> sendOtp(String phone) => _c.auth.signInWithOtp(phone: phone);

  @override
  Future<void> verifyOtp(String phone, String code) async {
    await _c.auth.verifyOTP(type: OtpType.sms, phone: phone, token: code);
    _subscribe();
  }

  @override
  Future<void> signOut() async {
    _unsubscribe();
    await _c.auth.signOut();
  }

  @override
  Future<UserProfile?> loadProfile() async {
    if (!signedIn) return null;
    final j = await _rpc('my_profile');
    if (j == null) return null;
    final m = Map<String, dynamic>.from(j as Map);
    final v = m['vehicle'] == null ? null : Map<String, dynamic>.from(m['vehicle'] as Map);
    return UserProfile(
      id: m['id'] as String,
      name: (m['full_name'] as String?) ?? '',
      female: m['gender'] == null ? null : m['gender'] == 'female',
      driverStatus: _dstatus(m['driver_status'] as String?),
      phone: m['phone'] as String?,
      car: v == null ? null : '${v['make_model']} · ${v['color']}',
      plate: v?['plate'] as String?,
      vehicleId: v?['id'] as String?,
      photo: _photo(m['avatar_path']),
      rating: _num(m['rating_avg']),
      trips: (m['trips_count'] as num?)?.toInt() ?? 0,
      role: (m['role'] as String?) ?? 'user',
      music: m['music_pref'] as String?,
      prefs: {for (final e in Map<String, dynamic>.from((m['travel_prefs'] as Map?) ?? const {}).entries) e.key: '${e.value}'},
    );
  }

  @override
  Future<void> completeProfile(String fullName, bool female, {String? music}) =>
      _rpc('complete_profile', {'p_full_name': fullName, 'p_gender': female ? 'female' : 'male', 'p_music': music});

  @override
  Future<void> updateProfile({String? name, String? music, Map<String, String>? prefs}) async {
    final patch = <String, dynamic>{
      if (name != null) 'full_name': name,
      if (music != null) 'music_pref': music,
      if (prefs != null) 'travel_prefs': prefs,
    };
    if (patch.isEmpty) return;
    await _c.from('profiles').update(patch).eq('id', _uid);
  }

  @override
  Future<void> requestDeletion() => _rpc('request_account_deletion');

  /// الصورة الشخصية: مجلد المستخدم بالـ avatars، واسم جديد كل مرة لحتى ما يعلق الكاش.
  @override
  Future<void> uploadAvatar(Uint8List jpeg) async {
    final path = '$_uid/avatar-${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await _c.storage.from('avatars').uploadBinary(path, jpeg, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
    } catch (_) {
      throw const AppException('UPLOAD_FAILED', 'ما قدرنا نرفع الصورة، جرّب مرة تانية');
    }
    final old = (await _c.from('profiles').select('avatar_path').eq('id', _uid).single())['avatar_path'] as String?;
    await _c.from('profiles').update({'avatar_path': path}).eq('id', _uid);
    if (old != null && old != path) {
      try {
        await _c.storage.from('avatars').remove([old]);
      } catch (_) {}
    }
  }

  String? _photo(dynamic path) => path == null || '$path'.isEmpty ? null : _c.storage.from('avatars').getPublicUrl('$path');

  @override
  Future<DriverPublic> driverPublic(Person p) async {
    if (p.id.isEmpty) return DriverPublic(p);
    final j = Map<String, dynamic>.from(await _rpc('driver_public', {'p_driver': p.id}) as Map);
    final hist = Map<String, dynamic>.from((j['histogram'] as Map?) ?? const {});
    return DriverPublic(
      p,
      trips: (j['trips_count'] as num?)?.toInt() ?? 0,
      reviewsCount: (j['rating_count'] as num?)?.toInt() ?? 0,
      rating: _num(j['rating_avg']),
      verified: j['verified'] == true,
      since: j['member_since'] == null ? null : DateTime.parse(j['member_since'] as String),
      histogram: {for (final e in hist.entries) int.parse(e.key): (e.value as num).toInt()},
      reviews: [
        for (final r in ((j['reviews'] as List?) ?? const []).cast<Map>())
          Review(
            (r['author'] as String?) ?? '',
            ((r['author'] as String?) ?? '؟').characters.first,
            (r['stars'] as num).toInt(),
            [...((r['tags'] as List?) ?? const []).map((e) => '$e'), if ((r['comment'] as String?)?.isNotEmpty ?? false) r['comment'] as String].join(' · '),
            timeAgo(DateTime.parse(r['created_at'] as String).toLocal()),
          ),
      ],
    );
  }

  // ── البحث ──────────────────────────────────────────────────────────
  @override
  Future<List<Trip>> searchTrips(String from, String to, int day, int seats) async {
    final rows = await _rpc('search_trips', {'p_from': _cid(from), 'p_to': _cid(to), 'p_date': _date(day), 'p_seats': seats}) as List;
    return [for (final r in rows) _trip(Map<String, dynamic>.from(r as Map))];
  }

  @override
  Future<Map<String, (int, int)>> destinationStats(String from, int day) async {
    final rows = await _rpc('destination_stats', {'p_from': _cid(from), 'p_date': _date(day)}) as List;
    return {
      for (final r in rows.cast<Map>())
        if (cityNames[r['to_city']] != null) cityNames[r['to_city']]!: ((r['trips'] as num).toInt(), (r['min_price'] as num).toInt()),
    };
  }

  // ── الحجز ──────────────────────────────────────────────────────────
  @override
  Future<Booking> requestBooking(Trip t, int seats, {bool family = false, String? message}) async {
    final r = Map<String, dynamic>.from(await _rpc('request_booking', {
      'p_trip': t.id,
      'p_seats': seats,
      'p_family': family,
      'p_message': message,
      'p_from': _cid(t.from),
      'p_to': _cid(t.to),
    }) as Map);
    return _bookingFrom(await _rpc('booking_details', {'p_booking': r['id']}));
  }

  @override
  Future<List<Booking>> myBookings() async {
    final rows = await _rpc('my_bookings') as List;
    return [for (final r in rows) _bookingFrom(r)];
  }

  @override
  Future<Booking> bookingDetails(Booking b) async => _bookingFrom(await _rpc('booking_details', {'p_booking': b.id}));

  @override
  Future<void> cancelBooking(Booking b, String reason) => _rpc('cancel_booking', {'p_booking': b.id, 'p_reason': reason});

  @override
  Future<void> submitReview(Booking b, int stars, List<String> tags, String? comment) =>
      _rpc('submit_review', {'p_booking': b.id, 'p_stars': stars, 'p_tags': tags, 'p_comment': comment});

  @override
  Future<void> report(String targetId, String? tripId, String reason, String? details) =>
      _rpc('submit_report', {'p_target': targetId, 'p_trip': tripId, 'p_reason': reason, 'p_details': details});

  // ── السائق ─────────────────────────────────────────────────────────
  @override
  Future<List<MyRide>> myRides() async {
    final rows = await _rpc('my_driver_trips') as List;
    final me = await loadProfile();
    final driver = Person(me?.name ?? '', (me?.name.isNotEmpty ?? false) ? me!.name.characters.first : 'أ', id: me?.id ?? '', photo: me?.photo, rating: me?.rating ?? 0, trips: me?.trips ?? 0);
    return [
      for (final raw in rows)
        () {
          final r = Map<String, dynamic>.from(raw as Map);
          final ride = MyRide(_trip(r, driver: driver, car: me?.car ?? '', plate: me?.plate ?? ''), status: r['status'] as String);
          for (final b in (r['bookings'] as List).cast<Map>()) {
            final name = (b['rider_name'] as String?) ?? '';
            final seg = b['from_city'] != r['from_city'] || b['to_city'] != r['to_city'];
            final segText = seg ? 'من ${cityNames[b['from_city']] ?? ''} لـ${cityNames[b['to_city']] ?? ''}' : '';
            final msg = (b['message'] as String?) ?? (b['family'] == true ? 'حجز عائلي' : '');
            ride.reqs.add(RideReq(
              Person(name, name.isEmpty ? '؟' : name.characters.first, id: b['rider_id'] as String, rating: _num(b['rider_rating'])),
              [segText, msg].where((x) => x.isNotEmpty).join(' · '),
              seats: (b['seats'] as num).toInt(),
              id: b['id'] as String,
              state: switch (b['status']) { 'pending' => 0, 'rejected' => 2, _ => 1 },
            ));
          }
          return ride;
        }(),
    ];
  }

  @override
  Future<Trip> publishTrip(Trip d, {List<String> prefs = const [], String? note}) async {
    final me = await loadProfile();
    if (me?.vehicleId == null) throw const AppException('VEHICLE_NOT_VERIFIED', 'السيارة لسا ما انفحصت');
    final dep = _departure(d.day, d.dep);
    final arr = _departure(d.day, d.arr);
    final minutes = arr.isAfter(dep) ? arr.difference(dep).inMinutes : arr.add(const Duration(days: 1)).difference(dep).inMinutes;
    final id = await _rpc('publish_trip', {
      'p_vehicle': me!.vehicleId,
      'p_from': _cid(d.from),
      'p_to': _cid(d.to),
      'p_from_spot': d.fromSpot,
      'p_to_spot': d.toSpot,
      'p_departure': dep.toIso8601String(),
      'p_duration_min': minutes,
      'p_price': d.price,
      'p_seats': d.seatsTotal,
      'p_kind': d.kind.name,
      'p_instant': d.instant,
      'p_prefs': prefs,
      'p_note': note,
      'p_stops': [for (final s in d.stops) _cid(s)],
    }) as String;
    return Trip(
      id: id, from: d.from, fromSpot: d.fromSpot, to: d.to, toSpot: d.toSpot, dep: d.dep, arr: d.arr, duration: d.duration,
      price: d.price, seatsLeft: d.seatsTotal, seatsTotal: d.seatsTotal, driver: d.driver, car: me.car ?? d.car,
      kind: d.kind, instant: d.instant, stops: d.stops, day: d.day, plate: me.plate ?? '',
    );
  }

  @override
  Future<void> respond(RideReq q, bool accept) => _rpc('respond_booking', {'p_booking': q.id, 'p_accept': accept});
  @override
  Future<void> cancelTrip(Trip t) => _rpc('cancel_trip', {'p_trip': t.id});
  @override
  Future<void> startTrip(Trip t) => _rpc('start_trip', {'p_trip': t.id});
  @override
  Future<void> completeTrip(Trip t) => _rpc('complete_trip', {'p_trip': t.id});

  @override
  Future<void> submitApplication(DriverApp a, void Function(double) onProgress) async {
    String appId;
    try {
      appId = await _rpc('submit_driver_application', {
        'p_city': _cid(a.city),
        'p_make_model': a.car.trim(),
        'p_year': int.tryParse(a.year.trim()) ?? 0,
        'p_color': a.color.trim(),
        'p_plate': a.plate.trim(),
        'p_seats': 4,
        'p_interview_at': a.interviewAt.toIso8601String(),
      }) as String;
    } catch (e) {
      // طلب انبعت قبل وفشل رفع الصور؟ منكمّل عليه بدل ما نرفض
      if (AppException.from(e).code != 'APPLICATION_ACTIVE') rethrow;
      final cur = await _rpc('my_application');
      if (cur == null || !const ['submitted', 'reviewing'].contains((cur as Map)['status'])) rethrow;
      appId = cur['id'] as String;
    }
    a.id = appId;
    final docs = a.docs.entries.toList();
    for (var i = 0; i < docs.length; i++) {
      final path = '$_uid/$appId/${docs[i].key}.jpg';
      try {
        await _c.storage.from('driver-docs').uploadBinary(path, docs[i].value, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
      } catch (_) {
        throw const AppException('UPLOAD_FAILED', 'ما قدرنا نرفع الصورة، جرّب مرة تانية');
      }
      await _rpc('add_application_document', {'p_application': appId, 'p_kind': docs[i].key, 'p_path': path});
      onProgress((i + 1) / docs.length);
    }
  }

  @override
  Future<(DStatus, DriverApp?)> application() async {
    final me = await loadProfile();
    final j = await _rpc('my_application');
    if (j == null) return (me?.driverStatus ?? DStatus.none, null);
    final m = Map<String, dynamic>.from(j as Map);
    final v = Map<String, dynamic>.from(m['vehicle'] as Map);
    final at = m['interview_at'] == null ? null : DateTime.parse(m['interview_at'] as String).toUtc().add(const Duration(hours: 3));
    final a = DriverApp()
      ..id = m['id'] as String
      ..name = me?.name ?? ''
      ..city = cityNames[m['city_id']] ?? ''
      ..car = v['make_model'] as String
      ..year = '${v['year']}'
      ..color = v['color'] as String
      ..plate = v['plate'] as String
      ..place = (m['interview_place'] as String?) ?? ''
      ..note = m['admin_note'] as String?
      ..slot = at == null ? '' : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'
      ..day = at == null ? 1 : _dayOf(at);
    return (me?.driverStatus ?? DStatus.none, a);
  }

  @override
  Future<void> cancelApplication() => _rpc('cancel_driver_application');

  // ── التتبع والرسائل والإشعارات ─────────────────────────────────────
  @override
  Future<void> updateLocation(Trip t, double lat, double lon, double? accuracy, double? heading) =>
      _rpc('update_live_location', {'p_trip': t.id, 'p_lat': lat, 'p_lon': lon, 'p_accuracy': accuracy, 'p_heading': heading});

  @override
  Future<String> createShareLink(Booking b) async {
    final token = await _rpc('create_share_link', {'p_booking': b.id, 'p_hours': 24}) as String;
    return '${AppConfig.trackBaseUrl}?t=$token';
  }

  @override
  Stream<List<ChatMessage>> messages(String bookingId) {
    final uid = _c.auth.currentUser?.id;
    return _c.from('messages').stream(primaryKey: ['id']).eq('booking_id', bookingId).order('created_at', ascending: true).map((rows) => [
          for (final r in rows) ChatMessage('${r['id']}', r['body'] as String, r['sender_id'] == uid, DateTime.parse(r['created_at'] as String).toLocal()),
        ]);
  }

  @override
  Future<void> sendMessage(String bookingId, String body) async {
    if (body.isEmpty || body.length > 1000) throw const AppException('INVALID_INPUT', 'في معلومة ناقصة أو غلط');
    await _c.from('messages').insert({'booking_id': bookingId, 'sender_id': _uid, 'body': body});
  }

  @override
  Future<List<AppNotification>> notifications() async {
    final rows = await _c.from('notifications').select('id, kind, title, body, read_at, created_at').order('created_at', ascending: false).limit(50);
    return [
      for (final r in rows)
        AppNotification('${r['id']}', r['kind'] as String, r['title'] as String, (r['body'] as String?) ?? '', DateTime.parse(r['created_at'] as String).toLocal(), read: r['read_at'] != null),
    ];
  }

  @override
  Future<void> markNotificationsRead() => _rpc('mark_notifications_read');

  @override
  Future<void> registerDevice(String token, String platform) => _rpc('register_device', {'p_token': token, 'p_platform': platform});

  @override
  Future<void> unregisterDevice(String token) => _rpc('unregister_device', {'p_token': token});

  // ── تحويل البيانات ─────────────────────────────────────────────────
  static String _cid(String name) => cityIds[name] ?? (throw const AppException('INVALID_ROUTE', 'الطريق مو صحيح، تأكد من المدن والوقفات'));
  static double _num(dynamic v) => v == null ? 0 : (v as num).toDouble();

  /// سوريا على توقيت UTC+3 طول السنة.
  static DateTime _damascusNow() => DateTime.now().toUtc().add(const Duration(hours: 3));
  static String _date(int day) {
    final d = _damascusNow().add(Duration(days: day));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static int _dayOf(DateTime damascus) {
    final n = _damascusNow();
    return DateTime.utc(damascus.year, damascus.month, damascus.day).difference(DateTime.utc(n.year, n.month, n.day)).inDays;
  }

  static DateTime _departure(int day, String hm) {
    final p = hm.split(':');
    final d = _damascusNow().add(Duration(days: day));
    return DateTime.utc(d.year, d.month, d.day, int.parse(p[0]), int.parse(p[1])).subtract(const Duration(hours: 3));
  }

  static String _hm(DateTime damascus) => '${damascus.hour.toString().padLeft(2, '0')}:${damascus.minute.toString().padLeft(2, '0')}';

  static DStatus _dstatus(String? s) => switch (s) {
        'reviewing' => DStatus.reviewing,
        'interview' => DStatus.interview,
        'approved' => DStatus.approved,
        'rejected' => DStatus.rejected,
        'suspended' => DStatus.suspended,
        _ => DStatus.none,
      };

  static RideKind _kind(String? s) => switch (s) { 'women' => RideKind.women, 'family' => RideKind.family, _ => RideKind.men };

  Trip _trip(Map<String, dynamic> r, {Person? driver, String? car, String? plate}) {
    final dep = DateTime.parse(r['departure_at'] as String).toUtc().add(const Duration(hours: 3));
    final arr = DateTime.parse(r['arrival_at'] as String).toUtc().add(const Duration(hours: 3));
    final name = (r['driver_name'] as String?) ?? driver?.name ?? '';
    return Trip(
      id: r['id'] as String,
      from: cityNames[r['from_city']] ?? r['from_city'] as String,
      fromSpot: (r['from_spot'] as String?) ?? '',
      to: cityNames[r['to_city']] ?? r['to_city'] as String,
      toSpot: (r['to_spot'] as String?) ?? '',
      dep: _hm(dep),
      arr: _hm(arr),
      duration: fmtDur(arr.difference(dep).inMinutes),
      price: (r['price_syp'] as num).toInt(),
      seatsLeft: (r['seats_available'] as num?)?.toInt() ?? 0,
      seatsTotal: (r['seats_total'] as num?)?.toInt() ?? 0,
      driver: driver ??
          Person(name, name.isEmpty ? '؟' : name.characters.first,
              id: (r['driver_id'] as String?) ?? '', photo: _photo(r['driver_avatar']), rating: _num(r['driver_rating']), trips: (r['driver_trips'] as num?)?.toInt() ?? 0),
      car: (r['car'] as String?) ?? car ?? '',
      kind: _kind(r['kind'] as String?),
      instant: r['instant'] == true,
      stops: [for (final s in ((r['stops'] as List?) ?? const [])) cityNames[s] ?? '$s'],
      day: _dayOf(dep),
      plate: plate ?? '',
      fullFrom: cityNames[r['full_from']] ?? '',
      fullTo: cityNames[r['full_to']] ?? '',
    );
  }

  Booking _bookingFrom(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    final t = Map<String, dynamic>.from(m['trip'] as Map);
    final d = Map<String, dynamic>.from(m['driver'] as Map);
    final v = Map<String, dynamic>.from(m['vehicle'] as Map);
    final dn = (d['full_name'] as String?) ?? '';
    final trip = _trip(
      {...t, 'seats_available': 0, 'seats_total': m['seats']},
      driver: Person(dn, dn.isEmpty ? '؟' : dn.characters.first, id: d['id'] as String, photo: _photo(d['avatar_path']), rating: _num(d['rating_avg'])),
      car: '${v['make_model']} · ${v['color']}',
      plate: (v['plate'] as String?) ?? '',
    );
    return Booking(
      trip,
      (m['seats'] as num).toInt(),
      id: m['id'] as String,
      family: m['family'] == true,
      status: switch (m['status']) {
        'confirmed' => BStatus.confirmed,
        'rejected' => BStatus.rejected,
        'cancelled' => BStatus.cancelled,
        'completed' => BStatus.done,
        _ => BStatus.pending,
      },
      rated: m['reviewed'] == true,
      pin: m['pin'] as String?,
      plate: v['plate'] as String?,
      driverPhone: d['phone'] as String?,
    );
  }
}
