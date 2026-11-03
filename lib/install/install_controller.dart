import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../catalog/distro.dart';
import '../download/download_controller.dart';
import 'engine.dart';
import 'process_runner.dart';

enum InstallPhase {
  idle,
  downloading,
  inspecting,
  probing,
  planning,
  ready,
  refused,
  applying,
  applied,
  failed,
  undoing,
  undone,
}

const linuxSpaceChoicesGiB = [20, 30, 50, 80, 120];
const defaultLinuxSpaceGiB = 30;
const windowsSpaceGiB = 80;
const _gib = 1 << 30;

/// Written by besideos-grub.sh while its GRUB entry exists.
const kLinuxStateDir = '/var/lib/besideos';

class InstallPlan {
  const InstallPlan({required this.steps, required this.risks, required this.shrinkBytes});
  final List<String> steps;
  final List<String> risks;
  final int shrinkBytes;

  factory InstallPlan.fromJson(Map<String, dynamic> j) => InstallPlan(
        // The restart is the person's own button press afterwards, never part of the run, so it is not listed as a step.
        steps: [
          for (final s in j['steps'] as List)
            if (((s as Map)['step'] as Map?)?['type'] != 'reboot') '${s['description']}'
        ],
        risks: [for (final r in j['risks'] as List) '$r'],
        shrinkBytes: (j['total_shrink_bytes'] as num).toInt(),
      );
}

/// An NTFS drive the probe found that Linux space can be carved from (one entry of drives.json).
class DriveChoice {
  const DriveChoice({
    required this.disk,
    required this.partition,
    required this.letter,
    required this.label,
    required this.diskName,
    required this.diskSizeBytes,
    required this.sizeBytes,
    required this.freeBytes,
    required this.isWindows,
    this.device,
    this.fstype,
    this.mountpoint,
  });

  /// Linux host: the partition's device node (/dev/sda1) and file system; null on Windows.
  final String? device;
  final String? fstype;
  final String? mountpoint;
  final int disk;
  final int partition;
  final String letter;
  final String label;
  final String diskName;
  final int diskSizeBytes;
  final int sizeBytes;
  final int freeBytes;
  final bool isWindows;

  factory DriveChoice.fromJson(Map<String, dynamic> j) => DriveChoice(
        disk: (j['disk'] as num).toInt(),
        partition: (j['partition'] as num).toInt(),
        letter: '${j['letter']}',
        label: '${j['label'] ?? ''}',
        diskName: '${j['disk_name'] ?? ''}',
        diskSizeBytes: (j['disk_size_bytes'] as num?)?.toInt() ?? 0,
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
        freeBytes: (j['free_bytes'] as num?)?.toInt() ?? 0,
        isWindows: j['is_windows'] == true,
        device: j['device'] as String?,
        fstype: j['fstype'] as String?,
        mountpoint: j['mountpoint'] as String?,
      );

  bool same(DriveChoice o) => disk == o.disk && partition == o.partition;
}

/// Turkish text for the script's warnings; null drops one that is only noise for the person.
String? turkishWarning(String w) {
  if (w.contains('no UEFI boot file') || w.contains('without root')) return null;
  if (w.contains('Secure Boot is on')) {
    return 'Secure Boot açık. İmzasız çekirdekli ISO\'lar açılmayabilir; kurulum menüsü gelmezse BIOS\'tan Secure Boot\'u kapat.';
  }
  if (w.contains('the ISO is on a disk you may want')) {
    return 'ISO dosyası, kurulum yapabileceğin bir diskte duruyor. Kurulumcu kendi ISO\'sunun bulunduğu bölümü silemez; '
        'yeni sistemi, BesideOS\'un açtığı boş alana kur.';
  }
  if (w.contains('BIOS boot')) return 'Bilgisayar BIOS (eski) modunda açılmış görünüyor; UEFI önerilir.';
  return w;
}

