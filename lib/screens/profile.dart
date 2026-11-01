import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'driver_join.dart';
import '../data/store.dart';
import '../data/mock.dart';
import '../widgets/common.dart';
import 'splash.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen();
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Store.i, builder: (context, _) => ListView(padding: EdgeInsets.zero, children: [
        Container(
          padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 24, 20, 64),
          color: C.primary,
          child: Column(children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(Store.i.name.isEmpty ? '؟' : Store.i.name.substring(0, 1), style: const TextStyle(fontFamily: kFont, fontSize: 46, color: C.primary)),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text(Store.i.profile?.name ?? Store.i.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kFont, fontSize: 24, color: Colors.white))),
              if (Store.i.driverStatus == DStatus.approved) ...[const SizedBox(width: 6), const Icon(Icons.verified_rounded, color: Colors.white, size: 20)],
            ]),
            Text(Store.i.profile?.phone ?? '', textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: kFont, color: Colors.white)),
          ]),
        ),
        Transform.translate(
          offset: const Offset(0, -40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: C.dark.withValues(alpha: .1), blurRadius: 30, offset: const Offset(0, 12))]),
                child: Row(children: [
                  for (final (a, b) in [('${Store.i.profile?.trips ?? 0}', 'رحلة'), ('★ ${(Store.i.profile?.rating ?? 0) == 0 ? '—' : Store.i.profile!.rating.toStringAsFixed(1)}', 'تقييم'), ('${Store.i.bookings.length}', 'حجوزات')])
                    Expanded(child: Column(children: [Text(a, style: const TextStyle(fontFamily: kFont, fontSize: 20, color: C.dark)), Text(b, style: T.small)])),
                ]),
              ),
              const SizedBox(height: 14),
              CardBox(
                color: C.tint,
                onTap: () => go(context, const VerifyScreen()),
                child: const Row(children: [
                  Icon(Icons.shield_outlined, color: C.primary),
                  SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('وثّق هويتك', style: T.label), Text('الحسابات الموثقة بتنحجز أسرع', style: T.small)])),
                  Icon(Icons.chevron_left_rounded, color: C.dark),
                ]),
              ),
              const SizedBox(height: 12),
              Group([
                RowItem(
                  Icons.verified_outlined,
                  switch (Store.i.driverStatus) { DStatus.none => 'صير سائق موثّق', DStatus.approved => 'سائق موثّق ✓', _ => 'حالة طلب السائق' },
                  sub: switch (Store.i.driverStatus) { DStatus.none => 'انشر رحلاتك بعد مقابلة قصيرة', DStatus.reviewing => 'عم نراجع أوراقك', DStatus.interview => 'موعد المقابلة جاهز', DStatus.approved => Store.i.profile?.car ?? '', DStatus.rejected => 'ما انقبل الطلب، فيك تقدّم من جديد', DStatus.suspended => 'موقوف للمراجعة' },
                  onTap: () => go(context, Store.i.driverStatus == DStatus.none ? const DriverApplyFlow() : const DriverStatusScreen()),
                ),
                RowItem(Icons.edit_outlined, 'تعديل الملف', onTap: () => go(context, const EditProfileScreen())),
                RowItem(Icons.tune_rounded, 'تفضيلات السفر', onTap: () => go(context, const TravelPrefsScreen())),
                RowItem(Icons.directions_car_outlined, 'سياراتي', sub: Store.i.profile?.car ?? 'ما في سيارة موثّقة', onTap: () => go(context, const CarsScreen())),
                RowItem(Icons.history_rounded, 'سجل الرحلات', onTap: () => go(context, const HistoryScreen())),
              ]),
              const SizedBox(height: 12),
              Group([
                RowItem(Icons.shield_outlined, 'مركز الأمان', onTap: () => go(context, const SafetyScreen())),
                RowItem(Icons.card_giftcard_rounded, 'ادعُ أصحابك', onTap: () => go(context, const InviteScreen())),
                RowItem(Icons.workspace_premium_outlined, 'مشوار بلس', sub: 'قريباً', onTap: () => go(context, const PlusScreen())),
                RowItem(Icons.help_outline_rounded, 'المساعدة', onTap: () => go(context, const HelpScreen())),
                RowItem(Icons.settings_outlined, 'الإعدادات', onTap: () => go(context, const SettingsScreen())),
              ]),
            ]),
          ),
        ),
      ]));
}

