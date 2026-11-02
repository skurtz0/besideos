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
const _gib = 1 << 30;

class InstallPlan {
  const InstallPlan({required this.steps, required this.risks, required this.shrinkBytes});
  final List<String> steps;
  final List<String> risks;
  final int shrinkBytes;

  factory InstallPlan.fromJson(Map<String, dynamic> j) => InstallPlan(
        steps: [for (final s in j['steps'] as List) '${(s as Map)['description']}'],
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
  });
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
      );

  bool same(DriveChoice o) => disk == o.disk && partition == o.partition;
}

Directory defaultWorkDir() {
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
  });

  final ProcessRunner runner;
  final Engine engine;
  final Directory workDir;
  final DownloadController download;

  InstallPhase _phase = InstallPhase.idle;
  String? _error;
  String? _refusal;
  InstallPlan? _plan;
  int _linuxGiB = defaultLinuxSpaceGiB;
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

  /// A previous run left changes behind that [undo] can reverse.
  bool get hasPendingState => _f('apply-state.json').existsSync();

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
      final errs = lines.where((l) => l.contains('[ERROR]') || l.contains('FATAL')).toList();
      final pick = (errs.isNotEmpty ? errs : lines).reversed.take(3).toList().reversed;
      return pick.isEmpty ? '' : '\n${pick.join('\n')}';
    } catch (_) {
      return '';
    }
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

  /// Applies the plan and reboots into the installer. Does nothing unless the user [confirmed] (backup box + dialog).
  Future<void> apply({required bool confirmed}) async {
    if (_phase != InstallPhase.ready || !confirmed) return;
    _set(InstallPhase.applying);
    try {
      final r = await runner.script(
        engine.apply,
        ['-PlanFile', _f('plan.json').path, '-Execute', '-Reboot', '-OutDir', workDir.path],
        elevated: true,
      );
      if (r.exitCode == kElevationDeclined) {
        _fail('Yönetici izni verilmedi; hiçbir şey değiştirilmedi.');
      } else if (r.exitCode != 0) {
        _fail('Kurulum hazırlığı başarısız oldu.${_logTail('apply.log')}');
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
        ['-Undo', '-Execute', '-OutDir', workDir.path],
        elevated: true,
      );
      if (r.exitCode == kElevationDeclined) {
        _fail('Yönetici izni verilmedi; geri alınmadı.');
      } else if (r.exitCode != 0) {
        _fail('Geri alma başarısız oldu.${_logTail('apply.log')}');
      } else {
        _set(InstallPhase.undone);
      }
    } catch (e) {
      _fail('Beklenmeyen hata: $e');
    }
  }
}
