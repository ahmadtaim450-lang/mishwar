import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/store.dart';
import '../data/location.dart';
import '../core/errors.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'splash.dart';
import 'profile.dart';

/// معلومات التسجيل بين الشاشات.
class _Draft {
  static String phone = '';
  static String first = '';
  static String last = '';
}

class LoginScreen extends StatefulWidget {
  const LoginScreen();
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 8600))..repeat();
  final _phone = TextEditingController(text: '');
  @override
  void dispose() {
    _c.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        resizeToAvoidBottomInset: true,
        body: SingleChildScrollView(
          child: Column(children: [
            Container(
              width: double.infinity,
              height: 300,
              decoration: const BoxDecoration(color: C.primary, borderRadius: BorderRadius.vertical(bottom: Radius.circular(36))),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: SyriaMapPainter(t: _c.value), size: Size.infinite)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Enter(child: Text('أهلاً فيك بمشوار', style: T.h1)),
                const SizedBox(height: 6),
                const Enter(delay: 100, child: Text('دخّل رقم موبايلك ورح نبعتلك رمز تحقق برسالة.', style: T.body)),
                const SizedBox(height: 24),
                const Text('رقم الموبايل', style: T.label),
                const SizedBox(height: 8),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(children: [
                    Container(
                      height: 58,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border, width: 1.5)),
                      alignment: Alignment.center,
                      child: const Text('+963', style: TextStyle(fontFamily: kFont, fontSize: 17, color: C.dark)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(fontFamily: kFont, fontSize: 18, letterSpacing: 1),
                        decoration: const InputDecoration(hintText: '9XX XXX XXX'),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                const InfoNote('رقمك ما بيظهر لحدا قبل ما ينقبل الحجز.', icon: Icons.verified_user_outlined),
                const SizedBox(height: 28),
                AsyncBtn('متابعة', busyLabel: 'عم نبعت الرمز...', onTap: () async {
                  final phone = normalizePhone(_phone.text);
                  await Store.i.sendOtp(phone);
                  _Draft.phone = phone;
                  if (context.mounted) go(context, OtpScreen(phone: phone));
                }),
                if (!Store.i.live) ...[
                  const SizedBox(height: 10),
                  const DemoBanner(),
                ],
                const SizedBox(height: 12),
                Center(
                  child: Wrap(alignment: WrapAlignment.center, children: [
                    const Text('بالمتابعة بتوافق على ', style: T.small),
                    GestureDetector(onTap: () => go(context, const TermsScreen()), child: const Text('الشروط', style: TextStyle(fontFamily: kFont, fontSize: 12.5, color: C.primary))),
                    const Text(' و', style: T.small),
                    GestureDetector(onTap: () => go(context, const PrivacyPolicyScreen()), child: const Text('سياسة الخصوصية', style: TextStyle(fontFamily: kFont, fontSize: 12.5, color: C.primary))),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      );
}

class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({required this.phone});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _len = 6;
  final _ctl = TextEditingController();
  String _code = '';
  bool _busy = false;
  int _wait = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    setState(() => _wait = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.length != _len || _busy) return;
    setState(() => _busy = true);
    try {
      final complete = await Store.i.verifyOtp(widget.phone, _code);
      if (!mounted) return;
      if (complete) {
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AppShell()), (_) => false);
      } else {
        go(context, const SignupNameScreen());
      }
    } catch (e) {
      if (!mounted) return;
      toast(context, AppException.from(e).message);
      _ctl.clear();
      setState(() => _code = '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Enter(child: Text('دخّل رمز التحقق', style: T.h1)),
            const SizedBox(height: 6),
            Enter(delay: 100, child: Text('بعتنالك رمز من 6 أرقام على ${widget.phone}', style: T.body, textDirection: TextDirection.rtl)),
            const SizedBox(height: 28),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(children: [
                Row(children: [
                  for (var i = 0; i < _len; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: i == _code.length ? C.yellow : (i < _code.length ? C.primary : C.border), width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(i < _code.length ? _code[i] : '', style: const TextStyle(fontFamily: kFont, fontSize: 28, color: C.dark)),
                      ),
                    ),
                ]),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: _ctl,
                      autofocus: true,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: _len,
                      onChanged: (v) {
                        setState(() => _code = v.replaceAll(RegExp(r'[^0-9]'), ''));
                        if (_code.length == _len) _verify();
                      },
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Center(
              child: _wait > 0
                  ? Text('ما وصلك؟ فيك تطلب رمز جديد بعد 0:${_wait.toString().padLeft(2, '0')}', style: T.small)
                  : TextButton(
                      onPressed: () async {
                        if (await attempt(context, () => Store.i.sendOtp(widget.phone))) _tick();
                      },
                      child: const Text('ابعتلي رمز جديد', style: TextStyle(fontFamily: kFont, color: C.primary)),
                    ),
            ),
            if (!Store.i.live) const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: Text('بالنسخة التجريبية أي 6 أرقام بتمشي', style: T.small))),
            const Spacer(),
            _busy ? const Center(child: CircularProgressIndicator(color: C.primary)) : Btn('تأكيد', onTap: _code.length == _len ? _verify : null),
          ]),
        ),
      );
}

class _SignupFrame extends StatelessWidget {
  final int step;
  final String title;
  final String? sub;
  final List<Widget> children;
  final String cta;
  final Future<void> Function() onNext;
  const _SignupFrame({required this.step, required this.title, this.sub, required this.children, this.cta = 'متابعة', required this.onNext});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(),
        body: Column(children: [
          StepBar(step, 5),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Enter(child: Text(title, style: T.h1)),
              if (sub != null) Enter(delay: 100, child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(sub!, style: T.body))),
              const SizedBox(height: 20),
              ...children,
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), child: AsyncBtn(cta, onTap: onNext)),
        ]),
      );
}

