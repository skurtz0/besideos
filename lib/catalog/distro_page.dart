import '../l10n/l10n.dart';
import '../l10n/text.dart';
import 'package:flutter/material.dart' hide Text;

import '../brand.dart';
import '../site_mode.dart';
import '../install/install_controller.dart';
import '../install/install_section.dart';
import '../theme.dart';
import 'distro.dart';
import 'screenshot_view.dart';
import 'support_matrix.dart';

const _hostNames = {
  Host.windows: 'Windows',
  Host.linux: 'Linux',
};

class DistroPage extends StatefulWidget {
  const DistroPage({super.key, required this.distro, this.installFactory});
  final Distro distro;

  /// Test hook: supplies the installer controller instead of locating the real engine.
  final InstallController? Function()? installFactory;

  @override
  State<DistroPage> createState() => _DistroPageState();
}

class _DistroPageState extends State<DistroPage> {
  String? _variantId;

  @override
  Widget build(BuildContext context) {
    final d = widget.distro;
    final vs = d.variants;
    final v = vs.isEmpty ? null : vs.firstWhere((x) => x.id == _variantId, orElse: () => vs.first);
    return _DistroBody(
      distro: v == null ? d : d.withVariant(v),
      installFactory: widget.installFactory,
      sectionKey: ValueKey('${d.id}/${v?.id}'),
      picker: vs.length < 2
          ? null
          : _VariantPicker(variants: vs, selected: v!.id, onPick: (id) => setState(() => _variantId = id)),
    );
  }
}

/// "Which one do you want?" for distros with several editions (desktop, live, GPU...).
class _VariantPicker extends StatelessWidget {
  const _VariantPicker({required this.variants, required this.selected, required this.onPick});
  final List<DistroVariant> variants;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Hangisini istersin?', icon: Icons.tune_rounded),
        const Text('Birini seç. Emin değilsen ilkini seçebilirsin.',
            style: TextStyle(color: kMuted, height: 1.5)),
        const SizedBox(height: 12),
        for (final v in variants)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: v.id == selected ? kAccent.withAlpha(30) : kPanel2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: v.id == selected ? kAccent : const Color(0x14FFFFFF), width: v.id == selected ? 2 : 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: v.id == selected ? null : () => onPick(v.id),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(v.id == selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                        color: v.id == selected ? kAccent : kMuted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(v.label, style: const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(v.note, style: const TextStyle(color: kMuted, height: 1.4)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _DistroBody extends StatelessWidget {
  const _DistroBody({required this.distro, this.installFactory, this.picker, this.sectionKey});
  final Distro distro;
  final InstallController? Function()? installFactory;
  final Widget? picker;
  final Key? sectionKey;

  @override
  Widget build(BuildContext context) {
    final d = distro;
    final accent = Color(d.accent);
    // The public website only presents the system and sends people to the app; manual steps and ISO tools stay in the app.
    final web = SiteMode.isWeb(context);
    final installable = [
      for (final h in Host.values)
        if (_ok(h, d)) _hostNames[h]!,
    ];
    return Scaffold(
      backgroundColor: kBg,
      appBar: SiteBar(
        maxWidth: 920,
        padding: 20,
        page: d.name,
        leading: Navigator.canPop(context)
            ? const BackButton()
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: tr('Dağıtımlar'),
                onPressed: () => Navigator.pushReplacementNamed(context, '/distros'),
              ),
      ),
      body: PageScroll(
        maxWidth: 920,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _hero(d, accent),
              if (picker != null) ...[
                const SizedBox(height: 16),
                picker!,
              ],
              const SizedBox(height: 16),
              // Every system can be installed with one click in the app (official download or the person's own ISO);
              // the website sends people to the app instead.
              if (!web && installerSupported())
                InstallSection(key: sectionKey, distro: d, controllerFactory: installFactory)
              else
                _DesktopOnlyNote(web: web),
              const SizedBox(height: 16),
              _card(Icons.lightbulb_outline_rounded, 'Bu sistem nedir?', [
                Text(d.description, style: const TextStyle(color: kText, height: 1.6)),
                const SizedBox(height: 10),
                Text(tr('Kimler için: {text}', {'text': tr(d.bestFor)}), style: const TextStyle(color: kMuted, height: 1.5)),
              ]),
              const SizedBox(height: 16),
              _card(Icons.palette_outlined, 'Nasıl görünür?', [
                Text(d.look, style: const TextStyle(color: kText, height: 1.6)),
                for (final s in d.screens) ...[
                  const SizedBox(height: 16),
                  ScreenShotView(shot: s),
                ],
              ]),
              const SizedBox(height: 16),
              _pair(
                _card(Icons.checklist_rounded, 'Bilgisayarında neler olmalı?', [
                  for (final r in d.requirements)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.check_rounded, color: kGreen, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(r, style: const TextStyle(color: kText, height: 1.5))),
                      ]),
                    ),
                ]),
                _card(Icons.computer_rounded, 'Hangi bilgisayarlara kurulur?', [
                  const Text('Kurulabilir ana sistemler', style: TextStyle(color: kMuted, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(installable.isEmpty ? 'Yok' : installable.join(', '),
                      style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  for (final h in Host.values) _hostRow(h, d),
                ]),
              ),
              if (!web) ...[
                const SizedBox(height: 20),
                Text(tr('Lisans: {text}', {'text': tr(d.license)}), style: const TextStyle(color: kMuted, fontSize: 13, height: 1.5)),
                const SizedBox(height: 4),
                const Text('Resmi sayfa', style: TextStyle(color: kMuted, fontSize: 13)),
                SelectableText(d.downloadPage, style: const TextStyle(color: kAccent)),
              ],
            ]),
      ),
    );
  }

