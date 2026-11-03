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
import 'install_sessions.dart';
import 'iso_picker.dart';
import 'process_runner.dart';

/// Known reasons the extracted-ISO method may not boot for a distro. Shown before the user starts.
const _labelCaveat =
    'Bu sistemin kurulum ekranı bazı bilgisayarlarda açılmayabilir. Açılmazsa "Değişiklikleri geri al" ile eski haline dönersin.';

const oneClickCaveats = {
  'fedora': _labelCaveat,
  'bazzite': _labelCaveat,
  'manjaro': _labelCaveat,
  'cachyos': _labelCaveat,
  'omarchy': _labelCaveat,
  'opensuse': _labelCaveat,
  'windows-xp': _oldWindowsCaveat,
  'windows-7': _oldWindowsCaveat,
  'windows-8-1': _oldWindowsCaveat,
};

const _oldWindowsCaveat =
    'Bu eski Windows sürümü yeni bilgisayarlarda (UEFI) açılmayabilir. Açılmazsa "Değişiklikleri geri al" ile eski haline dönersin.';

/// Firmware (BIOS/UEFI) settings the user should check before starting.
const beforeYouStart = [
  'Bilgisayarın UEFI modunda açılmalı (BIOS ayarlarında "Legacy/CSM" kapalı olsun). Eski BIOS modunda bu yöntem çalışmaz.',
  'Secure Boot açıkken bazı sistemler açılmayabilir. Kurulum ekranı gelmezse BIOS ayarlarından Secure Boot\'u kapat, kurulum bitince geri açabilirsin.',
  'Windows\'ta Hızlı Başlatma (Fast Startup) ve BitLocker kapalı olmalı. BitLocker açıksa BesideOS kurulumu reddeder.',
  'Açılış menüsü tuşunu öğren (genelde F12, F10, F9 ya da Esc). Kurulum ekranı kendiliğinden gelmezse bu menüden "BesideOS kurulumu"nu seç.',
];

/// Same idea for a Linux computer: nothing is shrunk, so the firmware list is shorter.
const beforeYouStartLinux = [
  'Bilgisayarın UEFI modunda açılmalı (BIOS ayarlarında "Legacy/CSM" kapalı olsun).',
  'Secure Boot açıkken bazı ISO\'lar açılmayabilir. Kurulum ekranı gelmezse BIOS ayarlarından Secure Boot\'u kapat.',
  'ISO dosyası, kuracağın disk bölümünün dışında durmalı (ör. ayrı bir disk). Kurulum ekranı kendi ISO\'sunu tuttuğu bölümü silemez.',
  'Yer açılacak bölüm ext4, btrfs ya da NTFS olmalı ve içinde yeterli boş yer bulunmalı. Disk GPT olmalı.',
  'Önemli dosyalarını yedekle: bölüm küçültme nadiren de olsa sorun çıkarabilir.',
  'GRUB menüsü kendiliğinden açılmazsa başlangıçta Shift ya da Esc\'e basılı tut ve "BesideOS" girişini seç.',
];

const _windowsSetupNote =
    'Windows Kurulum bu yöntemle, RAM diskten açılır. Kurulum sırasında hata ya da uyarı görmen normaldir; çoğu zaman yok sayıp devam edebilirsin. Kurulum hiç ilerlemezse "Değişiklikleri geri al" ile eski haline dönersin.';

/// Size of the download the click starts, e.g. "3,0 GB".
String isoSizeText(int bytes) => '${(bytes / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB';

/// One-click install only exists in the Windows and Linux desktop apps.
bool installerSupported() => !kIsWeb && (Platform.isWindows || Platform.isLinux);

