import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'auth.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen();
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _i = 0;
  static const _pages = [
    ('onboard1', 'شارك الطريق،\nوقسّم المصروف', 'لاقي سيارة رايحة على وجهتك، أو اعرض المقاعد الفاضية بسيارتك.'),
    ('onboard2', 'سايق لحالك؟\nرجّع حق البنزين', 'انشر رحلتك بدقيقة، واختار مين يطلع معك.'),
    ('women_only', 'رحلات نسائية\nوعائلية', 'سائقات لراكبات، وسفر عائلي مع مَحرَم. بكل احترام وأمان.'),
    ('onboard3', 'مجتمع موثوق\nومحترم', 'كل الأعضاء موثّقين برقم الموبايل، وفيك تشوف التقييمات قبل ما تحجز.'),
  ];

  @override
  Widget build(BuildContext context) {
    final last = _i == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('مشوار', style: TextStyle(fontFamily: kFont, fontSize: 28, color: C.primary)),
              TextButton(onPressed: () => goReplace(context, const LoginScreen()), child: const Text('تخطّي', style: TextStyle(fontFamily: kFont, color: C.muted, fontSize: 15))),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: _pages.length,
              onPageChanged: (v) => setState(() => _i = v),
              itemBuilder: (_, i) {
                final p = _pages[i];
                return AnimatedBuilder(
                  animation: _pc,
                  builder: (_, __) {
                    final page = _pc.hasClients && _pc.position.haveDimensions ? _pc.page! : 0.0;
                    final d = (page - i).clamp(-1.0, 1.0);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SizedBox(height: 12),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(32)),
                            clipBehavior: Clip.antiAlias,
                            child: Transform.translate(
                              offset: Offset(d * 80, 0),
                              child: Floaty(child: Illus(p.$1, fit: BoxFit.contain)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Opacity(opacity: 1 - d.abs(), child: Text(p.$2, style: T.h1.copyWith(fontSize: 36))),
                        const SizedBox(height: 10),
                        Opacity(opacity: 1 - d.abs(), child: Text(p.$3, style: T.body)),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(children: [
              Row(children: [
                for (var k = 0; k < _pages.length; k++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(left: 6),
                    width: k == _i ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(color: k == _i ? C.primary : const Color(0xFFC7D1D1), borderRadius: BorderRadius.circular(8)),
                  ),
              ]),
              const SizedBox(height: 18),
              Btn(last ? 'إنشاء حساب' : 'التالي', onTap: () {
                if (last) {
                  goReplace(context, const LoginScreen());
                } else {
                  _pc.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
                }
              }),
              const SizedBox(height: 10),
              Btn('عندي حساب', kind: BtnKind.outline, onTap: () => goReplace(context, const LoginScreen())),
            ]),
          ),
        ]),
      ),
    );
  }
}