  static bool _ok(Host h, Distro d) {
    final key = hostKey(h);
    return key != null && supportFor(h, d.family).supported && d.hosts.contains(key);
  }

  Widget _hero(Distro d, Color accent) {
    return Panel(
      tint: accent,
      padding: const EdgeInsets.all(24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        LetterBadge(name: d.name, color: accent, size: 72),
        const SizedBox(width: 20),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name, style: const TextStyle(color: kText, fontSize: 34, fontWeight: FontWeight.w800, height: 1.1)),
            const SizedBox(height: 6),
            Text(d.tagline, style: const TextStyle(color: kText, fontSize: 18, height: 1.4)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (d.desktop != null) _pill(tr('Masaüstü: {text}', {'text': d.desktop})),
              if (d.basedOn != null) _pill(tr('Temel aldığı sistem: {text}', {'text': d.basedOn})),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: const Color(0x22FFFFFF), borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _card(IconData icon, String title, List<Widget> children) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle(title, icon: icon),
          ...children,
        ]),
      );

  /// Two cards side by side on wide screens, stacked on narrow ones.
  Widget _pair(Widget a, Widget b) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 700) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 16), b]);
        }
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: a),
            const SizedBox(width: 16),
            Expanded(child: b),
          ]),
        );
      });

  Widget _hostRow(Host h, Distro d) {
    final m = supportFor(h, d.family);
    final ok = _ok(h, d);
    final e = ok || !m.supported ? m : const SupportEntry(false, 'Bu dağıtım için bu rehberde yok.');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 24, child: Text(ok ? '✓' : '✗', style: TextStyle(color: ok ? kGreen : kMuted, fontWeight: FontWeight.w700))),
        Expanded(
          child: Text(tr('{host}: {reason}', {'host': tr(_hostNames[h]!), 'reason': tr(e.reason)}), style: const TextStyle(color: kMuted, height: 1.5)),
        ),
      ]),
    );
  }
}

class _DesktopOnlyNote extends StatelessWidget {
  const _DesktopOnlyNote({this.web = false});

  /// On the website this offers the app download instead of describing a feature of the app.
  final bool web;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.desktop_windows_rounded, color: kAccent, size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(web ? 'Kurmak için BesideOS uygulamasını indir' : 'Tek tıkla kurulum için uygulamayı aç',
                style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              web
                  ? 'Uygulama bir Windows bilgisayarda çalışır. Kurmak istediğin sistemi uygulamada seçer, tek tıkla kurulumu başlatırsın.'
                  : 'Bu özellik BesideOS masaüstü uygulamasında, bir Windows bilgisayarda çalışır. Buradan sistemi tanıyabilir ve ISO dosyasını indirebilirsin.',
              style: const TextStyle(color: kMuted, height: 1.5),
            ),
            if (web) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => SiteMode.download(context),
                icon: const Icon(Icons.download_rounded),
                label: const Text('İndirmek için tıklayın'),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
