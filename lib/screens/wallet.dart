// محفظة السائق: الرصيد، العمولة، الشحن، وسجل الحركات.
// الراكب بيدفع للسائق كاش، والعمولة بتنخصم من هالرصيد لحظة تأكيد الحجز.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../data/store.dart';
import '../data/wallet.dart';
import '../widgets/common.dart';

String _bookings(int n) => n == 1 ? 'حجز واحد' : n == 2 ? 'حجزين' : n <= 10 ? '$n حجوزات' : '$n حجز';

String signedMoney(int v) => '${v > 0 ? '+' : v < 0 ? '−' : ''}${money(v.abs())}';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => (_loading = true, _error = null));
    try {
      await Store.i.refreshWallet();
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _topup() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => TopupSheet(Store.i.wallet!),
    );
    if (ok == true && mounted) {
      toast(context, 'وصل طلبك، رح ينضاف الرصيد بعد ما نتأكد من التحويل');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) {
          final w = Store.i.wallet;
          return Scaffold(
            appBar: TopBar(title: 'محفظتي', actions: [SquareBtn(Icons.refresh_rounded, tooltip: 'حدّث', onTap: _load)]),
            body: w == null
                ? (_error != null ? ErrorView(_error!, onRetry: _load) : const Center(child: CircularProgressIndicator(color: C.primary)))
                : RefreshIndicator(
                    onRefresh: _load,
                    color: C.primary,
                    child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
                      if (!Store.i.live) const DemoBanner(),
                      _BalanceCard(w, onTopup: _topup),
                      const SizedBox(height: 14),
                      _HowItWorks(w),
                      if (w.requests.any((r) => r.status == 'pending')) ...[
                        const SizedBox(height: 18),
                        const Text('طلبات شحن عم تتراجع', style: T.h3),
                        const SizedBox(height: 8),
                        for (final r in w.requests.where((r) => r.status == 'pending')) _RequestTile(r),
                      ],
                      const SizedBox(height: 18),
                      Row(children: [
                        const Expanded(child: Text('الحركات', style: T.h3)),
                        if (_loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.primary)),
                      ]),
                      const SizedBox(height: 8),
                      if (w.entries.isEmpty && w.requests.isEmpty)
                        const Padding(padding: EdgeInsets.all(20), child: Text('لسا ما في حركات. اشحن رصيدك لتبلّش تستقبل حجوزات.', style: T.body, textAlign: TextAlign.center)),
                      for (final e in w.entries) _EntryTile(e),
                      for (final r in w.requests.where((r) => r.status == 'rejected').take(5)) _RequestTile(r),
                    ]),
                  ),
          );
        },
      );
}

class _BalanceCard extends StatelessWidget {
  final Wallet w;
  final VoidCallback onTopup;
  const _BalanceCard(this.w, {required this.onTopup});
  @override
  Widget build(BuildContext context) {
    final low = !w.canAccept;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: low ? const [Color(0xFF9A2A17), Color(0xFFC8321C)] : const [C.dark, Color(0xFF0B6A7A)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet_rounded, color: C.yellow),
          const SizedBox(width: 8),
          const Expanded(child: Text('رصيدك', style: TextStyle(fontFamily: kFont, color: Colors.white70, fontSize: 15))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
            child: Text(low ? 'ما بتستقبل حجوزات' : 'بتستقبل حجوزات', style: const TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 12.5)),
          ),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(w.balance < 0 ? '−${money(-w.balance)}' : money(w.balance), style: const TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 36)),
        ),
        const SizedBox(height: 4),
        Text(
          low ? 'اشحن رصيدك لحتى ترجع توصلك حجوزات، والحجز الفوري بيرجع يشتغل.' : 'بيكفي لحوالي ${_bookings(w.bookingsLeft(50000))} (لمقعد سعرو 50 ألف) · عمولة الشهر ${money(w.monthCommission)}',
          style: const TextStyle(fontFamily: kFont, color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 14),
        Btn('اشحن رصيد', kind: BtnKind.white, icon: Icons.add_card_rounded, onTap: onTopup),
      ]),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  final Wallet w;
  const _HowItWorks(this.w);
  @override
  Widget build(BuildContext context) => CardBox(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('كيف بتشتغل؟', style: T.label),
          const SizedBox(height: 8),
          _line(Icons.payments_outlined, 'الراكب بيدفعلك أجرة المقعد كاش، كاملة.'),
          _line(Icons.percent_rounded, 'لما تأكّد حجز، بتنخصم عمولة مشوار ${w.commissionPct}% من رصيدك (أقل شي ${money(w.commissionMin)}).'),
          _line(Icons.undo_rounded, 'إذا الحجز انلغى قبل الانطلاق، العمولة بترجعلك.'),
          _line(Icons.block_rounded, 'إذا الرصيد ما بيكفي، ما بتقدر تقبل حجوزات لحد ما تشحن.'),
        ]),
      );

  Widget _line(IconData i, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 18, color: C.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(fontFamily: kFont, fontSize: 13.5, color: C.muted2, height: 1.5))),
        ]),
      );
}

