import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/store.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'splash.dart';
import 'profile.dart';

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
                Btn('متابعة', onTap: () => go(context, const OtpScreen())),
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
  const OtpScreen();
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _code = '';
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Enter(child: Text('دخّل رمز التحقق', style: T.h1)),
            const SizedBox(height: 6),
            const Enter(delay: 100, child: Text('بعتنالك رمز من 4 أرقام برسالة.', style: T.body)),
            const SizedBox(height: 28),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(children: [
                Row(children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: i == _code.length ? C.yellow : (i < _code.length ? C.primary : C.border), width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(i < _code.length ? _code[i] : '', style: const TextStyle(fontFamily: kFont, fontSize: 30, color: C.dark)),
                      ),
                    ),
                ]),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      onChanged: (v) {
                        setState(() => _code = v);
                        if (v.length == 4) go(context, const SignupNameScreen());
                      },
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            const Center(child: Text('ما وصلك؟ إعادة الإرسال بعد 0:42', style: T.small)),
            const Spacer(),
            Btn('تأكيد', onTap: () => go(context, const SignupNameScreen())),
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
  final VoidCallback onNext;
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
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), child: Btn(cta, onTap: onNext)),
        ]),
      );
}

class SignupNameScreen extends StatelessWidget {
  const SignupNameScreen();
  @override
  Widget build(BuildContext context) => _SignupFrame(
        step: 1,
        title: 'شو اسمك؟',
        sub: 'هيك رح يشوفك السائقين والركاب.',
        onNext: () => go(context, const SignupGenderScreen()),
        children: const [
          Text('الاسم الأول', style: T.label),
          SizedBox(height: 8),
          TextField(style: TextStyle(fontFamily: kFont, fontSize: 17)),
          SizedBox(height: 16),
          Text('الكنية', style: T.label),
          SizedBox(height: 8),
          TextField(style: TextStyle(fontFamily: kFont, fontSize: 17), decoration: InputDecoration(hintText: 'اختياري')),
          SizedBox(height: 16),
          InfoNote('استخدم اسمك الحقيقي، الحسابات بأسماء وهمية بتنوقف.'),
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
        onNext: () {
          Store.i.setFemale(_g == 1);
          go(context, SafeModeScreen(female: _g == 1));
        },
        children: [
          const Text('الجنس', style: T.label),
          const SizedBox(height: 8),
          ChoiceCards(options: const [('ذكر', ''), ('أنثى', '')], selected: {_g}, onTap: (i) => setState(() => _g = i)),
          const SizedBox(height: 8),
          const InfoNote('منستخدمها لنعرضلك الرحلات المناسبة إلك، وما بتنعرض عملفك.', icon: Icons.lock_outline_rounded),
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
        onNext: () => go(context, const SignupPhotoScreen()),
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
        onNext: () => go(context, const PermissionsScreen()),
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
        onNext: () => goReplace(context, const WelcomeScreen()),
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
              const Enter(child: Text('أهلا فيك يا إيهاب!', style: TextStyle(fontFamily: kFont, fontSize: 40, color: Colors.white))),
              const Enter(delay: 120, child: Text('حسابك جاهز. لوين أول مشوار؟', style: TextStyle(fontFamily: kFont, fontSize: 17, color: Colors.white))),
              const Spacer(),
              Btn('دوّر على رحلة', kind: BtnKind.white, icon: Icons.search_rounded, onTap: () => goReplace(context, const AppShell())),
              const SizedBox(height: 10),
              Btn('انشر رحلة', kind: BtnKind.dark, icon: Icons.add_circle_outline_rounded, onTap: () => goReplace(context, const AppShell(initial: 2))),
            ]),
          ),
        ),
      );
}