InstallController? _defaultController(String distroId, String distroName) {
  final engine = locateEngine();
  if (engine == null) return null;
  return InstallController(
    ownerId: distroId,
    ownerName: distroName,
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
    this.pickIso,
    this.findIsos,
  });
  final Distro distro;

  /// Opens the file dialog for the person's own ISO (tests replace it).
  final Future<File?> Function()? pickIso;

  /// ISO files already on this computer (tests replace it).
  final List<LocalIso> Function()? findIsos;

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
  List<LocalIso> _found = const [];

  @override
  void initState() {
    super.initState();
    if (_supported) {
      try {
        _found = (widget.findIsos ?? findLocalIsos)();
      } catch (_) {}
    }
  }

  bool get _supported => widget.supported ?? installerSupported();
  String get _name => widget.distro.name;

  /// What is being installed: the distro, or the ISO file the person picked (it may be any system).
  String _sys(InstallController c) {
    if (!c.isLocalIso) return _name;
    final n = c.isoFileName ?? 'ISO dosyası';
    return n.toLowerCase().endsWith('.iso') ? n.substring(0, n.length - 4) : n;
  }

  /// Tests inject their own controller and the section owns it; the real one is shared across pages.
  bool get _owned => widget.controllerFactory != null;

  InstallController? get ctl {
    if (!_built) {
      _built = true;
      _ctl = _owned
          ? widget.controllerFactory!()
          : InstallSessions.instance.obtain(widget.distro.id, () => _defaultController(widget.distro.id, _name));
    }
    return _ctl;
  }

  @override
  void dispose() {
    if (_owned) {
      _ctl?.download.dispose();
      _ctl?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.distro;
    if (!_supported) return const SizedBox.shrink();
    final c = ctl;
    return Panel(
      tint: Color(d.accent),
      padding: const EdgeInsets.all(24),
      child: c == null
          ? _header(Icons.build_circle_outlined, 'Kurulum bileşeni eksik',
              'Uygulama dosyaları eksik görünüyor. BesideOS\'u yeniden indirip aç.', color: kWarn)
          : ListenableBuilder(
              listenable: Listenable.merge([c, c.download, InstallSessions.instance]), builder: (_, __) => _body(c)),
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

  /// What to pick in the installer's own disk screen. Getting this wrong (wiping the whole disk, formatting the
  /// wrong partition) is the one way the person can still lose data after BesideOS did its part.
  Widget _diskAdvice(InstallController c) {
    final other = c.target != null && !c.target!.isWindows && c.drives.length > 1;
    final isWin = widget.distro.family == DistroFamily.windows;
    if (c.linuxHost) {
      return _banner(kWarn, Icons.disc_full_rounded, title: '${_sys(c)} kurulurken diski doğru seç', lines: const [
        'Kurulum ekranı açılınca disk sorusunda "Diskin tamamını sil" seçeneğini SEÇME. "Başka bir şey" (elle bölümleme) seç ve yalnızca BesideOS\'un açtığı boş (ayrılmamış) alanı kullan.',
        'ISO dosyasının bulunduğu bölüme ve mevcut sistemine dokunma, biçimlendirme (format) yalnızca yeni açılan alanda olsun.',
        'Emin olamazsan kurulumu o ekranda bırak, bilgisayarı yeniden başlat ve BesideOS\'tan "geri al" de.',
      ]);
    }
    return _banner(kWarn, Icons.disc_full_rounded, title: '${_sys(c)} kurulurken diski doğru seç', lines: [
      if (isWin)
        'Disk ekranında "Ayrılmamış alan"ı seç ve "İleri" de. Windows kendi bölümlerini oraya açar.'
      else
        'Disk sorusunda "Diskin tamamını sil" seçeneğini SEÇME. "Yanına kur" ya da "Başka bir şey" (elle bölümleme) seç ve yalnızca "boş alan"ı kullan.',
      if (other) 'Boş yer ${c.target!.letter}: sürücüsünün bulunduğu diskte açıldı; kurulum ekranında o diski seç.',
      'Biçimlendirme (format) yalnızca yeni açılan boş alanda olsun. Windows bölümlerine ve BESIDEOS bölümüne dokunma.',
      'Emin olamazsan kurulumu o ekranda bırak; bilgisayarını kapatıp Windows\'a dönebilirsin, BesideOS\'tan "geri al" demen yeter.',
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
            c.linuxHost
                ? 'Parolanı soran bir pencere açılacak. Bu pencereyi kapatma. Bilgisayar kendiliğinden yeniden başlamaz.'
                : 'Windows izin isteyecek: «Evet» de. Bu pencereyi kapatma. Bilgisayar kendiliğinden yeniden başlamaz.');
      case InstallPhase.undoing:
        return _busy('Değişiklikler geri alınıyor…',
            c.linuxHost ? 'Parolanı soran bir pencere açılacak.' : 'Windows izin isteyecek: «Evet» de.');
      case InstallPhase.ready:
        return _ready(c);
      case InstallPhase.refused:
        return _refused(c);
      case InstallPhase.applied:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(Icons.check_circle_rounded, c.restarting ? 'Bilgisayar 15 saniye içinde yeniden başlıyor' : 'Hazır! Şimdi yeniden başlatabilirsin',
              c.restarting
                  ? 'Açık işin varsa kaydet. Vazgeçersen aşağıdaki düğmeye bas.'
                  : 'Yeniden başlayınca açılış menüsü 5 saniye görünür; "BesideOS: 5 saniye içinde kurulacak: ${_sys(c)}" seçili gelir. '
                      'İstersen listedeki kurulu sistemlerden birini seçebilirsin. Açık işlerini kaydedince yeniden başlat.',
              color: kGreen),
          const SizedBox(height: 16),
          if (c.restartError != null) _banner(kWarn, Icons.warning_amber_rounded, lines: [c.restartError!]),
          _diskAdvice(c),
          if (c.restarting)
            OutlinedButton(onPressed: c.cancelRestart, child: const Text('Yeniden başlatmaktan vazgeç'))
          else ...[
            _bigButton('Şimdi yeniden başlat', Icons.restart_alt_rounded, () => _confirmRestart(c)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: c.undo, child: const Text('Vazgeç, değişiklikleri geri al')),
            const SizedBox(height: 12),
            _small(c.linuxHost
                ? 'Daha sonra başlatmak istersen bilgisayarı kendin yeniden başlat; kurulum ekranı ilk açılışta gelir. Açılmazsa GRUB menüsünden (Shift ya da Esc) "BesideOS" girişini seç. Kurulum bitince girişi "geri al" ile kaldırabilirsin.'
                : 'Daha sonra başlatmak istersen bilgisayarı kendin yeniden başlat; kurulum ekranı ilk açılışta gelir. Açılmazsa açılış menüsünden "BesideOS kurulumu"nu seç. Kurulum bitince BESIDEOS adlı geçici bölümü silebilirsin.'),
          ],
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
          OutlinedButton(onPressed: () => _retry(c), child: const Text('Tekrar dene')),
        ]);
    }
  }

  IsoArch get _arch => widget.hostArch ?? currentIsoArch() ?? IsoArch.x86_64;

  void _begin(InstallController c) {
    final iso = widget.distro.isoFor(_arch);
    if (iso == null) return;
    if (widget.distro.family == DistroFamily.windows) c.useSpace(windowsSpaceGiB);
    setState(() => _backup = false);
    c.begin(iso, _arch);
  }

  void _retry(InstallController c) {
    setState(() => _backup = false);
    c.retry();
  }

  /// "Use my own ISO": the person picks a file (or taps one found on the computer), no path or checksum typing.
  Future<void> _beginOwn(InstallController c, [File? chosen]) async {
    final file = chosen ?? await (widget.pickIso ?? () => pickIsoFile(c.runner))();
    if (file == null || !mounted) return;
    if (widget.distro.family == DistroFamily.windows) c.useSpace(windowsSpaceGiB);
    setState(() => _backup = false);
    c.beginWithFile(file, _arch);
  }

  // ---------------------------------------------------------------- idle

  Widget _start(InstallController c) {
    final d = widget.distro;
    final iso = d.userSuppliedIso ? null : d.isoFor(_arch);
    final official = iso != null;
    final caveat = oneClickCaveats[d.id];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      c.linuxHost
          ? _header(Icons.rocket_launch_rounded, "Linux'un yanına kur",
              'Mevcut sistemin ve dosyaların yerinde kalır. Bir bölüm küçülterek boş yer açılır; $_name ISO dosyasından, bir GRUB girişiyle açılır.')
          : _header(Icons.rocket_launch_rounded, "Windows'un yanına kur",
              "Windows ve dosyaların yerinde kalır. $_name için bilgisayarında yer açılır."),
      const SizedBox(height: 22),
      _threeSteps(official, c.linuxHost),
      const SizedBox(height: 22),
      if (c.phase == InstallPhase.undone)
        _banner(kGreen, Icons.check_circle_rounded, title: 'Değişiklikler geri alındı'),
      _banner(kWarn, Icons.settings_suggest_rounded,
          title: 'Başlamadan önce bilgisayarında kontrol et', lines: c.linuxHost ? beforeYouStartLinux : beforeYouStart),
      if (caveat != null) _banner(kWarn, Icons.info_outline_rounded, title: 'Bilmen gerekenler', lines: [caveat]),
      if (d.family == DistroFamily.windows)
        _banner(kWarn, Icons.info_outline_rounded, title: 'Windows kurulumunda hata görürsen', lines: [_windowsSetupNote]),
      if (c.hasPendingState) ...[
        _banner(kWarn, Icons.warning_amber_rounded,
            title: 'Daha önce yarım kalmış bir kurulum var',
            lines: ['Yenisine başlamadan önce eski değişiklikleri geri almalısın.']),
        _bigButton('Değişiklikleri geri al', Icons.undo_rounded, c.undo),
      ] else ...[
        if (official) ...[
          _bigButton('Kurmak için tıklayın', Icons.touch_app_rounded, () => _begin(c)),
          _small('${iso.sizeBytes != null ? 'İndirilecek ISO dosyası: ${isoSizeText(iso.sizeBytes!)}. ' : ''}'
              'Önce neler yapılacağını sana göstereceğiz. Sen onaylamadan bilgisayarında hiçbir şey değişmez.'),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _beginOwn(c),
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Kendi ISO dosyamı seçip kurmak istiyorum'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ] else ...[
          _bigButton('ISO dosyamı seçip kurmak için tıklayın', Icons.folder_open_rounded, () => _beginOwn(c)),
          _small('Bu sistemin ISO dosyasını sen getirirsin; yol ya da sağlama kodu yazman gerekmez, dosyayı seçmen yeter. '
              'Önce neler yapılacağını sana göstereceğiz. Sen onaylamadan bilgisayarında hiçbir şey değişmez.'),
          if (d.downloadPage.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Dosyan yoksa resmi sayfadan indirebilirsin:',
                textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 13)),
            SelectableText(d.downloadPage,
                textAlign: TextAlign.center, style: const TextStyle(color: kAccent, fontSize: 13)),
          ],
        ],
        if (_found.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text('Bilgisayarında bulunan ISO dosyaları',
              style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          _detail('Birine basarsan onu kurmaya başlarsın.'),
          const SizedBox(height: 10),
          for (final f in _found) _foundTile(c, f),
        ],
      ],
    ]);
  }

  Widget _foundTile(InstallController c, LocalIso f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kPanel2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0x14FFFFFF)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: c.busy ? null : () => _beginOwn(c, f.file),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.album_rounded, color: kAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(isoSizeText(f.bytes), style: const TextStyle(color: kMuted, height: 1.4)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: kMuted),
            ]),
          ),
        ),
      ),
    );
  }
  Widget _threeSteps(bool official, bool linux) {
    final steps = official
        ? [
            ('Tıklarsın', 'Gerisini BesideOS yapar.'),
            ('Bilgisayar hazırlanır', linux ? '$_name indirilir, disklerinde yer açılır ve GRUB menüsüne bir giriş eklenir.' : '$_name indirilir ve Windows\'un yanında yer açılır.'),
            ('Yeniden başlar', '$_name kurulum ekranı açılır.'),
          ]
        : [
            ('ISO dosyanı seçersin', 'Bilgisayarındaki ya da indirdiğin dosyayı gösterirsin.'),
            ('Bilgisayar hazırlanır', linux ? 'Disklerinde yer açılır ve GRUB menüsüne ISO\'nu açan bir giriş eklenir.' : 'Windows\'un yanında yer açılır ve dosyalar oraya konur.'),
            ('Yeniden başlar', 'Kurulum ekranı açılır.'),
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
    // a picked ISO has nothing to download, so that row is not shown
    final own = c.isLocalIso;
    final idx = switch (c.phase) {
      InstallPhase.downloading => 0,
      InstallPhase.inspecting => own ? 0 : 1,
      InstallPhase.probing => own ? 1 : 2,
      _ => own ? 2 : 3,
    };
    final rows = <(String, Widget?)>[
      if (!own) ('$_name indiriliyor ve kontrol ediliyor', idx == 0 ? _downloadDetail(c.download) : null),
      (own ? 'Seçtiğin ISO dosyası inceleniyor' : 'İndirilen dosya inceleniyor', null),
      ('Bilgisayarın kontrol ediliyor', idx == (own ? 1 : 2) && !c.linuxHost ? _detail('Windows izin isteyecek: «Evet» de.') : null),
      ('Plan hazırlanıyor', null),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(Icons.hourglass_top_rounded, 'Hazırlanıyor, lütfen bekle…',
          'Bilgisayarında henüz hiçbir şey değişmiyor.'),
      const SizedBox(height: 18),
      for (var i = 0; i < rows.length; i++)
        _row(i < idx ? 1 : (i == idx ? 2 : 0), rows[i].$1, rows[i].$2),
      if (!own && idx == 0) ...[
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
            label: Text(g == c.recommendedGiB ? '$g GB · önerilen' : '$g GB'),
            selected: c.linuxGiB == g,
            onSelected: c.busy ? null : (_) => c.replan(g),
          ),
      ]);

  String _gb(int bytes) => '${(bytes / (1 << 30)).round()} GB';

  /// Only shown with 2+ candidate drives (e.g. two disks). Picking one re-plans from that drive's free space.
  List<Widget> _drivePicker(InstallController c) {
    if (c.drives.length < (c.linuxHost ? 1 : 2)) return const [];
    return [
      Text(c.linuxHost ? 'Yer hangi bölümden açılsın?' : 'Yer hangi sürücüden açılsın?',
          style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      _detail('Yer, seçtiğin ${c.linuxHost ? 'bölümün' : 'sürücünün'} boş alanından ayrılır. Dosyaların silinmez.'
          '${c.linuxHost ? ' Listede olmayan bölümler küçültülemeyen bir dosya sistemindedir ya da yeterli boş yeri yoktur.' : ''}'),
      const SizedBox(height: 10),
      for (final d in c.drives) _driveTile(c, d),
      const SizedBox(height: 12),
    ];
  }

  Widget _driveTile(InstallController c, DriveChoice d) {
    final sel = c.target != null && d.same(c.target!);
    final name = d.device != null
        ? (d.label.isEmpty ? d.device! : '${d.device} (${d.label})')
        : (d.label.isEmpty ? '${d.letter}: sürücüsü' : '${d.letter}: sürücüsü (${d.label})');
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
                  Text(d.device != null
                      ? '$disk · ${d.fstype} · toplam ${_gb(d.sizeBytes)} · en fazla ${_gb(d.freeBytes)} yer açılabilir'
                          '${d.mountpoint == '/' || d.mountpoint == '/home' ? ' · şu an çalışan sistemin bölümü' : ''}'
                      : '$disk · toplam ${_gb(d.sizeBytes)} · ${_gb(d.freeBytes)} boş',
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
      const Text('Yeni sistem için ne kadar yer ayıralım?',
          style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      _detail(widget.distro.family == DistroFamily.windows
          ? 'Windows için en az 64 GB gerekir; 80 GB rahat eder. Çok program kuracaksan daha fazlasını seç.'
          : 'Çoğu kişi için 30 GB yeter. Çok program kuracaksan daha fazlasını seç.'),
      const SizedBox(height: 10),
      _sizeChips(c),
      const SizedBox(height: 22),
      const Text('Neler olacak?', style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      if (c.linuxHost) ...[
        _bullet(Icons.content_cut_rounded, '${c.target!.device} bölümü küçültülür ve yaklaşık $gb GB boş (ayrılmamış) yer açılır.'),
        _bullet(Icons.playlist_add_rounded, 'GRUB açılış menüsüne "BesideOS" adlı bir giriş eklenir; ${_sys(c)} ISO dosyası olduğu yerde kalır.'),
      ] else ...[
        _bullet(Icons.content_cut_rounded,
            c.target != null && !c.target!.isWindows && c.drives.length > 1
                ? '${c.target!.letter}: sürücüsünde yaklaşık $gb GB boş yer açılır.'
                : "Windows'un yanında yaklaşık $gb GB boş yer açılır."),
        _bullet(Icons.file_copy_rounded, '${_sys(c)} kurulum dosyaları bu yere kopyalanır.'),
      ],
      _bullet(Icons.restart_alt_rounded,
          'Hazır olunca sen yeniden başlatırsın. Açılışta menü 5 saniye görünür, ${_sys(c)} kurulumu seçili gelir; kurulu sistemlerin de aynı listede.'),
      const SizedBox(height: 6),
      _diskAdvice(c),
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

  Future<void> _confirmRestart(InstallController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şimdi yeniden başlatalım mı?'),
        content: Text('Bilgisayar 15 saniye sonra yeniden başlayacak. Açılışta menü 5 saniye görünür: ${_sys(c)} kurulumu seçili gelir, '
            'istersen kurulu bir sistemi seçebilirsin. Açık işlerini şimdi kaydet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Şimdi değil')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet, yeniden başlat')),
        ],
      ),
    );
    if (ok == true) await c.restart();
  }

  Future<void> _confirmAndApply(InstallController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Başlayalım mı?'),
        content: Text(c.linuxHost
            ? 'Bir bölüm küçültülecek ve GRUB menüsüne bir giriş eklenecek. Bilgisayar kendiliğinden yeniden BAŞLAMAZ; bunu sonra sen seçeceksin.'
            : 'Kurulum hazırlanacak: boş yer açılacak ve dosyalar kopyalanacak. Bilgisayar kendiliğinden yeniden BAŞLAMAZ; bunu sonra sen seçeceksin.'),
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
        if (!c.linuxHost || c.drives.isNotEmpty) ...[
          const SizedBox(height: 12),
          ..._drivePicker(c),
          const Text('Daha küçük bir alan seçmeyi deneyebilirsin:',
              style: TextStyle(color: kText, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _sizeChips(c),
        ],
      ]);
}