class _Simple extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? bottom;
  final Color bg;
  const _Simple(this.title, this.children, {this.bottom, this.bg = C.bg});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: bg,
        appBar: TopBar(title: title),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: children),
        bottomNavigationBar: bottom == null ? null : SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: bottom)),
      );
}

class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen();
  @override
  Widget build(BuildContext context) => _Simple('تعديل الملف', [
        Center(
          child: Stack(children: [
            const CircleAvatar(radius: 52, backgroundColor: C.primary, child: Text('إ', style: TextStyle(fontFamily: kFont, fontSize: 46, color: Colors.white))),
            Positioned(bottom: 0, left: 0, child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: C.dark, shape: BoxShape.circle), child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18))),
          ]),
        ),
        const SizedBox(height: 20),
        const Text('الاسم', style: T.label),
        const SizedBox(height: 6),
        TextFormField(initialValue: 'إيهاب', style: const TextStyle(fontFamily: kFont, fontSize: 16)),
        const SizedBox(height: 14),
        const Text('المدينة', style: T.label),
        const SizedBox(height: 6),
        TextFormField(initialValue: 'اللاذقية', style: const TextStyle(fontFamily: kFont, fontSize: 16)),
        const SizedBox(height: 14),
        const Text('نبذة عنك', style: T.label),
        const SizedBox(height: 6),
        TextFormField(initialValue: 'بسافر كتير بين اللاذقية ودمشق.', maxLines: 3, style: const TextStyle(fontFamily: kFont, fontSize: 15)),
      ], bottom: Btn('حفظ', onTap: () {
        toast(context, 'انحفظت التعديلات');
        Navigator.pop(context);
      }));
}

class TravelPrefsScreen extends StatefulWidget {
  const TravelPrefsScreen();
  @override
  State<TravelPrefsScreen> createState() => _TravelPrefsScreenState();
}

class _TravelPrefsScreenState extends State<TravelPrefsScreen> {
  final _v = [1, 0, 0, 1];
  static const _groups = [
    ('الحكي', ['بحب الحكي', 'حسب المزاج', 'بحب الهدوء']),
    ('بالسيارة', ['أغاني', 'بلا أغاني', 'حسب الركاب']),
    ('التدخين', ['ممنوع', 'بالوقفات بس', 'عادي']),
    ('الاستراحة', ['كل ساعتين', 'حسب الطريق', 'بلا وقفات']),
  ];
  @override
  Widget build(BuildContext context) => _Simple('تفضيلات السفر', [
        const Text('بتظهر عملفك لحتى يعرف الركاب والسائقين شو بتحب.', style: T.body),
        const SizedBox(height: 10),
        for (var g = 0; g < _groups.length; g++) ...[
          Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: Text(_groups[g].$1, style: T.label)),
          ChipGroup(options: _groups[g].$2, selected: {_v[g]}, onTap: (i) => setState(() => _v[g] = i)),
        ],
      ], bottom: Btn('حفظ', onTap: () => Navigator.pop(context)));
}

class CarsScreen extends StatelessWidget {
  const CarsScreen();
  @override
  Widget build(BuildContext context) => _Simple('سياراتي', [
        CardBox(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 150, child: Illus('car_silver', fallback: Icons.directions_car_rounded)),
            const SizedBox(height: 10),
            const Row(children: [Expanded(child: Text('كيا ريو 2015 · فضي', style: T.h3)), Badge2('الافتراضية')]),
          ]),
        ),
        const SizedBox(height: 12),
        CardBox(onTap: () => toast(context, 'قريباً'), child: const Center(child: Padding(padding: EdgeInsets.all(14), child: Text('+ ضيف سيارة', style: TextStyle(fontFamily: kFont, color: C.primary, fontSize: 16))))),
      ]);
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen();
  @override
  Widget build(BuildContext context) => _Simple('سجل الرحلات', [
        for (final (a, b, d, s) in const [('جبلة', 'حمص', 'الأحد · كراكب', 'انتهت'), ('اللاذقية', 'دمشق', 'الجمعة · كسائق', 'انتهت'), ('طرطوس', 'حلب', 'الإثنين · كراكب', 'ملغاة')])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CardBox(
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$a ← $b', style: T.label), Text(d, style: T.small)])),
                Badge2(s, bg: s == 'ملغاة' ? C.dangerBg : C.line, fg: s == 'ملغاة' ? C.danger : C.muted2),
              ]),
            ),
          ),
      ]);
}

