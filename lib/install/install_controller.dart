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

/// What the user must type before anything on the disk is touched.
const installConfirmWord = 'KUR';

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

Directory defaultWorkDir() {
  final base = Platform.environment['LOCALAPPDATA'];
  final root = base == null || base.isEmpty ? Directory.systemTemp.path : base;
  return Directory('$root${Platform.pathSeparator}BesideOS${Platform.pathSeparator}work');
}

/// Download -> inspect ISO -> probe host -> plan -> (user confirms) -> apply.
/// Nothing on the disk changes before [apply], which needs the confirmation word.
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

  Future<void> begin(IsoAsset iso, IsoArch arch) async {
    if (busy) return;
    _error = _refusal = null;
    _plan = null;
    try {
      await workDir.create(recursive: true);
      if (_iso == null || _isoName != iso.fileName || !_iso!.existsSync()) {
        _set(InstallPhase.downloading);
        await download.start(iso);
        final f = download.file;
        if (download.phase != DownloadPhase.verified || f == null) {
          _fail(download.error ?? 'ISO indirilemedi veya doğrulanamadı.');
          return;
        }
        _iso = f;
        _isoName = iso.fileName;
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
      await _makePlan();
    } catch (e) {
      _fail('Beklenmeyen hata: $e');
    }
  }

  /// Re-plans with another Linux size, reusing the ISO and host facts already collected.
  Future<void> replan(int gib) async {
    if (_phase != InstallPhase.ready && _phase != InstallPhase.refused) return;
    _linuxGiB = gib;
    _plan = null;
    _refusal = null;
    try {
      await _makePlan();
    } catch (e) {
      _fail('Beklenmeyen hata: $e');
    }
  }

  Future<void> _makePlan() async {
    _set(InstallPhase.planning);
    final req = _f('request.json');
    await req.writeAsString(jsonEncode({'linux_space_bytes': _linuxGiB * _gib}));
    final r = await runner.exec(engine.plan.path, [
      '--host', _f('facts.json').path,
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

  /// Applies the plan and reboots into the installer. Does nothing unless [typed] is the confirmation word.
  Future<void> apply(String typed) async {
    if (_phase != InstallPhase.ready || typed.trim().toUpperCase() != installConfirmWord) return;
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
