import 'package:flutter/material.dart';

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
  const DistroPage({super.key, required this.distro});
  final Distro distro;

  @override
  Widget build(BuildContext context) {
    final d = distro;
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
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(d.tagline, style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(d.description, style: const TextStyle(color: kMuted, height: 1.5)),
              const SizedBox(height: 8),
              Text('Kimler için: ${d.bestFor}', style: const TextStyle(color: kMuted, height: 1.5)),
              if (d.basedOn != null)
                Text('Temel aldığı sistem: ${d.basedOn}', style: const TextStyle(color: kMuted, height: 1.5)),
              _head('Görünüm'),
              Container(
                decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(8)),
                clipBehavior: Clip.antiAlias,
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(width: 6, color: Color(d.accent)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (d.desktop != null)
                            Text('Masaüstü: ${d.desktop}', style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
                          Text(d.look, style: const TextStyle(color: kMuted, height: 1.5)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              _head('Kurulum adımları'),
              for (var i = 0; i < d.guide.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
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
              _head('Gereksinimler'),
              for (final r in d.requirements) Text('• $r', style: const TextStyle(color: kMuted, height: 1.6)),
              _head('Kurulabilir ana sistemler'),
              Text(installable.isEmpty ? 'Yok' : installable.join(', '), style: const TextStyle(color: kText)),
              const SizedBox(height: 8),
              for (final h in Host.values) _hostRow(h, d),
              _head('Kurulamayanlar'),
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
              _head('Lisans'),
              Text(d.license, style: const TextStyle(color: kMuted, height: 1.5)),
              _head('Resmi sayfa'),
              SelectableText(d.downloadPage, style: const TextStyle(color: kAccent)),
              if (d.userSuppliedIso) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(8)),
                  child: const Text(
                    'Bu sistem için kendi ISO dosyanı getirmen gerekir; BesideOS ISO dosyası sağlamaz.',
                    style: TextStyle(color: kText, height: 1.5),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const FilledButton(onPressed: null, child: Text('İndir (sonraki aşamada)')),
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

  Widget _head(String t) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(t, style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
      );

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