class VerifyScreen extends StatefulWidget {
  const VerifyScreen();
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  int _done = 1;
  @override
  Widget build(BuildContext context) => _Simple('وثّق هويتك', [
        const Floaty(child: Illus('id_scan', height: 200)),
        const Text('التوثيق بيعطي ثقة أكبر، وصورة الهوية ما بتنعرض لحدا.', style: T.body),
        const SizedBox(height: 14),
        Group([
          for (final (i, t) in const [(0, 'رقم الموبايل'), (1, 'صورة الهوية'), (2, 'صورة سيلفي')])
            RowItem(i < _done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, t, sub: i < _done ? 'تم ✓' : 'اضغط للبدء', onTap: () => setState(() => _done = i + 1 > _done ? i + 1 : _done)),
        ]),
      ], bottom: Btn(_done >= 3 ? 'تم الإرسال للمراجعة' : 'التالي', onTap: () {
        if (_done >= 3) {
          Navigator.pop(context);
          toast(context, 'عم نراجع هويتك، بتاخد أقل من 24 ساعة');
        } else {
          setState(() => _done++);
        }
      }));
}

class SafetyScreen extends StatelessWidget {
  const SafetyScreen();
  @override
  Widget build(BuildContext context) => _Simple('مركز الأمان', [
        const SizedBox(height: 190, child: Floaty(child: Illus('safety_shield'))),
        const SizedBox(height: 12),
        CardBox(
          color: C.dangerBg,
          onTap: () => go(context, const SosScreen()),
          child: const Row(children: [Icon(Icons.sos_rounded, color: C.danger, size: 30), SizedBox(width: 12), Expanded(child: Text('زر الطوارئ', style: TextStyle(fontFamily: kFont, color: C.danger, fontSize: 17))), Icon(Icons.chevron_left_rounded, color: C.danger)]),
        ),
        const SizedBox(height: 12),
        for (final (i, t, s) in const [
          (Icons.person_search_rounded, 'تأكد من السائق والسيارة', 'طابق الاسم والصورة ولون السيارة قبل ما تطلع.'),
          (Icons.family_restroom_rounded, 'رحلات نسائية وعائلية', 'الراكبات بيسافروا مع سائقات، أو ضمن عائلتها.'),
          (Icons.share_location_rounded, 'شارك رحلتك', 'خلي أهلك يتابعوا موقعك لحد ما توصل.'),
          (Icons.payments_outlined, 'الدفع بعد اللقاء', 'لا تحوّل أي مبلغ قبل ما تلتقي بالسائق.'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CardBox(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(i, color: C.primary), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: T.label), Text(s, style: T.small)]))])),
          ),
      ]);
}

class SosScreen extends StatefulWidget {
  const SosScreen();
  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.sos,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Align(alignment: AlignmentDirectional.centerStart, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30))),
              const Spacer(),
              SizedBox(
                width: 240,
                height: 240,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => Stack(alignment: Alignment.center, children: [
                    for (final off in [0.0, .5])
                      Transform.scale(
                        scale: 1 + ((_c.value + off) % 1) * .9,
                        child: Opacity(opacity: (1 - (_c.value + off) % 1) * .4, child: Container(width: 150, height: 150, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
                      ),
                    GestureDetector(
                      onLongPress: () => toast(context, 'تم إرسال تنبيه الطوارئ وموقعك لجهات اتصالك'),
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('SOS', style: TextStyle(fontFamily: kFont, fontSize: 40, color: C.sos)), Text('اضغط مطوّلاً', style: TextStyle(fontFamily: kFont, color: C.sos))]),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              const Text('بحاجة مساعدة؟', style: TextStyle(fontFamily: kFont, fontSize: 34, color: Colors.white)),
              const Text('رح نتصل بالطوارئ ونبعت موقعك وتفاصيل الرحلة لجهات اتصالك.', textAlign: TextAlign.center, style: TextStyle(fontFamily: kFont, fontSize: 15, color: Colors.white)),
              const Spacer(),
              Row(children: [
                Expanded(child: Btn('الطوارئ 112', kind: BtnKind.dark, icon: Icons.call_rounded, onTap: () => toast(context, 'جاري الاتصال...'))),
                const SizedBox(width: 10),
                Expanded(child: Btn('بلّغ أهلي', kind: BtnKind.white, onTap: () => toast(context, 'انبعت لأهلك'))),
              ]),
            ]),
          ),
        ),
      );
}

