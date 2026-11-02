import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../catalog/distro.dart';
import '../download/download_controller.dart';
import '../download/downloader.dart';
import '../download/host_arch_stub.dart' if (dart.library.io) '../download/host_arch_io.dart';
import '../theme.dart';
import 'engine.dart';
import 'install_controller.dart';
import 'process_runner.dart';

/// Known reasons the extracted-ISO method may not boot for a distro. Shown before the user starts.
const oneClickCaveats = {
  'fedora':
      'Fedora Live, kurulum ortamını ISO etiketiyle arar; bölüm "BESIDEOS" etiketli olduğu için açılmayabilir. Bu yöntem Fedora ile doğrulanmadı.',
};

InstallController? _defaultController() {
  final engine = locateEngine();
  if (engine == null) return null;
  return InstallController(
    runner: SystemProcessRunner(),
    engine: engine,
    workDir: defaultWorkDir(),
    download: DownloadController(downloader: Downloader(), targetDir: defaultDownloadDir()),
  );
}

class InstallSection extends StatefulWidget {
  const InstallSection({
    super.key,
    required this.distro,
    this.controllerFactory,
    this.hostArch,
    this.supported,
  });
  final Distro distro;

  /// Returns null when the installer engine is not available.
  final InstallController? Function()? controllerFactory;
  final IsoArch? hostArch;

  /// Test override for "running as the Windows desktop app".
  final bool? supported;

  @override
  State<InstallSection> createState() => _InstallSectionState();
}

class _InstallSectionState extends State<InstallSection> {
  InstallController? _ctl;
  bool _built = false;
  bool _backup = false;
  final _confirm = TextEditingController();

  bool get _supported => widget.supported ?? (!kIsWeb && Platform.isWindows);

  InstallController? get ctl {
    if (!_built) {
      _built = true;
      _ctl = (widget.controllerFactory ?? _defaultController)();
    }
    return _ctl;
  }

