import 'dart:io';

import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/download/download_controller.dart';
import 'package:besideos_site/download/downloader.dart';
import 'package:besideos_site/install/engine.dart';
import 'package:besideos_site/install/install_controller.dart';
import 'package:besideos_site/install/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pretends to be besideos-grub.sh: records the calls and answers `check` from [checkOut]/[checkExit].
class FakeGrubRunner implements ProcessRunner {
  final calls = <String>[];
  String checkOut = 'OK: ISO label: X\nWARN: Secure Boot is on\nOK: GRUB menu reads custom.cfg\n';
  int checkExit = 0, applyExit = 0;
  String drives = '[{"disk":0,"partition":1,"letter":"/dev/sda1","device":"/dev/sda1","label":"DATA","fstype":"ext4",'
      '"mountpoint":"/mnt/data","system":false,"disk_name":"Disk","disk_size_bytes":1000000000000,'
      '"size_bytes":900000000000,"free_bytes":400000000000,"is_windows":false}]';

  @override
  Future<RunResult> exec(String exe, List<String> args) async {
    calls.add('$exe ${args.join(' ')}');
    return const RunResult(0, '', '');
  }

  @override
  Future<RunResult> script(File script, List<String> args, {bool elevated = false}) async {
    calls.add('${args.first}${elevated ? '*' : ''} ${args.where((a) => a.startsWith('--')).join(' ')}');
    if (args.first == 'check') return RunResult(checkExit, checkOut, '');
    if (args.first == 'disks') {
      File(args[args.indexOf('--out') + 1]).writeAsStringSync(drives);
      return const RunResult(0, '', '');
    }
    return RunResult(applyExit, applyExit == 0 ? 'OK: done' : 'REFUSED: an earlier BesideOS entry exists', '');
  }
}

void main() {
  late Directory tmp;
  late File iso;
  late FakeGrubRunner runner;
  late InstallController c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('linuxctl');
    iso = File('${tmp.path}/mint.iso')..writeAsStringSync('iso');
    runner = FakeGrubRunner();
    c = InstallController(
      runner: runner,
      ownerId: 'linux-mint',
      engine: Engine.linux(File('${tmp.path}/besideos-grub.sh')),
      workDir: Directory('${tmp.path}/work'),
      download: DownloadController(downloader: Downloader(), targetDir: tmp),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('check -> ready -> prepare needs the confirmation and runs elevated', () async {
    await c.beginWithFile(iso, IsoArch.x86_64);
    expect(c.linuxHost, isTrue);
    expect(c.phase, InstallPhase.ready);
    expect(c.target!.device, '/dev/sda1');
    expect(c.plan!.shrinkBytes, 30 * (1 << 30));
    expect(c.plan!.steps.first, contains('/dev/sda1'));
    expect(c.plan!.risks.any((r) => r.startsWith('Secure Boot açık')), isTrue);

    await c.apply(confirmed: false);
    expect(c.phase, InstallPhase.ready);
    await c.apply(confirmed: true);
    expect(c.phase, InstallPhase.applied);
    expect(runner.calls, [
      'check --iso --allow-experimental',
      'disks* --out',
      'prepare* --iso --name --execute --allow-experimental --shrink-dev --shrink-gb',
    ]);
  });

  test('a refused ISO shows the script\'s reason and changes nothing', () async {
    runner
      ..checkExit = 2
      ..checkOut = 'OK: a\nREFUSED: this ISO has no known loopback boot recipe yet\n';
    await c.beginWithFile(iso, IsoArch.x86_64);
    expect(c.phase, InstallPhase.refused);
    expect(c.refusal, contains('Canlı'));
    expect(runner.calls.any((x) => x.startsWith('prepare')), isFalse);
  });

  test('a size the partition cannot give is refused, a smaller one is accepted', () async {
    runner.drives = runner.drives.replaceAll('"free_bytes":400000000000', '"free_bytes":40000000000');
    await c.beginWithFile(iso, IsoArch.x86_64);
    expect(c.phase, InstallPhase.ready);
    await c.replan(50);
    expect(c.phase, InstallPhase.refused);
    expect(c.refusal, contains('en fazla 37 GB'));
    await c.replan(20);
    expect(c.phase, InstallPhase.ready);
    expect(c.plan!.shrinkBytes, 20 * (1 << 30));
  });

  test('no partition with enough room means a refusal, not a plan', () async {
    runner.drives = '[]';
    await c.beginWithFile(iso, IsoArch.x86_64);
    expect(c.phase, InstallPhase.refused);
    expect(c.refusal, contains('yer açılabilecek bir bölüm bulunamadı'));
  });

  test('undo runs elevated and a failed prepare reports the reason', () async {
    await c.beginWithFile(iso, IsoArch.x86_64);
    runner.applyExit = 2;
    await c.apply(confirmed: true);
    expect(c.phase, InstallPhase.failed);
    expect(c.error, contains('an earlier BesideOS entry exists'));
    runner.applyExit = 0;
    await c.undo();
    expect(c.phase, InstallPhase.undone);
    expect(runner.calls.last, 'undo* --name --execute');
  });

  test('restart waits for the countdown and can be cancelled; it never restarts by itself', () async {
    await c.beginWithFile(iso, IsoArch.x86_64);
    await c.apply(confirmed: true);
    expect(runner.calls.any((x) => x.contains('reboot')), isFalse);
    await c.restart();
    expect(c.restarting, isTrue);
    await c.cancelRestart();
    expect(c.restarting, isFalse);
    expect(runner.calls.any((x) => x.contains('reboot')), isFalse);
  });
}
