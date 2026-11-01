import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../core/errors.dart';

/// صورة من assets/images مع بديل أنيق إذا ما كانت موجودة.
class Illus extends StatelessWidget {
  final String name;
  final double? width, height;
  final BoxFit fit;
  final IconData fallback;
  const Illus(this.name, {this.width, this.height, this.fit = BoxFit.contain, this.fallback = Icons.image_outlined});
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/$name.png',
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => SizedBox(
        width: width,
        height: height,
        child: Center(child: Icon(fallback, size: ((height ?? 120) * .4).clamp(24, 80).toDouble(), color: C.primary.withValues(alpha: .5))),
      ),
    );
  }
}

/// حركة دخول: ظهور وانزلاق خفيف، مع تأخير.
class Enter extends StatefulWidget {
  final Widget child;
  final int delay;
  final double dy;
  const Enter({super.key, required this.child, this.delay = 0, this.dy = 18});
  @override
  State<Enter> createState() => _EnterState();
}

class _EnterState extends State<Enter> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: a,
      builder: (_, child) => Opacity(opacity: a.value, child: Transform.translate(offset: Offset(0, widget.dy * (1 - a.value)), child: child)),
      child: widget.child,
    );
  }
}

/// تطفو للأعلى والأسفل بلطف (للرسومات).
class Floaty extends StatefulWidget {
  final Widget child;
  final double amp;
  const Floaty({required this.child, this.amp = 8});
  @override
  State<Floaty> createState() => _FloatyState();
}

class _FloatyState extends State<Floaty> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.translate(offset: Offset(0, -widget.amp * Curves.easeInOut.transform(_c.value)), child: child),
        child: widget.child,
      );
}

/// زر بيصغر شوي لما تضغط عليه.
class Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const Press({required this.child, this.onTap});
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(scale: _down ? .96 : 1, duration: const Duration(milliseconds: 120), child: widget.child),
      );
}

enum BtnKind { primary, outline, ghost, danger, white, dark }

class Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final BtnKind kind;
  final IconData? icon;
  const Btn(this.label, {this.onTap, this.kind = BtnKind.primary, this.icon});
  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (C.primary, Colors.white, null),
      BtnKind.outline => (Colors.white, C.dark, C.border),
      BtnKind.ghost => (Colors.transparent, C.dark, null),
      BtnKind.danger => (C.dangerBg, C.danger, null),
      BtnKind.white => (Colors.white, C.primary, null),
      BtnKind.dark => (C.dark, Colors.white, null),
    };
    return Opacity(
     opacity: onTap == null ? .55 : 1,
     child: Press(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: border == null ? null : Border.all(color: border, width: 1.5),
          boxShadow: kind == BtnKind.primary ? [BoxShadow(color: C.primary.withValues(alpha: .28), blurRadius: 18, offset: const Offset(0, 8))] : null,
        ),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 8)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 17, fontFamily: kFont))),
        ]),
      ),
     ),
    );
  }
}

class SquareBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool solid;
  final String tooltip;
  const SquareBtn(this.icon, {this.onTap, this.solid = false, this.tooltip = ''});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        child: Press(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: solid ? C.primary : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: solid ? null : Border.all(color: C.border, width: 1.5),
            ),
            child: Icon(icon, color: solid ? Colors.white : C.dark, size: 22),
          ),
        ),
      );
}

class TopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? sub;
  final List<Widget> actions;
  final bool close;
  const TopBar({this.title = '', this.sub, this.actions = const [], this.close = false});
  @override
  Size get preferredSize => const Size.fromHeight(76);
  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(children: [
            if (Navigator.canPop(context)) SquareBtn(close ? Icons.close_rounded : Icons.arrow_forward_rounded, tooltip: 'رجوع', onTap: () => Navigator.pop(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (title.isNotEmpty) Text(title, style: T.h3),
                if (sub != null) Text(sub!, style: T.small),
              ]),
            ),
            ...actions,
          ]),
        ),
      );
}

class CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final VoidCallback? onTap;
  const CardBox({required this.child, this.padding = const EdgeInsets.all(16), this.color = Colors.white, this.onTap});
  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22)),
      child: child,
    );
    return onTap == null ? box : Press(onTap: onTap, child: box);
  }
}

class Avatar extends StatelessWidget {
  final Person p;
  final double size;
  const Avatar(this.p, {this.size = 44});
  @override
  Widget build(BuildContext context) => ClipOval(
        child: Container(
          width: size,
          height: size,
          color: const Color(0xFFD7F0FC),
          alignment: Alignment.center,
          child: p.image == null
              ? Text(p.initial, style: TextStyle(fontSize: size * .42, color: C.dark, fontFamily: kFont))
              : Image.asset('assets/images/${p.image}.png', width: size, height: size, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Text(p.initial, style: TextStyle(fontSize: size * .42, color: C.dark, fontFamily: kFont))),
        ),
      );
}

class Badge2 extends StatelessWidget {
  final String text;
  final Color bg, fg;
  const Badge2(this.text, {this.bg = C.tint, this.fg = C.dark});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 12.5, fontFamily: kFont)),
      );
}

class KindBadge extends StatelessWidget {
  final RideKind kind;
  const KindBadge(this.kind);
  @override
  Widget build(BuildContext context) => switch (kind) {
        RideKind.women => const Badge2('نسائية', bg: Color(0xFFFFF4D6), fg: C.warn),
        RideKind.family => const Badge2('عائلية', bg: C.tint, fg: C.dark),
        RideKind.men => const Badge2('رجال', bg: C.line, fg: C.muted2),
      };
}

class InfoNote extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool warn;
  const InfoNote(this.text, {this.icon = Icons.info_outline_rounded, this.warn = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: warn ? C.warnBg : C.tint, borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: warn ? C.warn : C.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.7, color: warn ? C.warn : C.dark, fontFamily: kFont))),
        ]),
      );
}

class Timeline extends StatelessWidget {
  final String a, b, ta, tb, sa, sb;
  const Timeline({required this.a, required this.b, required this.ta, required this.tb, this.sa = '', this.sb = ''});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 96,
        child: Row(children: [
          Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(ta, style: T.label), Text(tb, style: T.label)]),
          const SizedBox(width: 14),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.primary, width: 3))),
              Expanded(child: Container(width: 2, color: const Color(0xFFC7D1D1))),
              Container(width: 12, height: 12, decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(3))),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a, style: T.label), if (sa.isNotEmpty) Text(sa, style: T.small)]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(b, style: T.label), if (sb.isNotEmpty) Text(sb, style: T.small)]),
            ]),
          ),
        ]),
      );
}

class ChipGroup extends StatelessWidget {
  final List<String> options;
  final Set<int> selected;
  final ValueChanged<int> onTap;
  const ChipGroup({required this.options, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < options.length; i++)
          Press(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected.contains(i) ? C.tint : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected.contains(i) ? C.primary : C.border, width: 1.5),
              ),
              child: Text(options[i], style: TextStyle(fontSize: 14, color: selected.contains(i) ? C.dark : C.muted2, fontFamily: kFont)),
            ),
          ),
      ]);
}

class ChoiceCards extends StatelessWidget {
  final List<(String, String)> options;
  final Set<int> selected;
  final ValueChanged<int> onTap;
  final bool multi;
  const ChoiceCards({required this.options, required this.selected, required this.onTap, this.multi = false});
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Press(
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selected.contains(i) ? C.primary : Colors.white, width: 2),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(options[i].$1, style: T.label),
                      if (options[i].$2.isNotEmpty) Text(options[i].$2, style: T.small),
                    ]),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: selected.contains(i) ? C.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(multi ? 7 : 24),
                      border: Border.all(color: selected.contains(i) ? C.primary : const Color(0xFFC7D1D1), width: 2),
                    ),
                    child: selected.contains(i) ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                  ),
                ]),
              ),
            ),
          ),
      ]);
}

