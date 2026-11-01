import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';
import '../data/mock.dart';
import '../data/store.dart';
import '../widgets/common.dart';
import 'publish.dart' show PublishFlow;

/// شروط الانضمام كسائق، بتنعرض بأكتر من مكان.
const driverRequirements = [
  (Icons.badge_outlined, 'هوية شخصية سارية', 'صورة الوجهين، ومعها صورة إلك ماسك الهوية'),
  (Icons.credit_card_rounded, 'شهادة سواقة', 'عمومية أو خصوصية، صار عمرها سنتين أو أكتر'),
  (Icons.gavel_rounded, 'لا حكم عليه', 'ورقة جديدة، عمرها أقل من 3 شهور'),
  (Icons.directions_car_outlined, 'أوراق السيارة', 'الميكانيك والتأمين، والسيارة باسمك أو معك وكالة'),
  (Icons.handshake_outlined, 'مقابلة وفحص سيارة', 'ربع ساعة بنقطة مشوار بمدينتك'),
];

/// ليش الراكب بيرتاح: كيف منوثّق السائقين.
class HowWeVerifyScreen extends StatelessWidget {
  const HowWeVerifyScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(title: 'كيف منوثّق السائقين'),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(24)),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.verified_rounded, color: C.yellow, size: 36),
              SizedBox(height: 8),
              Text('ما حدا بيسوق بمشوار قبل ما نتعرّف عليه', style: TextStyle(fontFamily: kFont, fontSize: 22, color: Colors.white, height: 1.4)),
              SizedBox(height: 4),
              Text('كل سائق بيمرق بخمس خطوات، وإذا خالف القواعد بينوقف.', style: TextStyle(fontFamily: kFont, color: C.tint)),
            ]),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < driverRequirements.length; i++)
            Enter(
              delay: i * 70,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CardBox(
                  child: Row(children: [
                    Container(width: 34, height: 34, alignment: Alignment.center, decoration: const BoxDecoration(color: C.primary, shape: BoxShape.circle), child: Text('${i + 1}', style: const TextStyle(fontFamily: kFont, color: Colors.white))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(driverRequirements[i].$2, style: T.label), Text(driverRequirements[i].$3, style: T.small)])),
                    Icon(driverRequirements[i].$1, color: C.primary),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text('وأثناء الرحلة', style: T.h3),
          const SizedBox(height: 8),
          Group([
            const RowItem(Icons.pin_outlined, 'رمز الرحلة', sub: 'رمز من 4 أرقام، بتتأكد منو مع السائق قبل ما تطلع'),
            const RowItem(Icons.confirmation_number_outlined, 'رقم السيارة ولونها', sub: 'بتشوفهن بتذكرتك قبل الموعد'),
            const RowItem(Icons.share_location_rounded, 'مشاركة الموقع', sub: 'أهلك بيعرفوا وينك ووقت وصولك'),
            const RowItem(Icons.sos_rounded, 'زر طوارئ', sub: 'اتصال سريع ورسالة لأهلك بموقعك'),
            const RowItem(Icons.flag_outlined, 'بلاغ بثانية', sub: 'بعد بلاغين، السائق بيتوقف لحتى نراجع'),
          ]),
          const SizedBox(height: 12),
          const InfoNote('الرحلات النسائية بتسوقها سائقات موثّقات بس.', icon: Icons.shield_outlined),
        ]),
      );
}