class ReportScreen extends StatefulWidget {
  final Person target;
  final String? tripId;
  const ReportScreen(this.target, {this.tripId});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _r = 0;
  final _details = TextEditingController();
  static const _reasons = ['ما إجا عالموعد', 'سواقة خطرة', 'تصرف غير لائق', 'طلب مصاري زيادة', 'حساب وهمي'];
  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Simple('بلاغ عن ${widget.target.name}', [
        const Text('بلاغك سري، وما رح نقول للعضو مين بلّغ. بعد بلاغين من شخصين مختلفين، السائق بيتوقف لحتى نراجع.', style: T.body),
        const SizedBox(height: 12),
        ChoiceCards(options: [for (final r in _reasons) (r, '')], selected: {_r}, onTap: (i) => setState(() => _r = i)),
        TextField(controller: _details, maxLines: 3, maxLength: 1000, style: const TextStyle(fontFamily: kFont), decoration: const InputDecoration(hintText: 'خبرنا شو صار (اختياري)')),
      ], bottom: AsyncBtn('إرسال البلاغ', kind: BtnKind.dark, onTap: () async {
        await Store.i.report(widget.target.id, _reasons[_r], tripId: widget.tripId, details: _details.text);
        if (!context.mounted) return;
        toast(context, 'وصلنا بلاغك، رح نتابعو');
        Navigator.pop(context);
      }));
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen();
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _n = [true, true, true, false];
  @override
  Widget build(BuildContext context) => _Simple('الإعدادات', [
        Container(height: 150, alignment: Alignment.center, child: const Illus('settings', height: 150)),
        Group(title: 'الإشعارات', [
          for (final (i, t) in const [(0, 'طلبات الحجز'), (1, 'الرسائل'), (2, 'تذكير قبل الرحلة'), (3, 'عروض وأخبار')])
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _n[i], activeColor: C.primary, title: Text(t, style: T.label), onChanged: (v) => setState(() => _n[i] = v)),
        ]),
        const SizedBox(height: 12),
        Group(title: 'الحساب', [
          RowItem(Icons.language_rounded, 'اللغة', sub: 'العربية', onTap: () => toast(context, 'قريباً: English')),
          RowItem(Icons.lock_outline_rounded, 'سياسة الخصوصية', onTap: () => go(context, const PrivacyPolicyScreen())),
          RowItem(Icons.description_outlined, 'الشروط والأحكام', onTap: () => go(context, const TermsScreen())),
          RowItem(Icons.info_outline_rounded, 'عن مشوار', sub: 'الإصدار 1.0.0', onTap: () => go(context, const AboutScreen())),
        ]),
        const SizedBox(height: 12),
        Group([
          RowItem(Icons.logout_rounded, 'تسجيل الخروج', danger: true, onTap: () async {
            await Store.i.signOut();
            if (context.mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SplashScreen()), (_) => false);
          }),
          RowItem(Icons.delete_outline_rounded, 'حذف الحساب', danger: true, onTap: () => _confirmDelete(context)),
        ]),
      ]);

  void _confirmDelete(BuildContext context) => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('حذف الحساب؟', style: TextStyle(fontFamily: kFont)),
          content: const Text('رح تنحذف رحلاتك وتقييماتك ورسائلك بشكل نهائي.', style: TextStyle(fontFamily: kFont)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('تراجع', style: TextStyle(fontFamily: kFont))),
            TextButton(onPressed: () async {
              // حذف الحساب بيتم من الدعم حالياً (لازم نلغي الحجوزات ونحذف الأوراق بأمان)
              Navigator.pop(context);
              toast(context, 'وصلنا طلب حذف الحساب، رح نتواصل معك خلال 48 ساعة');
            }, child: const Text('حذف', style: TextStyle(fontFamily: kFont, color: C.danger))),
          ],
        ),
      );
}