class Counter extends StatelessWidget {
  final int value, min, max;
  final ValueChanged<int> onChanged;
  final bool big;
  final String Function(int)? fmt;
  const Counter({required this.value, required this.onChanged, this.min = 1, this.max = 4, this.big = false, this.fmt});
  @override
  Widget build(BuildContext context) {
    final s = big ? 64.0 : 44.0;
    Widget b(IconData i, bool solid, VoidCallback? f) => Press(
          onTap: f,
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(color: solid ? C.primary : Colors.white, borderRadius: BorderRadius.circular(s / 3), border: solid ? null : Border.all(color: C.border, width: 1.5)),
            child: Icon(i, color: solid ? Colors.white : C.dark, size: s * .5),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      b(Icons.add_rounded, true, value < max ? () => onChanged(value + 1) : null),
      SizedBox(width: big ? 24 : 14),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: Text(fmt == null ? '$value' : fmt!(value), key: ValueKey(value), style: TextStyle(fontSize: big ? 48 : 22, color: C.dark, fontFamily: kFont)),
      ),
      SizedBox(width: big ? 24 : 14),
      b(Icons.remove_rounded, false, value > min ? () => onChanged(value - 1) : null),
    ]);
  }
}

class StepBar extends StatelessWidget {
  final int step, total;
  const StepBar(this.step, this.total);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          for (var i = 0; i < total; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 5,
                decoration: BoxDecoration(color: i < step ? C.primary : C.border, borderRadius: BorderRadius.circular(5)),
              ),
            ),
        ]),
      );
}

class RowItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  const RowItem(this.icon, this.label, {this.sub, this.trailing, this.onTap, this.danger = false});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: danger ? C.dangerBg : C.tint, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: danger ? C.danger : C.primary, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 15.5, color: danger ? C.danger : C.dark, fontFamily: kFont)),
                if (sub != null) Text(sub!, style: T.small),
              ]),
            ),
            trailing ?? const Icon(Icons.chevron_left_rounded, color: C.muted),
          ]),
        ),
      );
}

class Group extends StatelessWidget {
  final List<Widget> children;
  final String? title;
  const Group(this.children, {this.title});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) Padding(padding: const EdgeInsets.fromLTRB(6, 6, 6, 8), child: Text(title!, style: T.small)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1) const Divider(height: 1, color: C.line),
            ]
          ]),
        ),
      ]);
}

class EmptyState extends StatelessWidget {
  final String image, title, body;
  final List<Widget> actions;
  const EmptyState({super.key, required this.image, required this.title, required this.body, this.actions = const []});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          Floaty(child: Illus(image, width: 220, height: 220)),
          const SizedBox(height: 12),
          Enter(child: Text(title, style: T.h1, textAlign: TextAlign.center)),
          const SizedBox(height: 8),
          Enter(delay: 120, child: Text(body, style: T.body, textAlign: TextAlign.center)),
          const SizedBox(height: 24),
          ...actions.map((a) => Padding(padding: const EdgeInsets.only(bottom: 10), child: a)),
        ]),
      );
}

void go(BuildContext c, Widget page) => Navigator.of(c).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final cv = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: cv,
          child: SlideTransition(position: Tween(begin: const Offset(-.08, 0), end: Offset.zero).animate(cv), child: child),
        );
      },
    ));

void goReplace(BuildContext c, Widget page) => Navigator.of(c).pushAndRemoveUntil(
      PageRouteBuilder(transitionDuration: const Duration(milliseconds: 500), pageBuilder: (_, __, ___) => page, transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child)),
      (_) => false,
    );

void toast(BuildContext c, String msg) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: kFont)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.dark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));