class SignupNameScreen extends StatefulWidget {
  const SignupNameScreen();
  @override
  State<SignupNameScreen> createState() => _SignupNameScreenState();
}

class _SignupNameScreenState extends State<SignupNameScreen> {
  final _first = TextEditingController(text: _Draft.first);
  final _last = TextEditingController(text: _Draft.last);
  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SignupFrame(
        step: 1,
        title: 'شو اسمك؟',
        sub: 'هيك رح يشوفك السائقين والركاب.',
        onNext: () async {
          final f = _first.text.trim(), l = _last.text.trim();
          if (f.length < 2) throw const AppException('INVALID_NAME', 'اكتب اسمك الأول');
          if ('$f $l'.trim().length < 3) throw AppException('INVALID_NAME', AppException.messages['INVALID_NAME']!);
          _Draft.first = f;
          _Draft.last = l;
          go(context, const SignupGenderScreen());
        },
        children: [
          const Text('الاسم الأول', style: T.label),
          const SizedBox(height: 8),
          TextField(controller: _first, textInputAction: TextInputAction.next, maxLength: 40, style: const TextStyle(fontFamily: kFont, fontSize: 17), decoration: const InputDecoration(counterText: '')),
          const SizedBox(height: 16),
          const Text('الكنية', style: T.label),
          const SizedBox(height: 8),
          TextField(controller: _last, maxLength: 40, style: const TextStyle(fontFamily: kFont, fontSize: 17), decoration: const InputDecoration(hintText: 'اختياري', counterText: '')),
          const SizedBox(height: 16),
          const InfoNote('استخدم اسمك الحقيقي، الحسابات بأسماء وهمية بتنوقف.'),
        ],
      );
}

class SignupGenderScreen extends StatefulWidget {
  const SignupGenderScreen();
  @override
  State<SignupGenderScreen> createState() => _SignupGenderScreenState();
}

class _SignupGenderScreenState extends State<SignupGenderScreen> {
  int _g = 0;
  @override
  Widget build(BuildContext context) => _SignupFrame(
        step: 2,
        title: 'عرّفنا عليك أكتر',
        onNext: () async {
          await Store.i.completeProfile('${_Draft.first} ${_Draft.last}'.trim(), _g == 1);
          if (context.mounted) go(context, SafeModeScreen(female: _g == 1));
        },
        children: [
          const Text('الجنس', style: T.label),
          const SizedBox(height: 8),
          ChoiceCards(options: const [('ذكر', ''), ('أنثى', '')], selected: {_g}, onTap: (i) => setState(() => _g = i)),
          const SizedBox(height: 8),
          const InfoNote('منستخدمها لنعرضلك الرحلات المناسبة إلك، وما بتتغيّر بعد التسجيل.', icon: Icons.lock_outline_rounded),
        ],
      );
}