/// صفحة "صير سائق معنا" (بتنعرض بتاب النشر لمين مو سائق).
class DriverJoinIntro extends StatelessWidget {
  const DriverJoinIntro();
  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Enter(child: Text('صير سائق موثّق', style: T.h1)),
          const Enter(delay: 80, child: Text('بمشوار بس السائقين الموثّقين بينشروا رحلات. هيك الركاب بيرتاحوا، وانت بتنحجز أسرع.', style: T.body)),
          const SizedBox(height: 12),
          const SizedBox(height: 190, child: Floaty(child: Illus('onboard2', fit: BoxFit.contain))),
          const SizedBox(height: 12),
          Row(children: [
            for (final (a, b) in const [('وقت التقديم', '10 دقايق'), ('المراجعة', 'يوم أو يومين'), ('الرسوم', 'بلا رسوم')])
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [Text(b, style: const TextStyle(fontFamily: kFont, fontSize: 16, color: C.primary)), Text(a, style: T.small)]),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          const Text('شو بدك تجهّز', style: T.h3),
          const SizedBox(height: 8),
          for (final (i, t, s) in driverRequirements)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(12)), child: Icon(i, color: C.primary, size: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: T.label), Text(s, style: T.small)])),
              ]),
            ),
          const SizedBox(height: 10),
          Btn('قدّم طلبك', icon: Icons.arrow_back_rounded, onTap: () => go(context, const DriverApplyFlow())),
          const SizedBox(height: 6),
          Btn('كيف منوثّق السائقين؟', kind: BtnKind.ghost, onTap: () => go(context, const HowWeVerifyScreen())),
        ]),
      );
}

/// طلب الانضمام: 5 خطوات.
class DriverApplyFlow extends StatefulWidget {
  const DriverApplyFlow();
  @override
  State<DriverApplyFlow> createState() => _DriverApplyFlowState();
}

class _DriverApplyFlowState extends State<DriverApplyFlow> {
  final _pc = PageController();
  final _a = DriverApp()..name = Store.i.name;
  final _picker = ImagePicker();
  int _step = 0;
  bool _agree = false;
  static const _total = 5;
  static const _titles = ['معلوماتك', 'أوراقك', 'سيارتك', 'موعد المقابلة', 'التعهد والإرسال'];

  static const _personalDocs = [('selfie', 'صورتك ماسك الهوية'), ('id_front', 'الهوية · الوجه الأمامي'), ('id_back', 'الهوية · الوجه الخلفي'), ('license', 'شهادة السواقة'), ('record', 'لا حكم عليه')];
  static const _carDocs = [('car_front', 'السيارة من قدّام'), ('car_side', 'السيارة من الجنب'), ('car_inside', 'السيارة من جوا'), ('mechanic', 'الميكانيك')];

  String? _missing() {
    switch (_step) {
      case 0:
        if (_a.name.trim().length < 3) return 'اكتب اسمك الكامل';
        if (_a.phone.replaceAll(RegExp(r'\D'), '').length < 9) return 'اكتب رقم موبايل صحيح';
        if (_a.city.isEmpty) return 'اختار مدينتك';
      case 1:
        for (final (k, l) in _personalDocs) {
          if (!_a.docs.containsKey(k)) return 'ناقصك: $l';
        }
      case 2:
        if (_a.car.trim().isEmpty || _a.year.trim().isEmpty || _a.color.trim().isEmpty) return 'عبّي معلومات السيارة';
        if (_a.plate.trim().length < 4) return 'اكتب رقم السيارة';
        final y = int.tryParse(_a.year.trim());
        if (y == null || y < 2005 || y > DateTime.now().year + 1) return 'موديل السيارة لازم يكون 2005 وطالع';
        for (final (k, l) in _carDocs) {
          if (!_a.docs.containsKey(k)) return 'ناقصك: $l';
        }
      case 3:
        if (_a.slot.isEmpty) return 'اختار موعد المقابلة';
      case 4:
        if (!_agree) return 'لازم توافق على قواعد مشوار';
    }
    return null;
  }

  void _next() {
    final m = _missing();
    if (m != null) {
      toast(context, m);
      return;
    }
    FocusScope.of(context).unfocus();
    if (_step == _total - 1) {
      Store.i.submitApplication(_a);
      goReplace(context, const DriverStatusScreen(justSent: true));
      return;
    }
    setState(() => _step++);
    _pc.animateToPage(_step, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _step--);
    _pc.animateToPage(_step, duration: const Duration(milliseconds: 340), curve: Curves.easeOutCubic);
  }