/// أيقونة رسائل مدوّرة (فقاعة دائرية بذيل صغير وثلاث نقاط).
class RoundChatIcon extends StatelessWidget {
  final double size;
  final Color color;
  final bool filled;
  const RoundChatIcon({this.size = 24, this.color = C.dark, this.filled = false});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _RoundChatPainter(color, filled));
}

class _RoundChatPainter extends CustomPainter {
  final Color color;
  final bool filled;
  _RoundChatPainter(this.color, this.filled);
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final c = Offset(w * .5, w * .47);
    final r = w * .38;
    final bubble = Path()
      ..addOval(Rect.fromCircle(center: c, radius: r))
      ..moveTo(c.dx - r * .55, c.dy + r * .72)
      ..quadraticBezierTo(c.dx - r * .95, c.dy + r * 1.15, c.dx - r * 1.12, c.dy + r * 1.18)
      ..quadraticBezierTo(c.dx - r * .9, c.dy + r * .85, c.dx - r * .88, c.dy + r * .5);
    final stroke = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = w * .085
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(bubble, stroke);
    final dot = Paint()..color = filled ? Colors.white : color;
    for (final dx in [-.42, 0.0, .42]) {
      canvas.drawCircle(Offset(c.dx + r * dx, c.dy), w * .055, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _RoundChatPainter o) => o.color != color || o.filled != filled;
}

/// بيشغّل عملية، وإذا فشلت بيعرض رسالة مفهومة. بيرجّع true إذا نجحت.
Future<bool> attempt(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
    return true;
  } catch (e) {
    if (context.mounted) toast(context, AppException.from(e).message);
    return false;
  }
}

/// زر بيعرض تحميل وقت العملية، وما بينضغط مرتين.
class AsyncBtn extends StatefulWidget {
  final String label;
  final Future<void> Function()? onTap;
  final BtnKind kind;
  final IconData? icon;
  final String? busyLabel;
  const AsyncBtn(this.label, {super.key, this.onTap, this.kind = BtnKind.primary, this.icon, this.busyLabel});
  @override
  State<AsyncBtn> createState() => _AsyncBtnState();
}

class _AsyncBtnState extends State<AsyncBtn> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    if (_busy) {
      final light = widget.kind == BtnKind.primary || widget.kind == BtnKind.dark;
      return Container(
        height: 56,
        decoration: BoxDecoration(color: light ? (widget.kind == BtnKind.dark ? C.dark : C.primary) : Colors.white, borderRadius: BorderRadius.circular(18)),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: light ? Colors.white : C.primary)),
          const SizedBox(width: 10),
          Text(widget.busyLabel ?? 'لحظة...', style: TextStyle(fontFamily: kFont, fontSize: 16, color: light ? Colors.white : C.dark)),
        ]),
      );
    }
    return Btn(widget.label, kind: widget.kind, icon: widget.icon, onTap: widget.onTap == null
        ? null
        : () async {
            setState(() => _busy = true);
            await attempt(context, widget.onTap!);
            if (mounted) setState(() => _busy = false);
          });
  }
}

/// حالة خطأ مع زر إعادة المحاولة.
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorView(this.error, {super.key, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    final e = AppException.from(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(e.code == 'NETWORK' ? Icons.wifi_off_rounded : Icons.error_outline_rounded, size: 56, color: C.muted),
          const SizedBox(height: 12),
          Text(e.code == 'NETWORK' ? 'ما في نت' : 'ما زبطت', style: T.h2, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(e.message, style: T.body, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          SizedBox(width: 200, child: Btn('جرّب مرة تانية', icon: Icons.refresh_rounded, onTap: onRetry)),
        ]),
      ),
    );
  }
}

/// شريط صغير بيوضح إنو التطبيق بالوضع التجريبي.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.science_outlined, size: 18, color: C.warn),
          SizedBox(width: 8),
          Expanded(child: Text('نسخة تجريبية: الرحلات والحجوزات للتجربة بس', style: TextStyle(fontFamily: kFont, fontSize: 12.5, color: C.warn))),
        ]),
      );
}
