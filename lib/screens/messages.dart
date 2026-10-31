import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../widgets/common.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen();
  @override
  Widget build(BuildContext context) {
    final threads = [
      (samer, 'ولا يهمك، في محل', '18:07', 2),
      (mazen, 'تمام، بشوفك عالكورنيش', '17:40', 1),
      (hussam, 'شكراً، وصلت بالسلامة', 'امبارح', 0),
      (const Person('دعم مشوار', 'م'), 'كيف فينا نساعدك؟', 'الثلاثاء', 0),
    ];
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          const Expanded(child: Text('الرسائل', style: T.h1)),
          SquareBtn(Icons.notifications_none_rounded, tooltip: 'الإشعارات', onTap: () => go(context, const NotificationsScreen())),
        ]),
        const SizedBox(height: 12),
        const TextField(style: TextStyle(fontFamily: kFont), decoration: InputDecoration(hintText: 'دوّر بالمحادثات', prefixIcon: Icon(Icons.search_rounded, color: C.muted))),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: Column(children: [
            for (var i = 0; i < threads.length; i++)
              Enter(
                delay: i * 70,
                child: InkWell(
                  onTap: () => go(context, ChatScreen(threads[i].$1)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(border: i < threads.length - 1 ? const Border(bottom: BorderSide(color: C.line, width: 1.5)) : null),
                    child: Row(children: [
                      Avatar(threads[i].$1, size: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Expanded(child: Text(threads[i].$1.name, style: T.label)), Text(threads[i].$3, style: T.small)]),
                          Row(children: [
                            Expanded(child: Text(threads[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: kFont, fontSize: 13.5, color: threads[i].$4 > 0 ? C.dark : C.muted))),
                            if (threads[i].$4 > 0)
                              Container(
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(color: C.primary, shape: BoxShape.circle),
                                alignment: Alignment.center,
                                child: Text('${threads[i].$4}', style: const TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 12)),
                              ),
                          ]),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Person p;
  const ChatScreen(this.p);
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgs = [...chatSeed];
  final _ctl = TextEditingController();
  final _scroll = ScrollController();

  void _send(String text) {
    if (text.trim().isEmpty) return;
    setState(() => _msgs.add(ChatMsg(true, text.trim(), 'هلق')));
    _ctl.clear();
    Future.delayed(const Duration(milliseconds: 60), () {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

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
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(widget.p.name, style: T.label), const Text('متصل الآن', style: TextStyle(fontFamily: kFont, fontSize: 12, color: Color(0xFF2FBF71)))])),
                  SquareBtn(Icons.call_rounded, solid: true, tooltip: 'اتصال', onTap: () => toast(context, 'جاري الاتصال...')),
                ]),
              ),
            ),
          ),
        ),
        body: Column(children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _msgs.length,
              itemBuilder: (_, i) {
                final m = _msgs[i];
                return Align(
                  alignment: m.me ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                  child: Enter(
                    dy: 10,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .75),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: m.me ? C.primary : Colors.white,
                        borderRadius: BorderRadiusDirectional.only(
                          topStart: const Radius.circular(18),
                          topEnd: const Radius.circular(18),
                          bottomStart: Radius.circular(m.me ? 6 : 18),
                          bottomEnd: Radius.circular(m.me ? 18 : 6),
                        ),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.text, style: TextStyle(fontFamily: kFont, fontSize: 15, height: 1.6, color: m.me ? Colors.white : C.dark)),
                        Text(m.time, style: TextStyle(fontFamily: kFont, fontSize: 10.5, color: m.me ? Colors.white70 : C.muted)),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), scrollDirection: Axis.horizontal, children: [
              for (final q in const ['وصلت عالموعد', 'رح اتأخر 5 دقايق', 'وين بالزبط؟', 'جزاك الله خير'])
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
                Expanded(child: TextField(controller: _ctl, onSubmitted: _send, style: const TextStyle(fontFamily: kFont), decoration: const InputDecoration(hintText: 'اكتب رسالة…', fillColor: C.bg))),
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
  bool _read = false;
  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.check_circle_rounded, 'تم قبول حجزك', 'سامر قبل طلبك لرحلة اللاذقية ← دمشق بكرا 07:00', 'قبل 5 دقايق', true),
      (Icons.chat_bubble_rounded, 'رسالة جديدة', 'سامر: الانطلاق 7 بالزبط من جنب الكورنيش الجنوبي', 'قبل 20 دقيقة', true),
      (Icons.add_circle_rounded, 'طلب حجز جديد', 'مازن بدو مقعد برحلتك يوم السبت', 'قبل ساعة', false),
      (Icons.star_rounded, 'قيّم رحلتك', 'كيف كانت رحلتك من جبلة لحمص؟', 'امبارح', false),
      (Icons.alarm_rounded, 'تذكير', 'رحلتك بكرا الساعة 7 الصبح، لا تتأخر', 'امبارح', false),
    ];
    return Scaffold(
      appBar: TopBar(title: 'الإشعارات', actions: [TextButton(onPressed: () => setState(() => _read = true), child: const Text('قراءة الكل', style: TextStyle(fontFamily: kFont, color: C.primary)))]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        for (var i = 0; i < items.length; i++)
          Enter(
            delay: i * 60,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: items[i].$5 && !_read ? 1 : .8,
                child: CardBox(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 46, height: 46, decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(15)), child: Icon(items[i].$1, color: C.primary)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(items[i].$2, style: T.label), Text(items[i].$3, style: T.body.copyWith(fontSize: 13.5)), Text(items[i].$4, style: T.small)])),
                    if (items[i].$5 && !_read) Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6), decoration: const BoxDecoration(color: C.primary, shape: BoxShape.circle)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
