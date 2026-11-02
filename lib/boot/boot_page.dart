import 'dart:io';

import 'package:flutter/material.dart';

import '../brand.dart';
import '../install/engine.dart';
import '../install/process_runner.dart';
import '../theme.dart';
import 'boot_controller.dart';

/// Real controller for the app; null when the engine (the PowerShell scripts) is missing.
BootController? makeBootController() {
  final engine = locateEngine();
  final script = engine?.boot;
  if (script == null || !script.existsSync()) return null;
  final base = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
  return BootController(
    runner: SystemProcessRunner(),
    script: script,
    workDir: Directory('$base${Platform.pathSeparator}BesideOS${Platform.pathSeparator}work'),
  );
}

/// "Which system should start?": the installed systems, with a one-time or a permanent choice.
class BootPage extends StatefulWidget {
  const BootPage({super.key, this.controller});

  /// Test hook; the app builds the real one.
  final BootController? controller;

  @override
  State<BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<BootPage> {
  BootController? _c;
  bool _own = false;
  bool _showOthers = false;

  @override
  void initState() {
    super.initState();
    _c = widget.controller;
    if (_c == null) {
      _c = makeBootController();
      _own = _c != null;
    }
    _c?.load();
  }

  @override
  void dispose() {
    if (_own) _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: kBg,
      appBar: const SiteBar(page: 'Açılış sistemi', maxWidth: 920, padding: 20),
      body: PageScroll(
        maxWidth: 920,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
        child: c == null
            ? _message(Icons.extension_off_rounded, 'Bu özellik yalnızca BesideOS uygulamasında çalışır',
                'Uygulama dosyaları eksik görünüyor. Uygulamayı yeniden indirip aç.')
            : ListenableBuilder(listenable: c, builder: (context, _) => _body(c)),
      ),
    );
  }

  Widget _message(IconData icon, String title, String text, {Color color = kWarn}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_header(icon, title, text, color: color)]);

  Widget _header(IconData icon, String title, String? text, {Color color = kAccent}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, color: color, size: 30),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: kText, fontSize: 24, fontWeight: FontWeight.w800, height: 1.25)),
          if (text != null) ...[
            const SizedBox(height: 4),
            Text(text, style: const TextStyle(color: kMuted, fontSize: 16, height: 1.5)),
          ],
        ]),
      ),
    ]);
  }

  Widget _banner(Color color, IconData icon, String text) => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withAlpha(28),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(110)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: kText, fontSize: 15, height: 1.5))),
        ]),
      );

  Widget _body(BootController c) {
    if (c.phase == BootPhase.idle || c.phase == BootPhase.loading) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(Icons.hourglass_top_rounded, 'Kurulu sistemler okunuyor…', 'Windows izin isteyecek: «Evet» de.'),
        const SizedBox(height: 18),
        const LinearProgressIndicator(minHeight: 6, borderRadius: BorderRadius.all(Radius.circular(3))),
      ]);
    }
    if (c.phase == BootPhase.failed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(Icons.error_rounded, 'Sistemler okunamadı', c.error, color: kDanger),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: c.load, child: const Text('Tekrar dene')),
      ]);
    }
    final systems = c.systems;
    final working = c.phase == BootPhase.working;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(Icons.power_settings_new_rounded, 'Bilgisayar hangi sistemle açılsın?',
          'Bilgisayarında kurulu sistemler aşağıda. İstediğini bir kereliğine ya da hep açılacak şekilde seç.'),
      if (systems.length < 2)
        _banner(kAccent, Icons.info_outline_rounded,
            'Şu an tek bir sistem görünüyor. Yanına ikinci bir sistem kurunca burada ikisini de seçebilirsin.'),
      if (c.notice != null) _banner(kGreen, Icons.check_circle_rounded, c.notice!),
      if (c.error != null) _banner(kWarn, Icons.warning_amber_rounded, c.error!),
      const SizedBox(height: 18),
      for (final e in systems) ...[_systemCard(c, e, working), const SizedBox(height: 12)],
      if (c.notice != null) ...[
        const SizedBox(height: 4),
        if (c.restarting) ...[
          _banner(kWarn, Icons.restart_alt_rounded, 'Bilgisayar 15 saniye içinde yeniden başlıyor. Açık işin varsa kaydet.'),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: c.cancelRestart, child: const Text('Yeniden başlatmaktan vazgeç')),
        ] else
          FilledButton.icon(
            onPressed: () => _confirmRestart(c),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Şimdi yeniden başlat'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
      ],
      _banner(kAccent, Icons.lightbulb_outline_rounded,
          'Linux kurunca kendi seçim menüsü (GRUB) de gelebilir. Burada seçtiğin sistem, o menüden önce bilgisayarın açılışta ilk denediği sistemdir.'),
      if (c.others.isNotEmpty)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: _showOthers,
            onExpansionChanged: (v) => _showOthers = v,
            title: const Text('Diğer girişler (USB, ağ, kurulum)', style: TextStyle(color: kMuted, fontSize: 14)),
            children: [
              for (final e in c.others)
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('• ${e.description.isEmpty ? e.id : e.description}', style: const TextStyle(color: kMuted, height: 1.6))),
            ],
          ),
        ),
    ]);
  }

  Widget _systemCard(BootController c, BootEntry e, bool working) {
    final icon = e.isWindows ? Icons.window_rounded : Icons.terminal_rounded;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: (c.isNext(e) ? kGreen : kAccent).withAlpha(c.isDefault(e) || c.isNext(e) ? 160 : 60)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: kAccent, size: 28),
          const SizedBox(width: 14),
          Expanded(child: Text(e.label, style: const TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.w800))),
          if (c.isNext(e)) _tag('Sıradaki açılış', kGreen),
          if (c.isDefault(e)) ...[const SizedBox(width: 8), _tag('Varsayılan', kAccent)],
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton(
            onPressed: working ? null : () => c.startNext(e),
            child: const Text('Bir sonraki açılışta bunu aç'),
          ),
          OutlinedButton(
            onPressed: working || c.isDefault(e) ? null : () => c.makeDefault(e),
            child: const Text('Hep bunu aç'),
          ),
        ]),
      ]),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withAlpha(36), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Future<void> _confirmRestart(BootController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şimdi yeniden başlatalım mı?'),
        content: const Text('Bilgisayar 15 saniye sonra yeniden başlayacak. Açık işlerini şimdi kaydet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Şimdi değil')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet, yeniden başlat')),
        ],
      ),
    );
    if (ok == true) await c.restart();
  }
}