class _EntryTile extends StatelessWidget {
  final WalletEntry e;
  const _EntryTile(this.e);
  @override
  Widget build(BuildContext context) {
    final plus = e.amount > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: plus ? const Color(0xFFDDF5E7) : C.bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(
              switch (e.kind) { 'topup' => Icons.add_rounded, 'refund' => Icons.undo_rounded, 'commission' => Icons.receipt_long_rounded, 'payout' => Icons.north_east_rounded, _ => Icons.tune_rounded },
              color: plus ? const Color(0xFF146B3C) : C.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title, style: T.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text([if (e.note.isNotEmpty) e.note, timeAgo(e.at)].join(' · '), style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(signedMoney(e.amount), style: TextStyle(fontFamily: kFont, fontSize: 15, color: plus ? const Color(0xFF146B3C) : C.dark)),
            Text('الرصيد ${money(e.balance.abs())}', style: T.small),
          ]),
        ]),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final TopupRequest r;
  const _RequestTile(this.r);
  @override
  Widget build(BuildContext context) {
    final pending = r.status == 'pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        color: pending ? C.warnBg : C.dangerBg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(pending ? Icons.hourglass_top_rounded : Icons.cancel_outlined, color: pending ? C.warn : C.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${methodLabel(r.method)} · ${money(r.amount)}', style: T.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(pending ? 'رقم العملية ${r.reference} · عم نتأكد منو' : 'ما انقبل${r.note == null ? '' : ': ${r.note}'}', style: T.small, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// شحن الرصيد: تحويل لمحفظة مشوار برقم عملية، أو عند وكيل معتمد بالكاش.
class TopupSheet extends StatefulWidget {
  final Wallet w;
  const TopupSheet(this.w, {super.key});
  @override
  State<TopupSheet> createState() => _TopupSheetState();
}

class _TopupSheetState extends State<TopupSheet> {
  TopupMethod _m = TopupMethod.shamCash;
  int _amount = 100000;
  final _ref = TextEditingController();
  final _custom = TextEditingController();
  static const _amounts = [50000, 100000, 250000, 500000];
  bool _agent = false;

  @override
  void dispose() {
    _ref.dispose();
    _custom.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(_custom.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? _amount;

  @override
  Widget build(BuildContext context) {
    final account = widget.w.accounts[_m.db];
    final valid = _value >= widget.w.topupMin && _value <= widget.w.topupMax;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('اشحن رصيدك', style: T.h2),
            const SizedBox(height: 12),
            ChipGroup(options: const ['تحويل من محفظة', 'كاش عند وكيل'], selected: {_agent ? 1 : 0}, onTap: (i) => setState(() => _agent = i == 1)),
            const SizedBox(height: 14),
            if (_agent) ...[
              const InfoNote('روح لأي وكيل معتمد من مشوار (مكتب بالكراج أو محل)، وأعطيه رقم موبايلك والمبلغ كاش. الرصيد بينضاف فوراً ورح يوصلك إشعار.'),
              const SizedBox(height: 12),
              Btn('تمام', onTap: () => Navigator.pop(context)),
            ] else ...[
              const Text('المبلغ', style: T.label),
              const SizedBox(height: 8),
              ChipGroup(
                options: [for (final a in _amounts) money(a)],
                selected: {if (_custom.text.isEmpty) _amounts.indexOf(_amount)},
                onTap: (i) => setState(() {
                  _amount = _amounts[i];
                  _custom.clear();
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _custom,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                onChanged: (_) => setState(() {}),
                style: T.label,
                decoration: _dec('مبلغ تاني (ل.س)'),
              ),
              if (!valid) Padding(padding: const EdgeInsets.only(top: 4), child: Text('المبلغ لازم يكون بين ${money(widget.w.topupMin)} و ${money(widget.w.topupMax)}', style: const TextStyle(fontFamily: kFont, color: C.danger, fontSize: 12.5))),
              const SizedBox(height: 14),
              const Text('حوّل من', style: T.label),
              const SizedBox(height: 8),
              ChipGroup(options: [for (final m in TopupMethod.values) m.label], selected: {_m.index}, onTap: (i) => setState(() => _m = TopupMethod.values[i])),
              const SizedBox(height: 12),
              CardBox(
                color: C.tint,
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, color: C.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      account == null || account.isEmpty
                          ? 'حوّل ${money(_value)} على حساب مشوار بـ${_m.label} (الرقم بيوصلك من الدعم)، وبعدين اكتب رقم العملية تحت.'
                          : 'حوّل ${money(_value)} على حساب مشوار بـ${_m.label}: $account، وبعدين اكتب رقم العملية تحت.',
                      style: const TextStyle(fontFamily: kFont, fontSize: 13.5, color: C.dark, height: 1.5),
                    ),
                  ),
                  if (account != null && account.isNotEmpty)
                    IconButton(
                      tooltip: 'انسخ الرقم',
                      icon: const Icon(Icons.copy_rounded, color: C.primary),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: account));
                        toast(context, 'انسخ الرقم');
                      },
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              TextField(controller: _ref, maxLength: 80, onChanged: (_) => setState(() {}), style: T.label, decoration: _dec('رقم العملية (من رسالة التحويل)')),
              const SizedBox(height: 4),
              AsyncBtn('أرسل طلب الشحن', icon: Icons.send_rounded, onTap: !valid || _ref.text.trim().length < 3
                  ? null
                  : () async {
                      await Store.i.requestTopup(_value, _m, _ref.text);
                      if (context.mounted) Navigator.pop(context, true);
                    }),
            ],
          ]),
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: T.small,
        counterText: '',
        filled: true,
        fillColor: C.bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );
}

/// بطاقة صغيرة بتاب السائق: الرصيد وتنبيه إذا خلص.
class WalletBanner extends StatefulWidget {
  const WalletBanner({super.key});
  @override
  State<WalletBanner> createState() => _WalletBannerState();
}

class _WalletBannerState extends State<WalletBanner> {
  @override
  void initState() {
    super.initState();
    if (Store.i.wallet == null) Store.i.refreshWallet().then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) {
          final w = Store.i.wallet;
          final low = w != null && !w.canAccept;
          return CardBox(
            color: low ? C.dangerBg : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onTap: () => go(context, const WalletScreen()),
            child: Row(children: [
              Icon(Icons.account_balance_wallet_rounded, color: low ? C.danger : C.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w == null ? 'محفظتي' : 'رصيدك ${w.balance < 0 ? '−' : ''}${money(w.balance.abs())}', style: T.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(low ? 'الرصيد ما بيكفي، اشحن لتقبل حجوزات' : 'العمولة بتنخصم من هون لما تقبل حجز', style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              Text(low ? 'اشحن' : 'التفاصيل', style: TextStyle(fontFamily: kFont, color: low ? C.danger : C.primary, fontSize: 13.5)),
            ]),
          );
        },
      );
}

/// لما السائق يحاول يقبل برصيد ما بيكفي.
Future<void> showWalletLow(BuildContext context) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('رصيدك ما بيكفي', style: TextStyle(fontFamily: kFont)),
        content: Text(AppException.messages['WALLET_LOW']!, style: const TextStyle(fontFamily: kFont)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('بعدين', style: TextStyle(fontFamily: kFont))),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              go(context, const WalletScreen());
            },
            child: const Text('اشحن هلق', style: TextStyle(fontFamily: kFont, color: C.primary)),
          ),
        ],
      ),
    );
