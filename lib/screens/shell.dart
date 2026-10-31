import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'home.dart';
import 'publish.dart';
import 'my_trips.dart';
import 'messages.dart';
import 'profile.dart';

class AppShell extends StatefulWidget {
  final int initial;
  const AppShell({this.initial = 0});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _i = widget.initial;
  static const _items = [
    (Icons.search_rounded, 'بحث'),
    (Icons.add_circle_outline_rounded, 'انشر'),
    (Icons.route_rounded, 'رحلاتي'),
    (Icons.chat_bubble_outline_rounded, 'الرسائل'),
    (Icons.person_outline_rounded, 'حسابي'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [const HomeScreen(), const PublishStartScreen(), const MyTripsScreen(), const InboxScreen(), const ProfileScreen()];
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .02), end: Offset.zero).animate(a), child: c)),
        child: KeyedSubtree(key: ValueKey(_i), child: pages[_i]),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line, width: 1.5))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 68,
            child: Row(children: [
              for (var k = 0; k < _items.length; k++)
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _i = k),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(color: k == _i ? C.tint : Colors.transparent, borderRadius: BorderRadius.circular(14)),
                        child: Stack(clipBehavior: Clip.none, children: [
                          Icon(_items[k].$1, color: k == _i ? C.primary : C.muted, size: 24),
                          if (k == 3 && _i != 3) Positioned(top: -1, left: -2, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFF0533A), shape: BoxShape.circle))),
                        ]),
                      ),
                      const SizedBox(height: 2),
                      Text(_items[k].$2, style: TextStyle(fontFamily: kFont, fontSize: 11.5, color: k == _i ? C.primary : C.muted)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