class _LegalScreen extends StatelessWidget {
  final String title, image;
  final List<(String, String)> sections;
  const _LegalScreen(this.title, this.image, this.sections);
  @override
  Widget build(BuildContext context) => _Simple(title, [
        Center(child: Illus(image, height: 160)),
        const Text('آخر تحديث: [التاريخ]', style: T.small),
        const SizedBox(height: 12),
        for (final (h, b) in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(h, style: T.h3), const SizedBox(height: 4), Text(b, style: T.body)]),
          ),
      ], bg: Colors.white);
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen();
  @override
  Widget build(BuildContext context) => const _LegalScreen('سياسة الخصوصية', 'privacy', [
        ('شو المعلومات اللي منجمعها', 'الاسم، رقم الموبايل، الصورة، الجنس، ومعلومات رحلاتك. وموقعك أثناء الرحلة فقط إذا فعّلت المشاركة.'),
        ('ليش منستخدمها', 'لربطك برحلات مناسبة، لعرض الرحلات النسائية والعائلية بشكل صحيح، ولأمان الأعضاء.'),
        ('مين بيشوف رقمك', 'رقمك ما بيظهر إلا للسائق أو الراكب بعد قبول الحجز، وبيختفي بعد الرحلة بـ 24 ساعة.'),
        ('صورة الهوية', 'بنستخدمها للتوثيق فقط، وما بتنعرض لأي عضو.'),
        ('حذف بياناتك', 'فيك تحذف حسابك وكل بياناتك من الإعدادات بأي وقت.'),
        ('تواصل معنا', '[إيميل الدعم]'),
      ]);
}

class TermsScreen extends StatelessWidget {
  const TermsScreen();
  @override
  Widget build(BuildContext context) => const _LegalScreen('الشروط والأحكام', 'terms', [
        ('1. شو هو مشوار', 'منصة بتربط بين سائقين عندهن مقاعد فاضية وركاب رايحين على نفس الطريق، لتقسيم مصروف الرحلة.'),
        ('2. الاحترام والآداب', 'الالتزام بالآداب العامة والاحترام المتبادل. الرحلات النسائية للنساء فقط، وسفر المرأة مع سائق رجل بيكون ضمن عائلتها.'),
        ('3. الأسعار والدفع', 'السعر لتقسيم المصروف فقط وليس للربح. الدفع كاش بين الراكب والسائق.'),
        ('4. الإلغاء', 'الإلغاءات المتكررة أو المتأخرة بتأثر على تقييم العضو.'),
        ('5. المسؤولية', '[يُستكمل النص القانوني]'),
      ]);
}

class HelpScreen extends StatelessWidget {
  const HelpScreen();
  @override
  Widget build(BuildContext context) => _Simple('المساعدة', [
        const Center(child: Illus('help', height: 160)),
        const TextField(style: TextStyle(fontFamily: kFont), decoration: InputDecoration(hintText: 'دوّر على سؤال', prefixIcon: Icon(Icons.search_rounded, color: C.primary))),
        const SizedBox(height: 12),
        for (final (q, a) in const [
          ('كيف بدفع للسائق؟', 'كاش مباشرة للسائق. لا تحوّل أي مبلغ قبل اللقاء.'),
          ('شو بصير إذا السائق ألغى؟', 'بيوصلك إشعار فوراً، ومنقترح عليك رحلات بديلة.'),
          ('كيف بوثّق هويتي؟', 'من حسابي ← وثّق هويتك، بتصوّر الهوية وسيلفي.'),
          ('كيف بتشتغل الرحلات النسائية؟', 'السائقة امرأة موثّقة والركاب نساء فقط، والرحلات العائلية.'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(title: Text(q, style: T.label), childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14), children: [Text(a, style: T.body)]),
              ),
            ),
          ),
      ], bottom: Btn('تواصل مع الدعم', kind: BtnKind.outline, icon: Icons.chat_bubble_outline_rounded, onTap: () => toast(context, 'فريق الدعم رح يتواصل معك قريباً')));
}