/// Turkish text for the refusals besideos-grub.sh prints in English; unknown ones are shown as they are.
String? turkishScriptMessage(String? m) {
  if (m == null) return null;
  const known = <String, String>{
    'no known loopback boot recipe':
        'Bu ISO dosyası GRUB ile doğrudan açılamıyor (içinde ISO\'dan açılış için gereken bilgi yok). '
            'Büyük olasılıkla küçük "netinst" gibi bir kurulum dosyası; aynı sistemin "Canlı" sürümünü seçmeyi dene.',
    'is experimental': 'Bu ISO türü için açılış yöntemi henüz denenmedi.',
    'cannot read the file system the ISO is on':
        'ISO dosyası GRUB\'un okuyamadığı bir dosya sisteminde. Dosyayı ext4, btrfs, xfs ya da FAT32 bir diske kopyala.',
    'encrypted disk': 'ISO dosyası şifreli bir diskte; GRUB okuyamaz. Şifresiz bir diske kopyala.',
    'does not read custom.cfg': 'Bu bilgisayarın GRUB menüsü özel girişleri okumuyor; BesideOS burada çalışamaz.',
    'GRUB was not found': 'Bu bilgisayarda GRUB bulunamadı (systemd-boot gibi başka bir açılış yöneticisi olabilir).',
    'xorriso is needed': 'ISO\'nun içine bakmak için "xorriso" programı gerekir. Kur ve tekrar dene.',
    'not a readable ISO': 'Bu dosya okunabilir bir ISO görüntüsü değil.',
    'ISO file not found': 'ISO dosyası bulunamadı.',
    'only GPT disks': 'Yalnızca GPT bölümlü diskler destekleniyor.',
  };
  for (final e in known.entries) {
    if (m.contains(e.key)) return e.value;
  }
  return m;
}

Directory defaultWorkDir() {
  if (Platform.isLinux) {
    final env = Platform.environment;
    final data = env['XDG_DATA_HOME'] ?? (env['HOME'] == null ? null : '${env['HOME']}/.local/share');
    if (data != null && data.isNotEmpty) return Directory('$data/BesideOS/work');
  }
  final base = Platform.environment['LOCALAPPDATA'];
  final root = base == null || base.isEmpty ? Directory.systemTemp.path : base;
  return Directory('$root${Platform.pathSeparator}BesideOS${Platform.pathSeparator}work');
}

/// Download -> inspect ISO -> probe host -> plan -> (user confirms) -> apply.
/// Nothing on the disk changes before [apply], which needs an explicit `confirmed: true`.
class InstallController extends ChangeNotifier {
  InstallController({
    required this.runner,
    required this.engine,
    required this.workDir,
    required this.download,
    this.ownerId,
    this.ownerName,
  });

  /// Which distro page this controller belongs to (Linux host: the GRUB entry exists once, for one distro).
  final String? ownerId;

  /// Name shown in the GRUB menu ("BesideOS: 5 saniye içinde kurulacak: Ubuntu").
  final String? ownerName;
  final ProcessRunner runner;
  final Engine engine;
  final Directory workDir;
  final DownloadController download;

  InstallPhase _phase = InstallPhase.idle;
  String? _error;
  String? _refusal;
  InstallPlan? _plan;
  int _linuxGiB = defaultLinuxSpaceGiB;
  int _recommendedGiB = defaultLinuxSpaceGiB;
  File? _iso;
  String? _isoName;
  bool _disposed = false;
  List<DriveChoice> _drives = const [];
  DriveChoice? _target;

  /// Drives Linux space can come from; the picker is only worth showing when there is more than one.
  List<DriveChoice> get drives => _drives;
  DriveChoice? get target => _target;

  InstallPhase get phase => _phase;
  String? get error => _error;
  String? get refusal => _refusal;
  InstallPlan? get plan => _plan;
  int get linuxGiB => _linuxGiB;

  /// The size marked as recommended (Windows needs far more room than a Linux desktop).
  int get recommendedGiB => _recommendedGiB;

  /// Sets the recommended size and selects it. Only before a run starts.
  void useSpace(int gib) {
    if (busy || _phase != InstallPhase.idle) return;
    _recommendedGiB = gib;
    _linuxGiB = gib;
    notifyListeners();
  }

  /// Linux host: no partitions are touched, so there is no space/drive choice, only a GRUB entry to add.
  bool get linuxHost => engine.isLinux;