  Future<void> _pick(String key) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            RowItem(Icons.photo_camera_outlined, 'صوّر هلق', onTap: () => Navigator.pop(context, ImageSource.camera)),
            RowItem(Icons.photo_library_outlined, 'اختار من الصور', onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ]),
        ),
      ),
    );
    if (src == null) return;
    try {
      final f = await _picker.pickImage(source: src, maxWidth: 1600, imageQuality: 80);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (mounted) setState(() => _a.docs[key] = bytes);
    } catch (_) {
      if (mounted) toast(context, 'ما قدرنا نفتح الكاميرا أو الصور');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _step == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(children: [
                  SquareBtn(Icons.arrow_forward_rounded, tooltip: 'رجوع', onTap: _back),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${_titles[_step]} · ${_step + 1} من $_total', style: T.small)),
                ]),
              ),
              StepBar(_step + 1, _total),
              Expanded(
                child: PageView(controller: _pc, physics: const NeverScrollableScrollPhysics(), children: [
                  _page('عرّفنا عليك', 'نفس المعلومات اللي على هويتك.', [
                    _text('الاسم الكامل', _a.name, (v) => _a.name = v),
                    _text('رقم الموبايل', _a.phone, (v) => _a.phone = v, hint: '09XX XXX XXX', phone: true),
                    const Text('مدينتك', style: T.label),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final c in cities.take(8))
                        ChoiceChip(
                          label: Text(c.name, style: TextStyle(fontFamily: kFont, color: _a.city == c.name ? Colors.white : C.dark)),
                          selected: _a.city == c.name,
                          selectedColor: C.primary,
                          backgroundColor: Colors.white,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _a.city = c.name),
                        ),
                    ]),
                  ]),
                  _page('صوّر أوراقك', 'صور واضحة بضو منيح، بلا قص. الأوراق بتنحفظ مشفّرة وبتشوفها لجنة التوثيق بس.', [
                    for (final (k, l) in _personalDocs) _doc(k, l),
                  ]),
                  _page('سيارتك', 'السيارة اللي رح تسافر فيها.', [
                    Row(children: [
                      Expanded(flex: 2, child: _text('النوع والموديل', _a.car, (v) => _a.car = v, hint: 'كيا ريو')),
                      const SizedBox(width: 10),
                      Expanded(child: _text('سنة الصنع', _a.year, (v) => _a.year = v, hint: '2015', phone: true)),
                    ]),
                    Row(children: [
                      Expanded(child: _text('اللون', _a.color, (v) => _a.color = v, hint: 'فضي')),
                      const SizedBox(width: 10),
                      Expanded(flex: 2, child: _text('رقم السيارة', _a.plate, (v) => _a.plate = v, hint: 'اللاذقية 123456')),
                    ]),
                    for (final (k, l) in _carDocs) _doc(k, l),
                  ]),
                  _page('موعد المقابلة', 'ربع ساعة منتعرّف فيها عليك ومنفحص السيارة. جيب الأوراق الأصلية معك.', [
                    CardBox(
                      child: Row(children: [
                        const Icon(Icons.place_rounded, color: C.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text('نقطة مشوار · ${_a.city.isEmpty ? 'مدينتك' : _a.city}\n${_a.city.isEmpty ? '' : cities.firstWhere((c) => c.name == _a.city).sub.split(' · ').first}', style: T.label)),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    const Text('اليوم', style: T.label),
                    const SizedBox(height: 8),
                    Row(children: [
                      for (final d in const [1, 2, 3])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Press(
                              onTap: () => setState(() => _a.day = d),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: 58,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: _a.day == d ? C.primary : Colors.white, borderRadius: BorderRadius.circular(16)),
                                child: Text(dayLabel(d), textAlign: TextAlign.center, style: TextStyle(fontFamily: kFont, fontSize: 13, color: _a.day == d ? Colors.white : C.dark)),
                              ),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 14),
                    const Text('الساعة', style: T.label),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final s in const ['10:00', '11:30', '13:00', '16:00', '17:30'])
                        ChoiceChip(
                          label: Text(s, style: TextStyle(fontFamily: kFont, color: _a.slot == s ? Colors.white : C.dark)),
                          selected: _a.slot == s,
                          selectedColor: C.primary,
                          backgroundColor: Colors.white,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _a.slot = s),
                        ),
                    ]),
                  ]),
                  _page('قواعد مشوار', 'كل سائق بيوقّع عليها.', [
                    for (final r in const [
                      'بحترم الركاب وخصوصيتن، وما بطلب أرقامن خارج التطبيق.',
                      'بسوق بأمان وبلتزم بالسرعة المسموحة.',
                      'بلتزم بالموعد والمسار والسعر المنشور.',
                      'ما بدخّن بالسيارة إذا الرحلة ممنوع فيها التدخين.',
                      'الرحلات النسائية للسائقات بس.',
                      'بفهم إنو أي بلاغ صحيح ممكن يوقّف حسابي.',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.check_circle_rounded, color: C.primary, size: 18)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(r, style: T.body)),
                        ]),
                      ),
                    const SizedBox(height: 6),
                    CardBox(
                      onTap: () => setState(() => _agree = !_agree),
                      child: Row(children: [
                        Checkbox(value: _agree, activeColor: C.primary, onChanged: (v) => setState(() => _agree = v ?? false)),
                        const Expanded(child: Text('قرأت القواعد وموافق عليها', style: T.label)),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    CardBox(
                      color: C.tint,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('ملخص طلبك', style: T.label),
                        const SizedBox(height: 6),
                        Text('${_a.name} · ${_a.city}\n${_a.car} ${_a.year} · ${_a.color} · ${_a.plate}\nالمقابلة: ${dayLabel(_a.day)} الساعة ${_a.slot}\n${_a.docs.length} صور مرفوعة', style: T.body),
                      ]),
                    ),
                  ]),
                ]),
              ),
              Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: Btn(_step == _total - 1 ? 'أرسل الطلب' : 'متابعة', icon: _step == _total - 1 ? Icons.send_rounded : null, onTap: _next)),
            ]),
          ),
        ),
      );

  Widget _page(String title, String sub, List<Widget> children) => ListView(padding: const EdgeInsets.all(20), children: [
        Enter(child: Text(title, style: T.h1)),
        Text(sub, style: T.body),
        const SizedBox(height: 16),
        ...children,
      ]);

  Widget _text(String label, String value, ValueChanged<String> on, {String? hint, bool phone = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: T.label),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: value,
            onChanged: on,
            keyboardType: phone ? TextInputType.phone : TextInputType.text,
            style: const TextStyle(fontFamily: kFont, fontSize: 16),
            decoration: InputDecoration(hintText: hint),
          ),
        ]),
      );

  Widget _doc(String key, String label) {
    final Uint8List? b = _a.docs[key];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Press(
        onTap: () => _pick(key),
        child: Container(
          height: 76,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: b != null ? C.primary : C.border, width: 1.5)),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 56,
                height: 56,
                color: C.tint,
                child: b != null ? Image.memory(b, fit: BoxFit.cover) : const Icon(Icons.add_a_photo_outlined, color: C.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(label, style: T.label), Text(b != null ? 'تمام ✓ · اضغط لتغيّرها' : 'اضغط لتصوّر', style: T.small)])),
            Icon(b != null ? Icons.check_circle_rounded : Icons.chevron_left_rounded, color: b != null ? C.primary : C.muted),
          ]),
        ),
      ),
    );
  }
}