class SafeModeScreen extends StatefulWidget {
  final bool female;
  const SafeModeScreen({this.female = false});
  @override
  State<SafeModeScreen> createState() => _SafeModeScreenState();
}

class _SafeModeScreenState extends State<SafeModeScreen> {
  late int _m = widget.female ? 1 : 0;
  @override
  Widget build(BuildContext context) => _SignupFrame(
        step: 3,
        title: 'كيف بتحب تسافر؟',
        sub: 'بنعرضلك بس الرحلات اللي بتناسبك، وفيك تغيّرها بأي وقت.',
        onNext: () async => go(context, const SignupPhotoScreen()),
        children: [
          ChoiceCards(
            options: widget.female
                ? const [('رحلات نسائية', 'سائقة وراكبات فقط'), ('رحلات عائلية', 'مع أفراد عائلتي')]
                : const [('رحلات رجال', 'سائق رجل وركاب رجال'), ('رحلات عائلية', 'مع أفراد عائلتي'), ('الاثنين', 'رجال وعائلات')],
            selected: {_m.clamp(0, widget.female ? 1 : 2)},
            onTap: (i) => setState(() => _m = i),
          ),
          const InfoNote('الراكبات ما بيظهرلن إلا رحلات السائقات أو الرحلات العائلية.', icon: Icons.shield_outlined),
        ],
      );
}

class SignupPhotoScreen extends StatelessWidget {
  const SignupPhotoScreen();
  @override
  Widget build(BuildContext context) => _SignupFrame(
        step: 4,
        title: 'ضيف صورة لوجهك',
        sub: 'الملفات اللي فيها صورة واضحة بتنقبل حجوزاتها أسرع.',
        cta: 'التقط صورة',
        onNext: () async => go(context, const PermissionsScreen()),
        children: [
          Center(
            child: Floaty(
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(color: C.tint, shape: BoxShape.circle, border: Border.all(color: C.primary, width: 3)),
                child: const Icon(Icons.person_rounded, size: 110, color: C.primary),
              ),
            ),
          ),
          const SizedBox(height: 24),
          for (final t in ['وجهك واضح ومو مغطى', 'لحالك بالصورة', 'بدون فلاتر'])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [const Icon(Icons.check_circle_rounded, color: C.primary, size: 20), const SizedBox(width: 8), Text(t, style: T.body)]),
            ),
          TextButton(onPressed: () => go(context, const PermissionsScreen()), child: const Text('بعدين', style: TextStyle(fontFamily: kFont, color: C.muted))),
        ],
      );
}

class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen();
  @override
  Widget build(BuildContext context) => _SignupFrame(
        step: 5,
        title: 'خلّي التطبيق يساعدك',
        cta: 'سماح ومتابعة',
        onNext: () async {
          await myPosition();
          if (context.mounted) goReplace(context, const WelcomeScreen());
        },
        children: [
          for (final (img, t, s) in const [
            ('perm_location', 'الموقع', 'لنقترح عليك أقرب نقطة انطلاق، ولمشاركة الرحلة مع أهلك.'),
            ('perm_notifications', 'الإشعارات', 'لتعرف فوراً لما ينقبل حجزك أو يوصلك طلب.'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CardBox(
                child: Row(children: [
                  Illus(img, width: 72, height: 72),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: T.h3), Text(s, style: T.small)])),
                ]),
              ),
            ),
        ],
      );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.primary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(),
              const Floaty(child: Illus('welcome', height: 300)),
              const SizedBox(height: 16),
              Enter(child: Text('أهلا فيك يا ${Store.i.name}!', textAlign: TextAlign.center, style: const TextStyle(fontFamily: kFont, fontSize: 38, color: Colors.white))),
              const Enter(delay: 120, child: Text('حسابك جاهز. لوين أول مشوار؟', style: TextStyle(fontFamily: kFont, fontSize: 17, color: Colors.white))),
              const Spacer(),
              Btn('دوّر على رحلة', kind: BtnKind.white, icon: Icons.search_rounded, onTap: () => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AppShell()), (_) => false)),
              const SizedBox(height: 10),
              Btn('صير سائق موثّق', kind: BtnKind.dark, icon: Icons.add_circle_outline_rounded, onTap: () => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AppShell(initial: 2)), (_) => false)),
            ]),
          ),
        ),
      );
}
