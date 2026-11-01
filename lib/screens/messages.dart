import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../data/store.dart';
import '../widgets/common.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) {
          // محادثة لكل حجز: مع السائق (كراكب) أو مع الراكب (كسائق)
          final threads = <(Person, String, String)>[
            for (final b in Store.i.bookings.where((b) => b.status != BStatus.cancelled && b.status != BStatus.rejected)) (b.t.driver, b.id, '${b.t.from} ← ${b.t.to} · ${dayLabel(b.t.day)}'),
            for (final r in Store.i.rides)
              for (final q in r.reqs.where((q) => q.state != 2)) (q.p, q.id, 'راكب برحلتك ${r.t.from} ← ${r.t.to}'),
          ];
          return SafeArea(
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Row(children: [
                const Expanded(child: Text('الرسائل', style: T.h1)),
                SquareBtn(Icons.notifications_none_rounded, tooltip: 'الإشعارات', onTap: () => go(context, const NotificationsScreen())),
              ]),
              const SizedBox(height: 12),
              if (threads.isEmpty)
                const EmptyState(image: 'empty_search', title: 'ما في محادثات', body: 'بس تحجز رحلة أو يوصلك طلب حجز، فيك تراسل الطرف التاني من هون.')
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                  child: Column(children: [
                    for (var i = 0; i < threads.length; i++)
                      Enter(
                        delay: i * 60,
                        child: InkWell(
                          onTap: () => go(context, ChatScreen(threads[i].$1, threads[i].$2)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(border: i < threads.length - 1 ? const Border(bottom: BorderSide(color: C.line, width: 1.5)) : null),
                            child: Row(children: [
                              Avatar(threads[i].$1, size: 52),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(threads[i].$1.name, style: T.label),
                                  Text(threads[i].$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                                ]),
                              ),
                              const Icon(Icons.chevron_left_rounded, color: C.muted),
                            ]),
                          ),
                        ),
                      ),
                  ]),
                ),
            ]),
          );
        },
      );
}

class ChatScreen extends StatefulWidget {
  final Person p;
  final String bookingId;
  const ChatScreen(this.p, this.bookingId);
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  late final Stream<List<ChatMessage>> _stream = Store.i.messages(widget.bookingId);
  bool _sending = false;

  Future<void> _send(String text) async {
    final body = text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await attempt(context, () => Store.i.sendMessage(widget.bookingId, body));
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) _ctl.clear();
    _toEnd();
  }

  void _toEnd() => Future.delayed(const Duration(milliseconds: 80), () {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      });

  String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(76),
          child: Container(
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(children: [
                  SquareBtn(Icons.arrow_forward_rounded, tooltip: 'رجوع', onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 10),
                  Avatar(widget.p),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(widget.p.name, style: T.label), const Text('الرسائل بتنحفظ ضمن الحجز', style: T.small)])),
                ]),
              ),
            ),
          ),
        ),
        body: Column(children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) return ErrorView(snap.error!, onRetry: () => setState(() {}));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: C.primary));
                final msgs = snap.data!;
                if (msgs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(30), child: Text('ما في رسائل لسا. اسأل عن نقطة الانطلاق أو الشناتي.', style: T.body, textAlign: TextAlign.center)));
                _toEnd();
                return ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[i];
                return Align(
                  alignment: m.mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                  child: Enter(
                    dy: 10,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .75),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: m.mine ? C.primary : Colors.white,
                        borderRadius: BorderRadiusDirectional.only(
                          topStart: const Radius.circular(18),
                          topEnd: const Radius.circular(18),
                          bottomStart: Radius.circular(m.mine ? 6 : 18),
                          bottomEnd: Radius.circular(m.mine ? 18 : 6),
                        ),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.body, style: TextStyle(fontFamily: kFont, fontSize: 15, height: 1.6, color: m.mine ? Colors.white : C.dark)),
                        Text(_time(m.at), style: TextStyle(fontFamily: kFont, fontSize: 10.5, color: m.mine ? Colors.white70 : C.muted)),
                      ]),
                    ),
                  ),
                );
              },
            );
              },
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), scrollDirection: Axis.horizontal, children: [
              for (final q in const ['وصلت عالموعد', 'رح اتأخر 5 دقايق', 'وين بالزبط؟', 'شكراً كتير'])
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 6),
                  child: ActionChip(label: Text(q, style: const TextStyle(fontFamily: kFont)), backgroundColor: Colors.white, side: const BorderSide(color: C.border), onPressed: () => _send(q)),
                ),
            ]),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SafeArea(
              top: false,
              child: Row(children: [
                Expanded(child: TextField(controller: _ctl, onSubmitted: _send, maxLength: 1000, style: const TextStyle(fontFamily: kFont), decoration: const InputDecoration(hintText: 'اكتب رسالة…', fillColor: C.bg, counterText: ''))),
                const SizedBox(width: 10),
                SquareBtn(Icons.send_rounded, solid: true, tooltip: 'إرسال', onTap: () => _send(_ctl.text)),
              ]),
            ),
          ),
        ]),
      );
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen();
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Store.i.refreshAll();
  }

  static IconData _icon(String kind) => switch (kind.split('.').first) {
        'booking' => kind.endsWith('confirmed') ? Icons.check_circle_rounded : (kind.endsWith('requested') ? Icons.add_circle_rounded : Icons.event_busy_rounded),
        'trip' => Icons.route_rounded,
        'application' || 'driver' => Icons.verified_rounded,
        _ => Icons.notifications_rounded,
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) {
          final items = Store.i.notifications;
          return Scaffold(
            appBar: TopBar(title: 'الإشعارات', actions: [
              if (Store.i.unread > 0) TextButton(onPressed: () => attempt(context, Store.i.markAllRead), child: const Text('قراءة الكل', style: TextStyle(fontFamily: kFont, color: C.primary))),
            ]),
            body: items.isEmpty
                ? const EmptyState(image: 'alert_bell', title: 'ما في إشعارات', body: 'رح نخبرك هون لما ينقبل حجزك أو يوصلك طلب أو يتغيّر شي برحلتك.')
                : RefreshIndicator(
                    color: C.primary,
                    onRefresh: Store.i.refreshAll,
                    child: ListView(padding: const EdgeInsets.all(20), children: [
                      for (var i = 0; i < items.length; i++)
                        Enter(
                          delay: i * 50,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: items[i].read ? .75 : 1,
                              child: CardBox(
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Container(width: 46, height: 46, decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(15)), child: Icon(_icon(items[i].kind), color: C.primary)),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(items[i].title, style: T.label), if (items[i].body.isNotEmpty) Text(items[i].body, style: T.body.copyWith(fontSize: 13.5)), Text(timeAgo(items[i].at), style: T.small)])),
                                  if (!items[i].read) Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6), decoration: const BoxDecoration(color: C.primary, shape: BoxShape.circle)),
                                ]),
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
          );
        },
      );
}
