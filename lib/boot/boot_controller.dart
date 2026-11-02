import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../install/process_runner.dart';

/// One firmware boot entry as boot-entries.ps1 lists it.
class BootEntry {
  const BootEntry({required this.id, required this.title, required this.description, required this.path});
  final String id;
  final String title;
  final String description;
  final String path;

  factory BootEntry.fromJson(Map<String, dynamic> j) => BootEntry(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        description: '${j['description'] ?? ''}',
        path: '${j['path'] ?? ''}',
      );

  /// BesideOS' own temporary installer entry: it exists only until the install is undone or finished.
  bool get isInstaller => description.toLowerCase().contains('besideos');

  /// The Windows boot manager of this computer.
  bool get isWindows => id == '{bootmgr}' || path.toLowerCase().endsWith('bootmgfw.efi');

  /// USB, DVD and network starts the firmware lists itself: they name no loader file. (Linux entries also show up as
  /// "Firmware Application" in bcdedit, but they do name their loader, e.g. \EFI\ubuntu\shimx64.efi.)
  bool get isDevice => path.trim().isEmpty && !isWindows;

  /// A system the person can pick: Windows, or a Linux/other loader that is not a device or BesideOS' installer entry.
  bool get isSystem => !isDevice && !isInstaller;

  /// Name shown to the person.
  String get label => isWindows ? 'Windows' : description.isEmpty ? id : description;
}

enum BootPhase { idle, loading, ready, working, failed }

/// Which installed system starts next, or by default. Needs administrator rights for every call (bcdedit).
class BootController extends ChangeNotifier {
  BootController({required this.runner, required this.script, required this.workDir});
  final ProcessRunner runner;
  final File script;
  final Directory workDir;

  BootPhase _phase = BootPhase.idle;
  List<BootEntry> _entries = const [];
  List<String> _order = const [];
  List<String> _sequence = const [];
  String? _error;
  String? _notice;
  bool _restarting = false;
  bool _disposed = false;

  BootPhase get phase => _phase;
  String? get error => _error;
  String? get notice => _notice;
  bool get restarting => _restarting;
  bool get busy => _phase == BootPhase.loading || _phase == BootPhase.working;

  /// Systems the person can choose, in the order the firmware tries them.
  List<BootEntry> get systems {
    final all = _entries.where((e) => e.isSystem).toList();
    all.sort((a, b) => _rank(a.id).compareTo(_rank(b.id)));
    return all;
  }

  /// Devices and installer entries, kept apart (shown only on request).
  List<BootEntry> get others => _entries.where((e) => !e.isSystem).toList();

  int _rank(String id) {
    final i = _order.indexWhere((o) => o.toLowerCase() == id.toLowerCase());
    return i < 0 ? 1 << 20 : i;
  }

  /// The first system in the firmware's list starts by default.
  bool isDefault(BootEntry e) => systems.isNotEmpty && systems.first.id == e.id;

  /// Chosen for the next start only.
  bool isNext(BootEntry e) => _sequence.any((s) => s.toLowerCase() == e.id.toLowerCase());

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _set(BootPhase p) {
    _phase = p;
    notifyListeners();
  }

  void _fail(String m) {
    _error = m;
    _set(BootPhase.failed);
  }

  File get _out => File('${workDir.path}${Platform.pathSeparator}boot-entries.json');

  /// Reads the systems. [refresh] re-reads after a change without swapping the page for the loading view.
  Future<void> load({bool refresh = false}) async {
    if (busy && !refresh) return;
    _error = null;
    if (!refresh) _set(BootPhase.loading);
    try {
      await workDir.create(recursive: true);
      if (_out.existsSync()) _out.deleteSync();
      final r = await runner.script(script, ['-Action', 'list', '-OutFile', _out.path], elevated: true);
      if (r.exitCode == kElevationDeclined) return _fail('Yönetici izni verilmedi.');
      if (r.exitCode != 0 || !_out.existsSync()) return _fail('Sistemler okunamadı (kod ${r.exitCode}). Bu bilgisayar UEFI ile açılmıyor olabilir.');
      final j = jsonDecode(utf8.decode(_out.readAsBytesSync(), allowMalformed: true)) as Map<String, dynamic>;
      _entries = [for (final e in (j['entries'] as List? ?? const [])) BootEntry.fromJson(e as Map<String, dynamic>)];
      _order = [for (final o in (j['order'] as List? ?? const [])) '$o'];
      _sequence = [for (final s in (j['sequence'] as List? ?? const [])) '$s'];
      _set(BootPhase.ready);
    } catch (e) {
      _fail('Beklenmeyen hata: $e');
    }
  }

  /// The next start (only) opens [e]; afterwards the usual order applies again.
  Future<void> startNext(BootEntry e) => _change('next', e, 'Bir sonraki açılışta ${e.label} açılacak. Sonrasında her şey eskisi gibi.');

  /// [e] becomes the first system, started whenever nothing else is chosen.
  Future<void> makeDefault(BootEntry e) => _change('default', e, 'Artık varsayılan olarak ${e.label} açılacak.');

  Future<void> _change(String action, BootEntry e, String done) async {
    if (busy || !systems.any((s) => s.id == e.id)) return;
    _error = null;
    _notice = null;
    _set(BootPhase.working);
    try {
      final r = await runner.script(script, ['-Action', action, '-Id', e.id, '-Execute'], elevated: true);
      if (r.exitCode == kElevationDeclined) {
        _error = 'Yönetici izni verilmedi; hiçbir şey değişmedi.';
        _set(BootPhase.ready);
        return;
      }
      if (r.exitCode != 0) {
        _error = 'Değiştirilemedi (kod ${r.exitCode}).';
        _set(BootPhase.ready);
        return;
      }
      await load(refresh: true);
      if (_phase == BootPhase.ready) {
        _notice = done;
        notifyListeners();
      }
    } catch (err) {
      _error = 'Beklenmeyen hata: $err';
      _set(BootPhase.ready);
    }
  }

  /// Restarts after the person's own confirmation; Windows counts down 15 seconds and [cancelRestart] can stop it.
  Future<void> restart() async {
    if (_restarting) return;
    _restarting = true;
    notifyListeners();
    try {
      final r = await runner.exec('shutdown', ['/r', '/t', '15', '/c', 'BesideOS: seçtiğin sistem için yeniden başlatılıyor.']);
      if (r.exitCode != 0) {
        _restarting = false;
        _error = 'Yeniden başlatılamadı. Bilgisayarı kendin yeniden başlat.';
      }
    } catch (_) {
      _restarting = false;
      _error = 'Yeniden başlatılamadı. Bilgisayarı kendin yeniden başlat.';
    }
    notifyListeners();
  }

  Future<void> cancelRestart() async {
    if (!_restarting) return;
    try {
      await runner.exec('shutdown', ['/a']);
    } catch (_) {}
    _restarting = false;
    notifyListeners();
  }
}