class InviteScreen extends StatelessWidget {
  const InviteScreen();
  @override
  Widget build(BuildContext context) => _Simple('ادعُ أصحابك', [
        const Floaty(child: Illus('invite_gift', height: 220)),
        const Text('كل ما زاد الأعضاء، زادت الرحلات', style: T.h2),
        const Text('شارك مشوار مع أصحابك، ولما يعملوا أول رحلة بتاخد شارة "سفير مشوار".', style: T.body),
        const SizedBox(height: 16),
        CardBox(child: Row(children: [const Expanded(child: Text('IHAB-2026', textDirection: TextDirection.ltr, style: TextStyle(fontFamily: kFont, fontSize: 22, letterSpacing: 2))), TextButton(onPressed: () => toast(context, 'انتسخ الكود'), child: const Text('نسخ', style: TextStyle(fontFamily: kFont)))])),
      ], bottom: Btn('شارك الدعوة', icon: Icons.share_rounded, onTap: () => toast(context, 'قريباً')));
}

class PlusScreen extends StatelessWidget {
  const PlusScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.dark,
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Align(alignment: AlignmentDirectional.centerStart, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white))),
            const Floaty(child: Illus('plus_crown', height: 180)),
            const Center(child: Text('مشوار بلس', style: TextStyle(fontFamily: kFont, fontSize: 42, color: Colors.white))),
            const Center(child: Text('للسائقين اللي بيسافروا كتير · قريباً', style: TextStyle(fontFamily: kFont, color: C.tint))),
            const SizedBox(height: 20),
            for (final (i, t) in const [(Icons.bolt_rounded, 'رحلاتك بأول نتائج البحث'), (Icons.repeat_rounded, 'رحلات متكررة بضغطة'), (Icons.star_rounded, 'شارة سائق مميز'), (Icons.insights_rounded, 'تقارير شهرية')])
              Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(children: [Icon(i, color: C.yellow), const SizedBox(width: 12), Text(t, style: const TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 16))])),
            const SizedBox(height: 10),
            Press(
              onTap: () {
                toast(context, 'رح نبلّغك لما ينطلق');
                Navigator.pop(context);
              },
              child: Container(height: 56, decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(18)), alignment: Alignment.center, child: const Text('بلّغني لما ينطلق', style: TextStyle(fontFamily: kFont, color: C.dark, fontSize: 17))),
            ),
          ]),
        ),
      );
}

class AboutScreen extends StatelessWidget {
  const AboutScreen();
  @override
  Widget build(BuildContext context) => _Simple('', [
        const SizedBox(height: 20),
        Center(child: Container(width: 96, height: 96, decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(32)), child: const Icon(Icons.route_rounded, color: Colors.white, size: 54))),
        const SizedBox(height: 10),
        const Center(child: Text('مشوار', style: TextStyle(fontFamily: kFont, fontSize: 52, color: C.primary))),
        const Center(child: Text('الإصدار 1.0.0', style: T.small)),
        const SizedBox(height: 12),
        const Text('تطبيق سوري لمشاركة الرحلات بين المدن. هدفنا نخفف مصروف السفر ونقرّب الناس من بعض، بطابع يحترم قيمنا.', textAlign: TextAlign.center, style: T.body),
        const SizedBox(height: 20),
        Group([
          RowItem(Icons.star_outline_rounded, 'قيّمنا', onTap: () => toast(context, 'شكراً إلك')),
          RowItem(Icons.share_outlined, 'شارك التطبيق', onTap: () => go(context, const InviteScreen())),
        ]),
      ]);
}

class OfflineScreen extends StatelessWidget {
  const OfflineScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: EmptyState(image: 'offline', title: 'ما في إنترنت', body: 'تأكد من الاتصال وجرّب مرة تانية. رحلاتك المحجوزة متاحة بدون نت.', actions: [Btn('جرّب مرة تانية', onTap: () => Navigator.pop(context))]),
        ),
      );
}

// ignore: unused_element
Person get currentUser => me;