  /// A previous run left changes behind that [undo] can reverse.
  bool get hasPendingState {
    if (!linuxHost) return _f('apply-state.json').existsSync();
    // One GRUB entry per distro. The first version wrote a single unnamed one; linux-owner says whose it was.
    if (File('$kLinuxStateDir/$_entryName.state').existsSync()) return true;
    return File('$kLinuxStateDir/state').existsSync() && _linuxOwner() == ownerId;
  }

  /// Name of this distro's GRUB entry (besideos-grub.sh --name).
  String get _entryName => ownerId ?? 'default';

  File get _ownerFile => _f('linux-owner');
  String? _linuxOwner() {
    try {
      final t = _ownerFile.readAsStringSync().trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  bool get busy =>
      _phase == InstallPhase.downloading ||
      _phase == InstallPhase.inspecting ||
      _phase == InstallPhase.probing ||
      _phase == InstallPhase.planning ||
      _phase == InstallPhase.applying ||
      _phase == InstallPhase.undoing;

  File _f(String name) => File('${workDir.path}${Platform.pathSeparator}$name');

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _restartTimer?.cancel();
    super.dispose();
  }

  void _set(InstallPhase p) {
    _phase = p;
    notifyListeners();
  }

  void _fail(String message) {
    _error = message;
    _set(InstallPhase.failed);
  }

  Future<void> _rm(File f) async {
    try {
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  /// Last lines of a log the scripts wrote, for error messages.
  String _logTail(String name) {
    try {
      final lines = const LineSplitter().convert(utf8.decode(_f(name).readAsBytesSync(), allowMalformed: true));
      // the script logs the reason as "... [ERROR] FAIL: <reason>"; that is what the person needs to read
      final fails = lines.where((l) => l.contains('] FAIL:')).toList();
      final errs = lines.where((l) => l.contains('[ERROR]') || l.contains('FATAL')).toList();
      final src = fails.isNotEmpty ? fails : (errs.isNotEmpty ? errs : lines);
      final pick = src.reversed.take(fails.isNotEmpty ? 2 : 3).toList().reversed.map((l) => l.replaceFirst(RegExp(r'^\S+ \[\w+\] (FAIL: )?'), ''));
      return pick.isEmpty ? '' : '\n${pick.join('\n')}';
    } catch (_) {
      return '';
    }
  }

  /// The reason line the Linux script printed (REFUSED/ERROR), for error messages.
  String _scriptReason(RunResult r) {
    final all = '${r.stdout}\n${r.stderr}'.split('\n');
    final m = all.where((l) => l.startsWith('REFUSED: ') || l.startsWith('ERROR: ')).toList();
    return m.isEmpty ? '' : '\n${m.last.replaceFirst(RegExp(r'^\w+: '), '')}';
  }

  /// Downloads (and verifies) the official ISO, then inspects, probes and plans.
  Future<void> begin(IsoAsset iso, IsoArch arch) => _run(arch, asset: iso);

  /// Uses an ISO file the person already has: no download, no checksum to type in.
  Future<void> beginWithFile(File isoFile, IsoArch arch) => _run(arch, local: isoFile);

  /// Starts again the way the last attempt started (same ISO source), e.g. after an error.
  Future<void> retry() {
    final a = _lastArch;
    if (a == null) return Future.value();
    final asset = _lastAsset;
    return asset != null ? begin(asset, a) : (_iso == null ? Future.value() : beginWithFile(_iso!, a));
  }

  IsoAsset? _lastAsset;
  IsoArch? _lastArch;
  bool _localIso = false;

  /// True when the ISO is a file the person picked rather than the catalog's download.
  bool get isLocalIso => _localIso;

  /// File name of the ISO in use (picked or downloaded), for messages.
  String? get isoFileName => _iso?.uri.pathSegments.last;

  Future<void> _run(IsoArch arch, {IsoAsset? asset, File? local}) async {
    if (busy) return;
    _error = _refusal = null;
    _plan = null;
    _lastArch = arch;
    _lastAsset = asset;
    _localIso = local != null;
    try {
      await workDir.create(recursive: true);
      if (local != null) {
        if (!local.existsSync() || !local.path.toLowerCase().endsWith('.iso')) {
          _fail('Seçilen dosya bulunamadı ya da bir ISO dosyası değil.');
          return;
        }
        _iso = local;
        _isoName = null;
      } else if (_iso == null || _isoName != asset!.fileName || !_iso!.existsSync()) {
        _set(InstallPhase.downloading);
        await download.start(asset!);
        final f = download.file;
        if (download.phase != DownloadPhase.verified || f == null) {
          _fail(download.error ?? 'ISO indirilemedi veya doğrulanamadı.');
          return;
        }
        _iso = f;
        _isoName = asset.fileName;
      }

      if (linuxHost) {
        await _checkLinux();
        return;
      }

      _set(InstallPhase.inspecting);
      final isoJson = _f('iso.json');
      await _rm(isoJson);
      var r = await runner.script(engine.inspect, [
        '-IsoPath', _iso!.path,
        '-Arch', arch == IsoArch.arm64 ? 'arm64' : 'x86_64',
        '-OutFile', isoJson.path,
      ]);
      if (r.exitCode != 0 || !isoJson.existsSync()) {
        _fail('ISO içeriği incelenemedi. ${r.stderr.trim()}'.trim());
        return;
      }

      _set(InstallPhase.probing);
      await _rm(_f('facts.json'));
      r = await runner.script(engine.probe, ['-OutDir', workDir.path], elevated: true);
      if (r.exitCode == kElevationDeclined) {
        _fail('Yönetici izni verilmedi; disk bilgisi okunamadı. Hiçbir şey değiştirilmedi.');
        return;
      }
      if (r.exitCode != 0 || !_f('facts.json').existsSync()) {
        _fail('Disk bilgisi toplanamadı.${_logTail('probe.log')}');
        return;
      }
      _loadDrives();
      await _makePlan();
    } catch (e) {
      _fail('Beklenmeyen hata: $e');
    }
  }

  /// Linux host: the script's read-only `check` decides whether this ISO can be started from a GRUB entry.
  Future<void> _checkLinux() async {
    _set(InstallPhase.inspecting);
    final r = await runner.script(engine.grub!, ['check', '--iso', _iso!.path, '--allow-experimental']);
    final lines = const LineSplitter().convert(r.stdout);
    String? last(String tag) {
      final m = lines.where((l) => l.startsWith('$tag: ')).toList();
      return m.isEmpty ? null : m.last.substring(tag.length + 2);
    }

    if (r.exitCode == 2) {
      _refusal = turkishScriptMessage(last('REFUSED')) ?? 'Bu ISO bu bilgisayarda açılamıyor.';
      _set(InstallPhase.refused);
      return;
    }
    if (r.exitCode != 0) {
      _fail('ISO kontrol edilemedi. ${last('ERROR') ?? r.stderr.trim()}'.trim());
      return;
    }
    _isoWarnings = [
      for (final l in lines)
        if (l.startsWith('WARN: ') && turkishWarning(l.substring(6)) != null) turkishWarning(l.substring(6))!
    ];

    _set(InstallPhase.probing);
    final out = _f('drives.json');
    await _rm(out);
    final d = await runner.script(engine.grub!, ['disks', '--out', out.path], elevated: true);
    if (d.exitCode == kElevationDeclined) {
      _fail('Yönetici izni verilmedi; diskler okunamadı. Hiçbir şey değiştirilmedi.');
      return;
    }
    if (d.exitCode != 0 || !out.existsSync()) {
      _fail('Diskler okunamadı. ${_scriptReason(d)}'.trim());
      return;
    }
    _loadDrives();
    // The script's minimum is 8 GiB; the smallest choice offered is 20 GiB, so a partition below that is no use.
    _drives = [for (final x in _drives) if (x.freeBytes >= linuxSpaceChoicesGiB.first * _gib) x];
    if (_drives.isEmpty) {
      _refusal = 'Yeni sistem için yer açılabilecek bir bölüm bulunamadı. Küçültülebilen (ext4, btrfs ya da NTFS) ve '
          'en az ${linuxSpaceChoicesGiB.first} GB boş yeri olan bir bölüm gerekir.';
      _set(InstallPhase.refused);
      return;
    }
    _target = _drives.firstWhere((x) => !_isSystemDrive(x), orElse: () => _drives.first);
    _makeLinuxPlan();
  }

  List<String> _isoWarnings = const [];

  bool _isSystemDrive(DriveChoice d) => d.device != null && (d.mountpoint == '/' || d.mountpoint == '/home');

  /// Linux host: the plan for the chosen partition and size (no script run; the real checks happen again in `prepare`).
  void _makeLinuxPlan() {
    final t = _target!;
    if (_linuxGiB * _gib > t.freeBytes) {
      _plan = null;
      _refusal = '${t.device} en fazla ${(t.freeBytes / _gib).floor()} GB yer açabilir. Daha küçük bir alan seç ya da başka bir bölüm kullan.';
      _set(InstallPhase.refused);
      return;
    }
    _refusal = null;
    _plan = InstallPlan(
      steps: [
        '${t.device} bölümü $_linuxGiB GB küçültülür; açılan yer boş (ayrılmamış) kalır.',
        'ISO dosyası olduğu yerde kalır: ${_iso!.path}',
        'GRUB açılış menüsüne "BesideOS" girişi eklenir.',
        'Bir sonraki açılış için bir kereliğine bu giriş seçilir.',
      ],
      risks: [
        'Bölüm küçültme geri alınamayan bir işlem sayılır: "Geri al" bölümü eski boyutuna büyütmeyi dener, ama yeni sistem o alana kurulduysa büyütemez.',
        ..._isoWarnings,
      ],
      shrinkBytes: _linuxGiB * _gib,
    );
    _set(InstallPhase.ready);
  }

  /// Reads drives.json (best effort: without it the planner simply uses the Windows drive).
  void _loadDrives() {
    var list = <DriveChoice>[];
    try {
      final raw = jsonDecode(utf8.decode(_f('drives.json').readAsBytesSync(), allowMalformed: true));
      final items = raw is List ? raw : (raw is Map ? [raw] : const []);
      list = [for (final e in items) DriveChoice.fromJson((e as Map).cast<String, dynamic>())];
    } catch (_) {}
    _drives = list;
    DriveChoice? keep;
    for (final d in list) {
      if (_target != null && d.same(_target!)) keep = d;
    }
    _target = keep ?? (list.isEmpty ? null : list.firstWhere((d) => d.isWindows, orElse: () => list.first));
  }

  /// Re-plans with another Linux size, reusing the ISO and host facts already collected.
  Future<void> replan(int gib) async {
    if (_phase != InstallPhase.ready && _phase != InstallPhase.refused) return;
    _linuxGiB = gib;
    await _replan();
  }

  /// Re-plans taking the Linux space from another drive (e.g. the second disk).
  Future<void> selectDrive(DriveChoice d) async {
    if (_phase != InstallPhase.ready && _phase != InstallPhase.refused) return;
    if (!_drives.any((x) => x.same(d))) return;
    _target = _drives.firstWhere((x) => x.same(d));
    await _replan();
  }

  Future<void> _replan() async {
    if (linuxHost) {
      _makeLinuxPlan();
      return;
    }
    _plan = null;
    _refusal = null;
    try {
      await _makePlan();
    } catch (e) {
      _fail('Beklenmeyen hata: $e');
    }
  }

  /// The planner shrinks `windows_partition`; for another drive a copy of facts.json points it there.
  Future<File> _hostFactsFor(DriveChoice? t) async {
    final facts = _f('facts.json');
    if (t == null) return facts;
    final j = jsonDecode(utf8.decode(facts.readAsBytesSync(), allowMalformed: true)) as Map<String, dynamic>;
    j['windows_partition'] = {'disk': t.disk, 'partition': t.partition};
    final out = _f('facts.plan.json');
    await out.writeAsString(jsonEncode(j));
    return out;
  }

  Future<void> _makePlan() async {
    _set(InstallPhase.planning);
    final req = _f('request.json');
    await req.writeAsString(jsonEncode({'linux_space_bytes': _linuxGiB * _gib}));
    final hostFile = await _hostFactsFor(_target);
    final r = await runner.exec(engine.plan.path, [
      '--host', hostFile.path,
      '--iso', _f('iso.json').path,
      '--request', req.path,
      '--iso-path', _iso!.path,
    ]);
    Map<String, dynamic>? j;
    try {
      j = jsonDecode(r.stdout) as Map<String, dynamic>;
    } catch (_) {}
    if (r.exitCode == 0 && j != null) {
      await _f('plan.json').writeAsString(r.stdout);
      _plan = InstallPlan.fromJson(j);
      _set(InstallPhase.ready);
    } else if (r.exitCode == 2 && j != null) {
      _refusal = '${j['message']}';
      _set(InstallPhase.refused);
    } else {
      _fail('Plan üretilemedi (kod ${r.exitCode}). ${r.stderr.trim()}'.trim());
    }
  }

  bool _restarting = false;
  String? _restartError;

  /// A restart countdown is running (started by [restart], stoppable with [cancelRestart]).
  bool get restarting => _restarting;
  String? get restartError => _restartError;

  /// Restarts into the installer. Only the person's own press of the restart button calls this; [apply] never restarts.
  /// Windows counts down 15 seconds, so [cancelRestart] can still stop it.
  Future<void> restart() async {
    if (_phase != InstallPhase.applied || _restarting) return;
    _restarting = true;
    _restartError = null;
    notifyListeners();
    try {
      if (linuxHost) {
        _restartTimer = Timer(const Duration(seconds: 15), () => runner.exec('systemctl', ['reboot']));
        notifyListeners();
        return;
      }
      final r = await runner.exec('shutdown', ['/r', '/t', '15', '/c', 'BesideOS: kurulum ekranı için yeniden başlatılıyor.']);
      if (r.exitCode != 0) {
        _restarting = false;
        _restartError = 'Yeniden başlatılamadı. Bilgisayarı kendin yeniden başlat.';
      }
    } catch (e) {
      _restarting = false;
      _restartError = 'Yeniden başlatılamadı. Bilgisayarı kendin yeniden başlat.';
    }
    notifyListeners();
  }

  Timer? _restartTimer;

  Future<void> cancelRestart() async {
    if (!_restarting) return;
    _restartTimer?.cancel();
    try {
      if (!linuxHost) await runner.exec('shutdown', ['/a']);
    } catch (_) {}
    _restarting = false;
    notifyListeners();
  }

  /// Prepares the installer (partition, files, one-shot boot entry). Does NOT restart the computer.
  /// Does nothing unless the user [confirmed] (backup box + dialog).
  Future<void> apply({required bool confirmed}) async {
    if (_phase != InstallPhase.ready || !confirmed) return;
    _set(InstallPhase.applying);
    try {
      final r = await runner.script(
        engine.apply,
        linuxHost
            ? [
                'prepare', '--iso', _iso!.path, '--name', _entryName, '--execute', '--allow-experimental',
                if (ownerName != null) ...['--title', ownerName!],
                '--shrink-dev', _target!.device!, '--shrink-gb', '$_linuxGiB',
              ]
            : [
                '-PlanFile', _f('plan.json').path, '-Execute', '-OutDir', workDir.path,
                // 5 second boot menu with the installer selected (falls back to the direct start if it cannot be set up)
                '-Menu',
                if (ownerName != null) ...['-MenuTitle', ownerName!],
              ],
        elevated: true,
      );
      if (r.exitCode == kElevationDeclined) {
        _fail('Yönetici izni verilmedi; hiçbir şey değiştirilmedi.');
      } else if (r.exitCode != 0) {
        _fail('Kurulum hazırlığı başarısız oldu.${linuxHost ? _scriptReason(r) : _logTail('apply.log')}');
      } else {
        _set(InstallPhase.applied);
      }
    } catch (e) {
      _fail('Beklenmeyen hata: $e');
    }
  }

  /// Reverses what a failed or unwanted run changed (boot entry, staging partition, Windows partition size).
  Future<void> undo() async {
    if (busy) return;
    _set(InstallPhase.undoing);
    try {
      final r = await runner.script(
        engine.apply,
        linuxHost ? ['undo', '--name', _entryName, '--execute'] : ['-Undo', '-Execute', '-OutDir', workDir.path],
        elevated: true,
      );
      if (r.exitCode == kElevationDeclined) {
        _fail('Yönetici izni verilmedi; geri alınmadı.');
      } else if (r.exitCode != 0) {
        _fail('Geri alma başarısız oldu.${linuxHost ? _scriptReason(r) : _logTail('apply.log')}');
      } else {
        await _rm(_ownerFile);
        _set(InstallPhase.undone);
      }
    } catch (e) {
      _fail('Beklenmeyen hata: $e');
    }
  }
}
