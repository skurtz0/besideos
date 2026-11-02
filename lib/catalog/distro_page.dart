import 'package:flutter/material.dart';

import '../download/download_section.dart';
import '../install/install_controller.dart';
import '../install/install_section.dart';
import '../theme.dart';
import 'distro.dart';
import 'support_matrix.dart';

const _hostNames = {
  Host.windows: 'Windows',
  Host.linux: 'Linux',
  Host.macM1M2: 'Mac M1/M2',
  Host.macOther: 'Diğer Mac',
};

class DistroPage extends StatelessWidget {
  const DistroPage({super.key, required this.distro, this.installFactory});
  final Distro distro;

  /// Test hook: supplies the installer controller instead of locating the real engine.
  final InstallController? Function()? installFactory;

  @override
  Widget build(BuildContext context) {
    final d = distro;
    final accent = Color(d.accent);
    final canOneClick = !d.userSuppliedIso && d.hosts.contains('windows');
    final installable = [
      for (final h in Host.values)
        if (_ok(h, d)) _hostNames[h]!,
    ];
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        foregroundColor: kText,
        leading: Navigator.canPop(context)
            ? const BackButton()
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Dağıtımlar',
                onPressed: () => Navigator.pushReplacementNamed(context, '/distros'),
              ),
        title: Text(d.name, overflow: TextOverflow.ellipsis),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _hero(d, accent),
              if (canOneClick && installerSupported()) ...[
                const SizedBox(height: 16),
                InstallSection(distro: d, controllerFactory: installFactory),
              ],
              if (canOneClick && !installerSupported()) ...[
                const SizedBox(height: 16),
                const _DesktopOnlyNote(),
              ],
              if (d.userSuppliedIso) ...[
                const SizedBox(height: 16),
                const Panel(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.folder_open_rounded, color: kAccent),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Bu sistem için kendi ISO dosyanı getirmen gerekir; BesideOS ISO dosyası sağlamaz.',
                        style: TextStyle(color: kText, height: 1.5),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              _pair(
                _card(Icons.lightbulb_outline_rounded, 'Bu sistem nedir?', [
                  Text(d.description, style: const TextStyle(color: kText, height: 1.6)),
                  const SizedBox(height: 10),
                  Text('Kimler için: ${d.bestFor}', style: const TextStyle(color: kMuted, height: 1.5)),
                ]),
                _card(Icons.palette_outlined, 'Nasıl görünür?', [
                  Text(d.look, style: const TextStyle(color: kText, height: 1.6)),
                ]),
              ),
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
              const SizedBox(height: 16),
              _fold(Icons.menu_book_rounded, 'Elle kurmak istersen: adımlar', [
                for (var i = 0; i < d.guide.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 28, child: Text('${i + 1}.', style: const TextStyle(color: kAccent, fontWeight: FontWeight.w700))),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d.guide[i].title, style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
                          Text(d.guide[i].body, style: const TextStyle(color: kMuted, height: 1.5)),
                        ]),
                      ),
                    ]),
                  ),
              ]),
              const SizedBox(height: 12),
              _fold(Icons.block_rounded, 'Kurulamayanlar', [
                for (final u in unsupportedTargets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: u.key, style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
                        TextSpan(text: ': ${u.value.reason}'),
                      ]),
                      style: const TextStyle(color: kMuted, height: 1.5),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              _card(
                d.userSuppliedIso ? Icons.verified_outlined : Icons.download_rounded,
                d.userSuppliedIso ? 'ISO dosyanı doğrula' : 'Sadece ISO dosyasını indir',
                [
                  if (!d.userSuppliedIso)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text('Kurmadan yalnızca dosyayı almak istersen. İndirilen dosya otomatik doğrulanır.',
                          style: TextStyle(color: kMuted, height: 1.5)),
                    ),
                  Theme(
                    data: Theme.of(context).copyWith(
                      filledButtonTheme: FilledButtonThemeData(
                        style: FilledButton.styleFrom(backgroundColor: kPanel2, foregroundColor: kText),
                      ),
                    ),
                    child: DownloadSection(distro: d),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Lisans: ${d.license}', style: const TextStyle(color: kMuted, fontSize: 13, height: 1.5)),
              const SizedBox(height: 4),
              const Text('Resmi sayfa', style: TextStyle(color: kMuted, fontSize: 13)),
              SelectableText(d.downloadPage, style: const TextStyle(color: kAccent)),
            ]),
          ),
        ),
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
              if (d.desktop != null) _pill('Masaüstü: ${d.desktop}'),
              if (d.basedOn != null) _pill('Temel aldığı sistem: ${d.basedOn}'),
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

  Widget _fold(IconData icon, String title, List<Widget> children) => Panel(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Theme(
          data: ThemeData(brightness: Brightness.dark, dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            leading: Icon(icon, color: kAccent, size: 22),
            title: Text(title, style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
            children: children,
          ),
        ),
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
          child: Text('${_hostNames[h]}: ${e.reason}', style: const TextStyle(color: kMuted, height: 1.5)),
        ),
      ]),
    );
  }
}

class _DesktopOnlyNote extends StatelessWidget {
  const _DesktopOnlyNote();

  @override
  Widget build(BuildContext context) {
    return const Panel(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.desktop_windows_rounded, color: kAccent, size: 28),
        SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tek tıkla kurulum için uygulamayı aç',
                style: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text(
              'Bu özellik BesideOS masaüstü uygulamasında, bir Windows bilgisayarda çalışır. Buradan sistemi tanıyabilir ve ISO dosyasını indirebilirsin.',
              style: TextStyle(color: kMuted, height: 1.5),
            ),
          ]),
        ),
      ]),
    );
  }
}
