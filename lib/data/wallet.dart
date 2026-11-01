// محفظة السائق: الرصيد، العمولة، الحركات، وطلبات الشحن.
enum TopupMethod { shamCash, syriatelCash, mtnCash }

extension TopupMethodX on TopupMethod {
  String get db => switch (this) { TopupMethod.shamCash => 'sham_cash', TopupMethod.syriatelCash => 'syriatel_cash', TopupMethod.mtnCash => 'mtn_cash' };
  String get label => switch (this) { TopupMethod.shamCash => 'شام كاش', TopupMethod.syriatelCash => 'سيريتل كاش', TopupMethod.mtnCash => 'MTN كاش' };
  static TopupMethod? parse(String? s) => TopupMethod.values.where((m) => m.db == s).firstOrNull;
}

String methodLabel(String? db) => switch (db) {
      'sham_cash' => 'شام كاش',
      'syriatel_cash' => 'سيريتل كاش',
      'mtn_cash' => 'MTN كاش',
      'agent' => 'وكيل معتمد',
      'office' => 'مكتب مشوار',
      _ => db ?? '',
    };

class WalletEntry {
  final String id, kind; // topup, commission, refund, adjustment, earning, payout
  final int amount, balance;
  final String note;
  final DateTime at;
  const WalletEntry({required this.id, required this.kind, required this.amount, required this.balance, this.note = '', required this.at});
  String get title => switch (kind) {
        'topup' => 'شحن رصيد',
        'commission' => 'عمولة حجز',
        'refund' => 'استرجاع عمولة',
        'earning' => 'أرباح رحلات مدفوعة أونلاين',
        'payout' => 'تسوية',
        _ => 'تعديل من الإدارة',
      };
}

class TopupRequest {
  final String id, method, reference, status; // pending, approved, rejected
  final int amount;
  final String? note;
  final DateTime at;
  const TopupRequest({required this.id, required this.amount, required this.method, required this.reference, required this.status, this.note, required this.at});
}

class Wallet {
  final int balance, commissionPct, commissionMin, creditLimit, topupMin, topupMax, monthCommission;
  final bool canAccept;
  final Map<String, String> accounts; // أرقام محافظ مشوار للتحويل
  final List<WalletEntry> entries;
  final List<TopupRequest> requests;
  const Wallet({
    required this.balance,
    this.commissionPct = 8,
    this.commissionMin = 2000,
    this.creditLimit = 0,
    this.topupMin = 10000,
    this.topupMax = 5000000,
    this.monthCommission = 0,
    required this.canAccept,
    this.accounts = const {},
    this.entries = const [],
    this.requests = const [],
  });

  /// العمولة المتوقعة لحجز (نفس حساب السيرفر).
  int commissionFor(int pricePerSeat, int seats) {
    final v = (pricePerSeat * seats * commissionPct / 100).round();
    return v < commissionMin ? commissionMin : v;
  }

  /// كم حجز تقريباً بيغطي الرصيد الحالي لسعر مقعد معيّن.
  int bookingsLeft(int pricePerSeat) {
    final fee = commissionFor(pricePerSeat, 1);
    final room = balance + creditLimit;
    return room <= 0 ? 0 : room ~/ fee;
  }

  static Wallet fromJson(Map j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return Wallet(
      balance: n('balance'),
      commissionPct: n('commission_pct'),
      commissionMin: n('commission_min'),
      creditLimit: n('credit_limit'),
      topupMin: n('topup_min'),
      topupMax: n('topup_max'),
      monthCommission: n('month_commission'),
      canAccept: j['can_accept'] == true,
      accounts: {for (final e in ((j['accounts'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
      entries: [
        for (final e in ((j['entries'] as List?) ?? const []).cast<Map>())
          WalletEntry(
            id: '${e['id']}',
            kind: '${e['kind']}',
            amount: (e['amount'] as num).toInt(),
            balance: (e['balance'] as num).toInt(),
            note: (e['note'] as String?) ?? '',
            at: DateTime.parse(e['at'] as String).toLocal(),
          ),
      ],
      requests: [
        for (final r in ((j['requests'] as List?) ?? const []).cast<Map>())
          TopupRequest(
            id: '${r['id']}',
            amount: (r['amount'] as num).toInt(),
            method: '${r['method']}',
            reference: '${r['reference']}',
            status: '${r['status']}',
            note: r['note'] as String?,
            at: DateTime.parse(r['at'] as String).toLocal(),
          ),
      ],
    );
  }
}
