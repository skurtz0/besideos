import 'dart:convert';
import 'dart:io';

import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/download/download_controller.dart';
import 'package:besideos_site/download/downloader.dart';
import 'package:besideos_site/install/engine.dart';
import 'package:besideos_site/install/install_controller.dart';
import 'package:besideos_site/install/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

const planJson = '''
{"steps":[
 {"description":"Disk 0 bölüm 3 33,5 GiB küçültülecek","step":{"type":"shrink_partition"},"undo":null},
 {"description":"Bilgisayar yeniden başlatılacak","step":{"type":"reboot"},"undo":null}],
 "risks":["Bölüm küçültme geri alınamaz."],"total_shrink_bytes":35970351104}''';
const refusalJson = '{"refused":"not_enough_free_space","message":"Boş yer yetersiz: 53,5 GiB gerekli, 47,9 GiB var."}';

class FakeRunner implements ProcessRunner {
  FakeRunner(this.work);
  final Directory work;
  final calls = <String>[];
  int inspectExit = 0, probeExit = 0, applyExit = 0, planExit = 0, shutdownExit = 0;
  String planOut = planJson;
  String? drivesJson;
  final hosts = <String>[];

  String _arg(List<String> a, String flag) => a[a.indexOf(flag) + 1];

  @override
  Future<RunResult> exec(String exe, List<String> args) async {
    if (exe == 'shutdown') {
      calls.add('shutdown ${args.where((a) => a.startsWith('/')).join(' ')}');
      return RunResult(shutdownExit, '', '');
    }
    hosts.add(File(_arg(args, '--host')).readAsStringSync());
    calls.add('plan ${_arg(args, '--iso-path')} ${File(_arg(args, '--request')).readAsStringSync()}');
    return RunResult(planExit, planOut, '');
  }

  @override
  Future<RunResult> script(File script, List<String> args, {bool elevated = false}) async {
    final name = script.path.split(RegExp(r'[\\/]')).last;
    calls.add('$name${elevated ? '*' : ''} ${args.where((a) => a.startsWith('-')).join(' ')}');
    switch (name) {
      case 'inspect-iso.ps1':
        if (inspectExit == 0) File(_arg(args, '-OutFile')).writeAsStringSync('{}');
        return RunResult(inspectExit, '', 'boom');
      case 'collect-host-facts.ps1':
        if (probeExit == 0) File('${_arg(args, '-OutDir')}/facts.json').writeAsStringSync('{}');
        if (probeExit == 0 && drivesJson != null) File('${_arg(args, '-OutDir')}/drives.json').writeAsStringSync(drivesJson!);
        return RunResult(probeExit, '', '');
      default:
        if (applyExit != 0 && args.contains('-Execute') && !args.contains('-Undo')) {
          File('${_arg(args, '-OutDir')}/apply-state.json').writeAsStringSync('{}');
          File('${_arg(args, '-OutDir')}/apply.log').writeAsStringSync('x [INFO] a\ny [ERROR] FAIL: shrink impossible\n');
        }
        if (args.contains('-Undo') && applyExit == 0) {
          final s = File('${_arg(args, '-OutDir')}/apply-state.json');
          if (s.existsSync()) s.deleteSync();
        }
        return RunResult(applyExit, '', '');
    }
  }
}

class FakeDownload extends DownloadController {
  FakeDownload(this.dir, {this.ok = true}) : super(downloader: Downloader(), targetDir: Directory.systemTemp);
  final Directory dir;
  final bool ok;
  DownloadPhase ph = DownloadPhase.idle;
  File? f;
  int starts = 0;
  @override
  DownloadPhase get phase => ph;
  @override
  File? get file => f;
  @override
  String? get error => ph == DownloadPhase.failed ? 'İndirme başarısız: ağ' : null;
  @override
  Future<void> start(IsoAsset iso) async {
    starts++;
    if (ok) {
      f = File('${dir.path}/${iso.fileName}')..writeAsStringSync('iso');
      ph = DownloadPhase.verified;
    } else {
      ph = DownloadPhase.failed;
    }
    notifyListeners();
  }
}