  @override
  void dispose() {
    _ctl?.download.dispose();
    _ctl?.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.distro;
    if (!_supported || d.userSuppliedIso || !d.hosts.contains('windows')) return const SizedBox.shrink();
    final c = ctl;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(8)),
      child: c == null
          ? _col([
              _head(),
              _note('Kurulum motoru bulunamadı (engine klasörü). Uygulamayı tool\\build_windows.ps1 ile derle.'),
            ])
          : ListenableBuilder(listenable: Listenable.merge([c, c.download]), builder: (_, __) => _body(c)),
    );
  }

  Widget _head() => const Text('Tek tıkla kur',
      style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700));

  Widget _col(List<Widget> c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final w in c) Padding(padding: const EdgeInsets.only(bottom: 8), child: w)],
      );

  Widget _note(String t, {Color color = kMuted}) => Text(t, style: TextStyle(color: color, height: 1.5));

  Widget _body(InstallController c) {
    switch (c.phase) {
      case InstallPhase.idle:
      case InstallPhase.undone:
        return _start(c);
      case InstallPhase.downloading:
        return _col([_head(), ..._downloadStatus(c)]);
      case InstallPhase.inspecting:
        return _wait('ISO içeriği inceleniyor…');
      case InstallPhase.probing:
        return _wait('Disk bilgisi okunuyor. Yönetici izni isteyecek.');
      case InstallPhase.planning:
        return _wait('Plan hazırlanıyor…');
      case InstallPhase.applying:
        return _wait('Kurulum hazırlanıyor. Yönetici izni isteyecek; bilgisayar kendiliğinden yeniden başlayabilir. Bu pencereyi kapatma.');
      case InstallPhase.undoing:
        return _wait('Değişiklikler geri alınıyor. Yönetici izni isteyecek.');
      case InstallPhase.ready:
        return _ready(c);
      case InstallPhase.refused:
        return _col([
          _head(),
          _note(c.refusal ?? 'Bu bilgisayara kurulamaz.', color: Colors.redAccent),
          _sizePicker(c),
          _note('Daha küçük bir alan seçebilir ya da kurulamayan nedeni gidermeyi deneyebilirsin. Hiçbir şey değiştirilmedi.'),
        ]);
      case InstallPhase.applied:
        return _col([
          _head(),
          _note('Hazır. Bilgisayar yeniden başlatılıyor; açılışta ${widget.distro.name} kurulum ekranı gelecek.', color: kGreen),
          _note('Gelmezse bilgisayarın açılış menüsünden "BesideOS kurulumu" girdisini seç. Kurulum bitince BESIDEOS adlı geçici bölüm silinebilir.'),
        ]);
      case InstallPhase.failed:
        return _col([
          _head(),
          _note(c.error ?? 'Başarısız.', color: Colors.redAccent),
          if (c.hasPendingState) ...[
            _note('Disk üzerinde yarım kalmış değişiklikler olabilir. Geri almanı öneririm.', color: Colors.orangeAccent),
            ElevatedButton(onPressed: c.undo, child: const Text('Değişiklikleri geri al')),
          ],
          OutlinedButton(onPressed: () => _begin(c), child: const Text('Tekrar dene')),
        ]);
    }
  }

  void _begin(InstallController c) {
    final arch = widget.hostArch ?? currentIsoArch();
    final iso = arch == null ? null : widget.distro.isoFor(arch);
    if (iso == null || arch == null) return;
    _backup = false;
    _confirm.clear();
    c.begin(iso, arch);
  }

  Widget _start(InstallController c) {
    final arch = widget.hostArch ?? currentIsoArch();
    final iso = arch == null ? null : widget.distro.isoFor(arch);
    final caveat = oneClickCaveats[widget.distro.id];
    return _col([
      _head(),
      _note('${widget.distro.name} indirilir, doğrulanır ve Windows\'un yanına kurulum için hazırlanır. '
          'Diskine dokunmadan önce planı gösterip onayını isterim.'),
      if (caveat != null) _note(caveat, color: Colors.orangeAccent),
      if (c.phase == InstallPhase.undone) _note('Değişiklikler geri alındı.', color: kGreen),
      if (c.hasPendingState) ...[
        _note('Önceki bir kurulumdan kalan değişiklikler var. Yeni kuruluma başlamadan önce geri almalısın.', color: Colors.orangeAccent),
        ElevatedButton(onPressed: c.undo, child: const Text('Değişiklikleri geri al')),
      ] else
        ElevatedButton(
          onPressed: iso == null ? null : () => _begin(c),
          child: Text('${widget.distro.name} kur'),
        ),
      if (iso == null) _note('Bu mimari için ISO yok.'),
    ]);
  }

  Widget _wait(String text) => _col([_head(), const LinearProgressIndicator(), _note(text)]);

  List<Widget> _downloadStatus(InstallController c) {
    final dl = c.download;
    switch (dl.phase) {
      case DownloadPhase.fetchingChecksum:
        return [_note('Sağlama dosyası alınıyor…'), _cancel(dl)];
      case DownloadPhase.verifying:
        return [const LinearProgressIndicator(), _note('Doğrulanıyor…')];
      default:
        final t = dl.total;
        final mb = (dl.received / (1024 * 1024)).toStringAsFixed(1);
        return [
          LinearProgressIndicator(value: t == null || t == 0 ? null : (dl.received / t).clamp(0.0, 1.0)),
          _note(t == null || t == 0 ? '$mb MB indirildi' : 'İndiriliyor: %${(dl.received * 100 / t).floor()}'),
          _cancel(dl),
        ];
    }
  }

  Widget _cancel(DownloadController dl) => OutlinedButton(onPressed: dl.cancel, child: const Text('İptal'));

  Widget _sizePicker(InstallController c) => Row(children: [
        const Text('Linux için ayrılacak alan: ', style: TextStyle(color: kText)),
        DropdownButton<int>(
          value: c.linuxGiB,
          dropdownColor: kPanel,
          style: const TextStyle(color: kText),
          items: [for (final g in linuxSpaceChoicesGiB) DropdownMenuItem(value: g, child: Text('$g GiB'))],
          onChanged: c.busy ? null : (g) => g == null ? null : c.replan(g),
        ),
      ]);

  Widget _ready(InstallController c) {
    final plan = c.plan!;
    final can = _backup && _confirm.text.trim().toUpperCase() == installConfirmWord;
    return _col([
      _head(),
      _note('Plan hazır. Henüz diskine dokunulmadı.', color: kGreen),
      _sizePicker(c),
      for (final s in plan.steps) Text('• $s', style: const TextStyle(color: kText, height: 1.5)),
      for (final r in plan.risks) Text('⚠ $r', style: const TextStyle(color: Colors.orangeAccent, height: 1.5)),
      // The panel's DecoratedBox would hide the tile's ink; give it its own Material.
      Material(
        type: MaterialType.transparency,
        child: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _backup,
          onChanged: (v) => setState(() => _backup = v ?? false),
          title: const Text(
            'Önemli dosyalarımın yedeğini aldım. Bölüm küçültmenin geri alınamayabileceğini ve bilgisayarın yeniden başlayacağını anlıyorum.',
            style: TextStyle(color: kText, height: 1.4),
          ),
        ),
      ),
      TextField(
        controller: _confirm,
        style: const TextStyle(color: kText),
        decoration: const InputDecoration(labelText: 'Onaylamak için $installConfirmWord yaz'),
        onChanged: (_) => setState(() {}),
      ),
      ElevatedButton(
        onPressed: can ? () => c.apply(_confirm.text) : null,
        child: const Text('Kurulumu başlat ve yeniden başlat'),
      ),
    ]);
  }
}
