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

/// Size of the download the click starts, e.g. "3,0 GB".
String isoSizeText(int bytes) => '${(bytes / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB';

/// One-click install only exists in the Windows desktop app.
bool installerSupported() => !kIsWeb && Platform.isWindows;

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

  bool get _supported => widget.supported ?? installerSupported();
  String get _name => widget.distro.name;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.distro;
    if (!_supported || d.userSuppliedIso || !d.hosts.contains('windows')) return const SizedBox.shrink();
    final c = ctl;
    return Panel(
      tint: Color(d.accent),
      padding: const EdgeInsets.all(24),
      child: c == null
          ? _header(Icons.build_circle_outlined, 'Kurulum bileşeni eksik',
              'Uygulamayı yeniden kur. Geliştiriciysen tool\\build_windows.ps1 ile derle.', color: kWarn)
          : ListenableBuilder(listenable: Listenable.merge([c, c.download]), builder: (_, __) => _body(c)),
    );
  }

  // ---------------------------------------------------------------- pieces

  Widget _header(IconData icon, String title, String? subtitle, {Color color = kAccent}) {
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
          Text(title, style: const TextStyle(color: kText, fontSize: 22, fontWeight: FontWeight.w800, height: 1.25)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 15, height: 1.5)),
          ],
        ]),
      ),
    ]);
  }

  Widget _banner(Color color, IconData icon, {String? title, List<String> lines = const []}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(110)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null)
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, height: 1.5)),
            for (final l in lines) Text(l, style: const TextStyle(color: kText, height: 1.5)),
          ]),
        ),
      ]),
    );
  }

  Widget _bigButton(String label, IconData icon, VoidCallback? onPressed) {
    return SizedBox(
      height: 60,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 26),
        label: Text(label),
        style: FilledButton.styleFrom(
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }

  Widget _small(String t) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 13, height: 1.5)),
      );

  Widget _bullet(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: kAccent, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: kText, fontSize: 15, height: 1.5))),
        ]),
      );

  Widget _body(InstallController c) {
    switch (c.phase) {
      case InstallPhase.idle:
      case InstallPhase.undone:
        return _start(c);
      case InstallPhase.downloading:
      case InstallPhase.inspecting:
      case InstallPhase.probing:
      case InstallPhase.planning:
        return _progress(c);
      case InstallPhase.applying:
        return _busy('Kurulum hazırlanıyor…',
            'Windows izin isteyecek: «Evet» de. Bilgisayar kendiliğinden yeniden başlayabilir. Bu pencereyi kapatma.');
      case InstallPhase.undoing:
        return _busy('Değişiklikler geri alınıyor…', 'Windows izin isteyecek: «Evet» de.');
      case InstallPhase.ready:
        return _ready(c);
      case InstallPhase.refused:
        return _refused(c);
      case InstallPhase.applied:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(Icons.check_circle_rounded, 'Hazır! Bilgisayar yeniden başlıyor',
              '$_name kurulum ekranı birazdan açılacak. Ekrandaki yönergeleri izle.', color: kGreen),
          const SizedBox(height: 16),
          _small('Açılmazsa: bilgisayarın açılış menüsünden "BesideOS kurulumu"nu seç. Kurulum bitince BESIDEOS adlı geçici bölümü silebilirsin.'),
        ]);
      case InstallPhase.failed:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(Icons.error_rounded, 'Bir sorun çıktı', c.error ?? 'Başarısız oldu.', color: kDanger),
          const SizedBox(height: 16),
          if (c.hasPendingState) ...[
            _banner(kWarn, Icons.warning_amber_rounded,
                title: 'Yarım kalmış değişiklikler olabilir', lines: ['Geri almanı öneririz.']),
            _bigButton('Değişiklikleri geri al', Icons.undo_rounded, c.undo),
            const SizedBox(height: 10),
          ],
          OutlinedButton(onPressed: () => _begin(c), child: const Text('Tekrar dene')),
        ]);
    }
  }

  void _begin(InstallController c) {
    final arch = widget.hostArch ?? currentIsoArch();
    final iso = arch == null ? null : widget.distro.isoFor(arch);
    if (iso == null || arch == null) return;
    setState(() => _backup = false);
    c.begin(iso, arch);
  }

  // ---------------------------------------------------------------- idle

  Widget _start(InstallController c) {
    final arch = widget.hostArch ?? currentIsoArch();
    final iso = arch == null ? null : widget.distro.isoFor(arch);
    final caveat = oneClickCaveats[widget.distro.id];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(Icons.rocket_launch_rounded, "Windows'un yanına kur",
          "Windows ve dosyaların yerinde kalır. $_name için bilgisayarında yer açılır."),
      const SizedBox(height: 22),
      _threeSteps(),
      const SizedBox(height: 22),
      if (c.phase == InstallPhase.undone)
        _banner(kGreen, Icons.check_circle_rounded, title: 'Değişiklikler geri alındı'),
      if (caveat != null) _banner(kWarn, Icons.info_outline_rounded, title: 'Bilmen gerekenler', lines: [caveat]),
      if (c.hasPendingState) ...[
        _banner(kWarn, Icons.warning_amber_rounded,
            title: 'Daha önce yarım kalmış bir kurulum var',
            lines: ['Yenisine başlamadan önce eski değişiklikleri geri almalısın.']),
        _bigButton('Değişiklikleri geri al', Icons.undo_rounded, c.undo),
      ] else ...[
        _bigButton('Kurmak için tıklayın', Icons.touch_app_rounded, iso == null ? null : () => _begin(c)),
        _small(iso == null
            ? 'Bu bilgisayarın işlemcisi için ISO yok.'
            : '${iso.sizeBytes != null ? 'İndirilecek ISO dosyası: ${isoSizeText(iso.sizeBytes!)}. ' : ''}'
                'Önce neler yapılacağını sana göstereceğiz. Sen onaylamadan bilgisayarında hiçbir şey değişmez.'),
      ],
    ]);
  }

  Widget _threeSteps() {
    final steps = [
      ('Tıklarsın', 'Gerisini BesideOS yapar.'),
      ('Bilgisayar hazırlanır', '$_name indirilir ve Windows\'un yanında yer açılır.'),
      ('Yeniden başlar', '$_name kurulum ekranı açılır.'),
    ];
    Widget item(int i) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: kAccent),
            child: Text('${i + 1}', style: const TextStyle(color: kBg, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(steps[i].$1, style: const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 2),
              Text(steps[i].$2, style: const TextStyle(color: kMuted, height: 1.4)),
            ]),
          ),
        ]);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 560) {
        return Column(children: [for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(bottom: 14), child: item(i))]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 18),
          Expanded(child: item(i)),
        ],
      ]);
    });
  }

  // ---------------------------------------------------------------- progress

  Widget _busy(String title, String text) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(Icons.hourglass_top_rounded, title, text),
        const SizedBox(height: 18),
        const LinearProgressIndicator(minHeight: 6, borderRadius: BorderRadius.all(Radius.circular(3))),
      ]);

  Widget _progress(InstallController c) {
    final idx = switch (c.phase) {
      InstallPhase.downloading => 0,
      InstallPhase.inspecting => 1,
      InstallPhase.probing => 2,
      _ => 3,
    };
    final rows = <(String, Widget?)>[
      ('$_name indiriliyor ve kontrol ediliyor', idx == 0 ? _downloadDetail(c.download) : null),
      ('İndirilen dosya inceleniyor', null),
      ('Bilgisayarın kontrol ediliyor', idx == 2 ? _detail('Windows izin isteyecek: «Evet» de.') : null),
      ('Plan hazırlanıyor', null),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(Icons.hourglass_top_rounded, 'Hazırlanıyor, lütfen bekle…',
          'Bilgisayarında henüz hiçbir şey değişmiyor.'),
      const SizedBox(height: 18),
      for (var i = 0; i < rows.length; i++)
        _row(i < idx ? 1 : (i == idx ? 2 : 0), rows[i].$1, rows[i].$2),
      if (idx == 0) ...[
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: c.download.cancel, child: const Text('Vazgeç'))),
      ],
    ]);
  }

  Widget _detail(String t) => Text(t, style: const TextStyle(color: kMuted, height: 1.5));

  Widget _downloadDetail(DownloadController dl) {
    switch (dl.phase) {
      case DownloadPhase.fetchingChecksum:
        return _detail('Doğrulama bilgisi alınıyor…');
      case DownloadPhase.verifying:
        return _detail('Dosyanın bozuk olmadığı kontrol ediliyor…');
      default:
        final t = dl.total;
        final known = t != null && t > 0;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(
            value: known ? (dl.received / t).clamp(0.0, 1.0) : null,
            minHeight: 6,
            borderRadius: const BorderRadius.all(Radius.circular(3)),
          ),
          const SizedBox(height: 6),
          _detail(known
              ? '%${(dl.received * 100 / t).floor()}'
              : '${(dl.received / (1024 * 1024)).toStringAsFixed(1)} MB indirildi'),
        ]);
    }
  }

  /// state: 0 = waiting, 1 = done, 2 = running.
  Widget _row(int state, String label, Widget? detail) {
    final lead = switch (state) {
      1 => const Icon(Icons.check_circle_rounded, color: kGreen, size: 26),
      2 => const SizedBox(width: 26, height: 26, child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 3))),
      _ => const Icon(Icons.radio_button_unchecked_rounded, color: kMuted, size: 26),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        lead,
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    color: state == 0 ? kMuted : kText,
                    fontWeight: state == 2 ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 16,
                    height: 1.5)),
            if (detail != null) detail,
          ]),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- plan

  Widget _sizeChips(InstallController c) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final g in linuxSpaceChoicesGiB)
          ChoiceChip(
            label: Text(g == defaultLinuxSpaceGiB ? '$g GB · önerilen' : '$g GB'),
            selected: c.linuxGiB == g,
            onSelected: c.busy ? null : (_) => c.replan(g),
          ),
      ]);

  String _gb(int bytes) => '${(bytes / (1 << 30)).round()} GB';

  /// Only shown with 2+ candidate drives (e.g. two disks). Picking one re-plans from that drive's free space.
  List<Widget> _drivePicker(InstallController c) {
    if (c.drives.length < 2) return const [];
    return [
      const Text('Yer hangi sürücüden açılsın?',
          style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      _detail('Linux için yer, seçtiğin sürücünün boş alanından ayrılır. Sürücüdeki dosyaların silinmez.'),
      const SizedBox(height: 10),
      for (final d in c.drives) _driveTile(c, d),
      const SizedBox(height: 12),
    ];
  }

  Widget _driveTile(InstallController c, DriveChoice d) {
    final sel = c.target != null && d.same(c.target!);
    final name = d.label.isEmpty ? '${d.letter}: sürücüsü' : '${d.letter}: sürücüsü (${d.label})';
    final disk = d.diskName.isEmpty ? 'Disk ${d.disk}' : d.diskName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: sel ? kAccent.withAlpha(30) : kPanel2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: sel ? kAccent : const Color(0x14FFFFFF), width: sel ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: c.busy || sel ? null : () => c.selectDrive(d),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: sel ? kAccent : kMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.isWindows ? '$name · Windows burada' : name,
                      style: const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('$disk · toplam ${_gb(d.sizeBytes)} · ${_gb(d.freeBytes)} boş',
                      style: const TextStyle(color: kMuted, height: 1.4)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _ready(InstallController c) {
    final plan = c.plan!;
    final gb = (plan.shrinkBytes / (1 << 30)).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(Icons.check_circle_rounded, 'Her şey hazır!',
          'Bilgisayarında henüz hiçbir şey değişmedi. Neler olacağına bak, sonra başla.', color: kGreen),
      const SizedBox(height: 22),
      ..._drivePicker(c),
      const Text('Linux için ne kadar yer ayıralım?',
          style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      _detail('Çoğu kişi için 30 GB yeter. Çok program kuracaksan daha fazlasını seç.'),
      const SizedBox(height: 10),
      _sizeChips(c),
      const SizedBox(height: 22),
      const Text('Neler olacak?', style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      _bullet(Icons.content_cut_rounded,
          c.target != null && !c.target!.isWindows && c.drives.length > 1
              ? '${c.target!.letter}: sürücüsünde yaklaşık $gb GB boş yer açılır.'
              : "Windows'un yanında yaklaşık $gb GB boş yer açılır."),
      _bullet(Icons.file_copy_rounded, '$_name kurulum dosyaları bu yere kopyalanır.'),
      _bullet(Icons.restart_alt_rounded, 'Bilgisayar yeniden başlar ve $_name kurulum ekranı açılır.'),
      const SizedBox(height: 6),
      if (plan.risks.isNotEmpty)
        _banner(kWarn, Icons.warning_amber_rounded, title: 'Bilmen gerekenler', lines: plan.risks),
      // The panel's DecoratedBox would hide the tile's ink; give it its own Material.
      Material(
        type: MaterialType.transparency,
        child: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _backup,
          onChanged: (v) => setState(() => _backup = v ?? false),
          title: const Text('Önemli dosyalarımı yedekledim',
              style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w600)),
          subtitle: const Text('Bölüm küçültme nadiren de olsa sorun çıkarabilir.', style: TextStyle(color: kMuted)),
        ),
      ),
      const SizedBox(height: 8),
      _bigButton('Kurulumu başlat', Icons.play_arrow_rounded, _backup ? () => _confirmAndApply(c) : null),
      if (!_backup) _small('Başlamak için yukarıdaki kutuyu işaretle.'),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Teknik ayrıntılar', style: TextStyle(color: kMuted, fontSize: 14)),
          children: [
            for (final s in plan.steps)
              Align(alignment: Alignment.centerLeft, child: Text('• $s', style: const TextStyle(color: kMuted, height: 1.6))),
          ],
        ),
      ),
    ]);
  }

  Future<void> _confirmAndApply(InstallController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Başlayalım mı?'),
        content: Text('Bilgisayar yeniden başlayacak ve $_name kurulum ekranı açılacak. Açık işlerini şimdi kaydet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet, başlat')),
        ],
      ),
    );
    if (ok == true) await c.apply(confirmed: true);
  }

  Widget _refused(InstallController c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(Icons.info_rounded, 'Bu bilgisayara şu an kurulamıyor', 'Hiçbir şey değişmedi.', color: kWarn),
        const SizedBox(height: 16),
        _banner(kWarn, Icons.report_problem_rounded, lines: [c.refusal ?? 'Kurulum yapılamıyor.']),
        const SizedBox(height: 12),
        ..._drivePicker(c),
        const Text('Daha küçük bir alan seçmeyi deneyebilirsin:',
            style: TextStyle(color: kText, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _sizeChips(c),
      ]);
}