const iso = IsoAsset(
    arch: IsoArch.x86_64, url: 'https://e.org/a.iso', checksumUrl: 'https://e.org/SUMS', fileName: 'a.iso');

Engine engine() => Engine(
    probe: File('collect-host-facts.ps1'),
    apply: File('apply-plan.ps1'),
    inspect: File('inspect-iso.ps1'),
    plan: File('besideos-plan.exe'));

void main() {
  late Directory tmp;
  late FakeRunner runner;
  late FakeDownload dl;
  late InstallController c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('besideos_install_test');
    runner = FakeRunner(tmp);
    dl = FakeDownload(tmp);
    c = InstallController(runner: runner, engine: engine(), workDir: Directory('${tmp.path}/work'), download: dl);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('happy path: inspect, elevated probe, plan; nothing applied before confirmation', () async {
    await c.begin(iso, IsoArch.x86_64);
    expect(c.phase, InstallPhase.ready);
    expect(c.plan!.steps.first, contains('küçültülecek'));
    expect(c.plan!.risks, isNotEmpty);
    expect(c.plan!.shrinkBytes, 35970351104);
    expect(runner.calls[0], startsWith('inspect-iso.ps1 -IsoPath -Arch -OutFile'));
    expect(runner.calls[1], 'collect-host-facts.ps1* -OutDir');
    expect(runner.calls[2], contains('plan '));
    expect(runner.calls[2], contains('"linux_space_bytes":${30 * (1 << 30)}'));
    expect(runner.calls.any((x) => x.startsWith('apply-plan.ps1')), isFalse);
    expect(File('${tmp.path}/work/plan.json').readAsStringSync(), planJson);
  });

  const twoDrives = '''
[{"disk":0,"partition":3,"letter":"C","label":"","disk_name":"SSD","disk_size_bytes":500000000000,"size_bytes":400000000000,"free_bytes":20000000000,"is_windows":true},
 {"disk":1,"partition":2,"letter":"D","label":"Veri","disk_name":"HDD","disk_size_bytes":1000000000000,"size_bytes":900000000000,"free_bytes":800000000000,"is_windows":false}]''';

  test('without drives.json the planner gets facts.json untouched', () async {
    await c.begin(iso, IsoArch.x86_64);
    expect(c.drives, isEmpty);
    expect(c.target, isNull);
    expect(runner.hosts.single, '{}');
  });

  test('with two drives the Windows drive is the default and another can be picked', () async {
    runner.drivesJson = twoDrives;
    await c.begin(iso, IsoArch.x86_64);
    expect(c.drives.length, 2);
    expect(c.target!.letter, 'C');
    expect(jsonDecode(runner.hosts.last)['windows_partition'], {'disk': 0, 'partition': 3});

    await c.selectDrive(c.drives[1]);
    expect(c.phase, InstallPhase.ready);
    expect(c.target!.letter, 'D');
    expect(jsonDecode(runner.hosts.last)['windows_partition'], {'disk': 1, 'partition': 2});
    // the pick survives a size change
    await c.replan(50);
    expect(jsonDecode(runner.hosts.last)['windows_partition'], {'disk': 1, 'partition': 2});
    expect(runner.calls.any((x) => x.startsWith('apply-plan.ps1')), isFalse);
  });

  test('an unknown drive is ignored', () async {
    runner.drivesJson = twoDrives;
    await c.begin(iso, IsoArch.x86_64);
    final before = runner.hosts.length;
    await c.selectDrive(DriveChoice.fromJson({'disk': 9, 'partition': 9, 'letter': 'Z'}));
    expect(c.target!.letter, 'C');
    expect(runner.hosts.length, before);
  });

  test('useSpace sets the recommended size before a run, and is ignored once a plan exists', () async {
    expect(c.recommendedGiB, defaultLinuxSpaceGiB);
    c.useSpace(windowsSpaceGiB);
    expect(c.linuxGiB, windowsSpaceGiB);
    expect(c.recommendedGiB, windowsSpaceGiB);
    await c.begin(iso, IsoArch.x86_64);
    expect(runner.calls.firstWhere((x) => x.startsWith('plan ')), contains('"linux_space_bytes":${windowsSpaceGiB * (1 << 30)}'));
    c.useSpace(20);
    expect(c.linuxGiB, windowsSpaceGiB);
  });
  test('a picked ISO skips the download and goes straight to inspecting', () async {
    final mine = File('${tmp.path}/mine.iso')..writeAsStringSync('iso');
    await c.beginWithFile(mine, IsoArch.x86_64);
    expect(c.phase, InstallPhase.ready);
    expect(c.isLocalIso, isTrue);
    expect(c.isoFileName, 'mine.iso');
    expect(dl.starts, 0);
    expect(runner.calls.first, startsWith('inspect-iso.ps1'));
    expect(runner.calls.first, isNot(contains('collect-host-facts')));
  });

  test('a picked file that is gone or not an ISO fails clearly and runs nothing', () async {
    await c.beginWithFile(File('${tmp.path}/missing.iso'), IsoArch.x86_64);
    expect(c.phase, InstallPhase.failed);
    expect(c.error, contains('ISO'));
    final txt = File('${tmp.path}/readme.txt')..writeAsStringSync('x');
    await c.beginWithFile(txt, IsoArch.x86_64);
    expect(c.phase, InstallPhase.failed);
    expect(runner.calls, isEmpty);
  });

  test('retry repeats the way the last attempt started', () async {
    final mine = File('${tmp.path}/mine.iso')..writeAsStringSync('iso');
    runner.inspectExit = 1;
    await c.beginWithFile(mine, IsoArch.x86_64);
    expect(c.phase, InstallPhase.failed);
    runner.inspectExit = 0;
    await c.retry();
    expect(c.phase, InstallPhase.ready);
    expect(c.isLocalIso, isTrue);
    expect(dl.starts, 0);
    // and an official start retries as an official start (downloads)
    await c.begin(iso, IsoArch.x86_64);
    expect(c.isLocalIso, isFalse);
    expect(dl.starts, 1);
  });
  test('apply needs explicit confirmation, runs elevated with -Execute and never restarts the computer', () async {
    await c.begin(iso, IsoArch.x86_64);
    await c.apply(confirmed: false);
    expect(c.phase, InstallPhase.ready);
    expect(runner.calls.any((x) => x.startsWith('apply-plan.ps1')), isFalse);
    await c.apply(confirmed: true);
    expect(c.phase, InstallPhase.applied);
    expect(runner.calls.last, 'apply-plan.ps1* -PlanFile -Execute -OutDir -Menu');
    expect(runner.calls.any((x) => x.contains('-Reboot') || x.startsWith('shutdown')), isFalse);
    expect(c.restarting, isFalse);
  });

  test('the plan does not list the restart as a step', () async {
    await c.begin(iso, IsoArch.x86_64);
    expect(c.plan!.steps.any((s) => s.contains('yeniden başlat')), isFalse);
  });

  test('restart happens only when the person asks, with a 15 second countdown that can be cancelled', () async {
    await c.begin(iso, IsoArch.x86_64);
    await c.restart(); // not applied yet: ignored
    expect(runner.calls.any((x) => x.startsWith('shutdown')), isFalse);
    await c.apply(confirmed: true);
    await c.restart();
    expect(runner.calls.last, 'shutdown /r /t /c');
    expect(c.restarting, isTrue);
    await c.cancelRestart();
    expect(runner.calls.last, 'shutdown /a');
    expect(c.restarting, isFalse);
  });

  test('a failed restart tells the person to restart by hand', () async {
    await c.begin(iso, IsoArch.x86_64);
    await c.apply(confirmed: true);
    runner.shutdownExit = 5;
    await c.restart();
    expect(c.restarting, isFalse);
    expect(c.restartError, isNotNull);
  });

  test('apply does nothing before a plan is ready', () async {
    await c.apply(confirmed: true);
    expect(c.phase, InstallPhase.idle);
    expect(runner.calls, isEmpty);
  });

  test('declined UAC at probe fails with nothing changed', () async {
    runner.probeExit = kElevationDeclined;
    await c.begin(iso, IsoArch.x86_64);
    expect(c.phase, InstallPhase.failed);
    expect(c.error, contains('Yönetici izni verilmedi'));
    expect(c.plan, isNull);
  });

  test('planner refusal is shown and a smaller size can be re-planned', () async {
    runner
      ..planExit = 2
      ..planOut = refusalJson;
    await c.begin(iso, IsoArch.x86_64);
    expect(c.phase, InstallPhase.refused);
    expect(c.refusal, contains('Boş yer yetersiz'));
    runner
      ..planExit = 0
      ..planOut = planJson;
    await c.replan(20);
    expect(c.phase, InstallPhase.ready);
    expect(c.linuxGiB, 20);
    expect(runner.calls.last, contains('"linux_space_bytes":${20 * (1 << 30)}'));
    expect(runner.calls.where((x) => x.startsWith('collect-host-facts')).length, 1);
  });

  test('download failure stops before any script runs', () async {
    c = InstallController(
        runner: runner, engine: engine(), workDir: Directory('${tmp.path}/work'), download: FakeDownload(tmp, ok: false));
    await c.begin(iso, IsoArch.x86_64);
    expect(c.phase, InstallPhase.failed);
    expect(c.error, contains('İndirme başarısız'));
    expect(runner.calls, isEmpty);
  });

  test('retry reuses the verified ISO instead of downloading again', () async {
    runner.probeExit = kElevationDeclined;
    await c.begin(iso, IsoArch.x86_64);
    runner.probeExit = 0;
    await c.begin(iso, IsoArch.x86_64);
    expect(c.phase, InstallPhase.ready);
    expect(dl.starts, 1);
  });

  test('failed apply keeps the state and offers undo, which clears it', () async {
    runner.applyExit = 1;
    await c.begin(iso, IsoArch.x86_64);
    await c.apply(confirmed: true);
    expect(c.phase, InstallPhase.failed);
    expect(c.error, contains('shrink impossible'));
    expect(c.hasPendingState, isTrue);
    runner.applyExit = 0;
    await c.undo();
    expect(c.phase, InstallPhase.undone);
    expect(c.hasPendingState, isFalse);
    expect(runner.calls.last, 'apply-plan.ps1* -Undo -Execute -OutDir');
  });

  group('elevatedCommand', () {
    test('quotes paths with spaces and escapes single quotes', () {
      final s = elevatedCommand(r"C:\Program Files\B's\apply.ps1", [r'-OutDir', r'C:\a b\work']);
      expect(s, contains("'\"C:\\Program Files\\B''s\\apply.ps1\"'"));
      expect(s, contains("'\"C:\\a b\\work\"'"));
      expect(s, contains('-Verb RunAs -Wait -PassThru'));
      expect(s, contains('exit $kElevationDeclined'));
    });

    test('rejects arguments with double quotes', () {
      expect(() => elevatedCommand('a.ps1', ['x"y']), throwsArgumentError);
    });

    test('encodes as UTF-16LE base64', () {
      expect(encodePowerShell('A'), base64.encode([0x41, 0x00]));
    });
  });

  group('locateEngine', () {
    test('finds the engine folder next to the executable', () {
      final eng = Directory('${tmp.path}/app/engine')..createSync(recursive: true);
      for (final n in ['collect-host-facts.ps1', 'apply-plan.ps1', 'inspect-iso.ps1', 'besideos-plan.exe']) {
        File('${eng.path}/$n').writeAsStringSync('');
      }
      final e = locateEngine(exePath: '${tmp.path}/app/besideos_site.exe');
      expect(e, isNotNull);
      expect(e!.plan.path, endsWith('besideos-plan.exe'));
    });

    test('returns null when nothing is there', () {
      expect(locateEngine(exePath: '${tmp.path}/nothing/besideos_site.exe'), isNull);
    });
  });
}