/// متابعة حالة طلب السائق.
class DriverStatusScreen extends StatelessWidget {
  final bool justSent;
  const DriverStatusScreen({this.justSent = false});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: TopBar(title: 'طلب السائق', close: justSent),
        body: const DriverStatusBody(),
      );
}

class DriverStatusBody extends StatelessWidget {
  const DriverStatusBody();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) {
          final s = Store.i.driverStatus;
          final a = Store.i.app;
          final idx = switch (s) { DStatus.none => 0, DStatus.reviewing => 1, DStatus.interview => 2, DStatus.approved => 4 };
          final steps = [
            ('انبعت الطلب', a == null ? '' : '${a.docs.length} صور · ${a.car} ${a.year}'),
            ('مراجعة الأوراق', 'عادةً خلال يوم أو يومين'),
            ('المقابلة وفحص السيارة', a == null ? '' : '${dayLabel(a.day)} الساعة ${a.slot} · نقطة مشوار ${a.city}'),
            ('التفعيل', 'بتاخد شارة سائق موثّق وبتنشر رحلاتك'),
          ];
          return ListView(padding: const EdgeInsets.all(20), children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: s == DStatus.approved ? const Color(0xFF1E9E5A) : C.dark, borderRadius: BorderRadius.circular(24)),
              child: Row(children: [
                Icon(s == DStatus.approved ? Icons.verified_rounded : Icons.hourglass_top_rounded, color: C.yellow, size: 38),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      switch (s) { DStatus.reviewing => 'عم نراجع أوراقك', DStatus.interview => 'موعد مقابلتك جاهز', DStatus.approved => 'صرت سائق موثّق!', DStatus.none => 'ما في طلب' },
                      style: const TextStyle(fontFamily: kFont, fontSize: 22, color: Colors.white),
                    ),
                    Text(
                      switch (s) { DStatus.reviewing => 'رح يوصلك إشعار أول ما نخلص', DStatus.interview => 'جيب الهوية وشهادة السواقة والميكانيك الأصليين', DStatus.approved => 'فيك هلق تنشر رحلتك الأولى', DStatus.none => '' },
                      style: const TextStyle(fontFamily: kFont, color: C.tint),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < steps.length; i++)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < idx || s == DStatus.approved ? C.primary : (i == idx ? C.yellow : Colors.white),
                      border: Border.all(color: i <= idx ? Colors.transparent : C.border, width: 2),
                    ),
                    child: Icon(i < idx || s == DStatus.approved ? Icons.check_rounded : (i == idx ? Icons.more_horiz_rounded : null), size: 18, color: i < idx || s == DStatus.approved ? Colors.white : C.dark),
                  ),
                  if (i < steps.length - 1) Container(width: 2, height: 46, color: i < idx ? C.primary : C.border),
                ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(steps[i].$1, style: TextStyle(fontFamily: kFont, fontSize: 16, color: i <= idx ? C.dark : C.muted)),
                      if (steps[i].$2.isNotEmpty) Text(steps[i].$2, style: T.small),
                    ]),
                  ),
                ),
              ]),
            const SizedBox(height: 16),
            if (s == DStatus.approved)
              Btn('انشر رحلتك الأولى', icon: Icons.add_rounded, onTap: () => go(context, const PublishFlow())),
            if (s == DStatus.interview) ...[
              const InfoNote('هي نسخة تجريبية: اكبس الزر لتجرّب شو بيصير بعد المقابلة.', icon: Icons.science_outlined),
              const SizedBox(height: 10),
              Btn('حضرت المقابلة (تجريبي)', kind: BtnKind.dark, onTap: () {
                Store.i.finishInterview();
                toast(context, 'عم نفعّل حسابك...');
              }),
            ],
            if (s == DStatus.reviewing || s == DStatus.interview) ...[
              const SizedBox(height: 8),
              Btn('إلغاء الطلب', kind: BtnKind.ghost, onTap: () {
                Store.i.cancelApplication();
                Navigator.of(context).maybePop();
              }),
            ],
          ]);
        },
      );
}
