import 'dart:convert';
import 'dart:io';

import 'package:besideos_site/boot/boot_controller.dart';
import 'package:besideos_site/install/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

const listJson = {
  'order': ['{bootmgr}', '{aaa}', '{dev}'],
  'sequence': <String>[],
  'timeout': 0,
  'entries': [
    {'id': '{bootmgr}', 'title': 'Windows Boot Manager', 'description': 'Windows Boot Manager', 'path': r'\EFI\Microsoft\Boot\bootmgfw.efi'},
    {'id': '{aaa}', 'title': 'Firmware Application (101fffff)', 'description': 'Linux Mint', 'path': r'\EFI\ubuntu\shimx64.efi'},
    {'id': '{dev}', 'title': 'Firmware Application (101fffff)', 'description': 'EFI USB Device', 'path': ''},
    {'id': '{bos}', 'title': 'Windows Boot Manager', 'description': 'BesideOS kurulumu', 'path': r'\EFI\BOOT\BOOTX64.EFI'},
  ],
};

class FakeRunner implements ProcessRunner {
  final calls = <String>[];
  int scriptExit = 0, shutdownExit = 0;
  Map<String, dynamic> list = Map<String, dynamic>.from(listJson);

  @override
  Future<RunResult> exec(String exe, List<String> args) async {
    calls.add('$exe ${args.where((a) => a.startsWith('/')).join(' ')}');
    return RunResult(shutdownExit, '', '');
  }

  @override
  Future<RunResult> script(File script, List<String> args, {bool elevated = false}) async {
    calls.add('${elevated ? '*' : ''}${args.where((a) => a != args.last || a.startsWith('-')).join(' ')}'.replaceAll(RegExp(r'\S*boot-entries\.json'), 'OUT'));
    if (scriptExit == 0 && args.contains('list')) {
      File(args[args.indexOf('-OutFile') + 1]).writeAsStringSync(jsonEncode(list));
    }
    return RunResult(scriptExit, '', '');
  }
}

void main() {
  late Directory tmp;
  late FakeRunner runner;
  late BootController c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('boot');
    runner = FakeRunner();
    c = BootController(runner: runner, script: File('boot-entries.ps1'), workDir: tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('only real systems are offered; USB and the installer entry are kept apart', () async {
    await c.load();
    expect(c.phase, BootPhase.ready);
    expect(c.systems.map((e) => e.label), ['Windows', 'Linux Mint']);
    expect(c.others.map((e) => e.description), ['EFI USB Device', 'BesideOS kurulumu']);
    expect(c.isDefault(c.systems.first), isTrue);
    expect(c.isDefault(c.systems.last), isFalse);
  });

  test('systems follow the firmware order', () async {
    runner.list = {
      ...listJson,
      'order': ['{aaa}', '{bootmgr}']
    };
    await c.load();
    expect(c.systems.map((e) => e.label), ['Linux Mint', 'Windows']);
    expect(c.isDefault(c.systems.first), isTrue);
  });

  test('a declined administrator prompt is reported and nothing is listed', () async {
    runner.scriptExit = kElevationDeclined;
    await c.load();
    expect(c.phase, BootPhase.failed);
    expect(c.error, contains('izni verilmedi'));
  });

  test('choosing the next start runs the script elevated with -Execute and the entry id', () async {
    await c.load();
    await c.startNext(c.systems.last);
    expect(runner.calls.any((x) => x.contains('-Action next') && x.contains('-Id {aaa}') && x.contains('-Execute') && x.startsWith('*')), isTrue);
    expect(c.notice, contains('Linux Mint'));
    expect(c.phase, BootPhase.ready);
  });

  test('making a system the default uses the default action', () async {
    await c.load();
    await c.makeDefault(c.systems.last);
    expect(runner.calls.any((x) => x.contains('-Action default') && x.contains('-Id {aaa}')), isTrue);
  });

  test('a USB or installer entry cannot be chosen', () async {
    await c.load();
    final before = runner.calls.length;
    await c.startNext(c.others.first);
    await c.makeDefault(c.others.last);
    expect(runner.calls.length, before);
  });

  test('a failing change is reported and keeps the list', () async {
    await c.load();
    runner.scriptExit = 1;
    await c.startNext(c.systems.last);
    expect(c.error, contains('Değiştirilemedi'));
    expect(c.notice, isNull);
    expect(c.systems, isNotEmpty);
  });

  test('restart only on request, with a countdown that can be cancelled', () async {
    await c.load();
    expect(runner.calls.any((x) => x.startsWith('shutdown')), isFalse);
    await c.restart();
    expect(runner.calls.last, 'shutdown /r /t /c');
    expect(c.restarting, isTrue);
    await c.cancelRestart();
    expect(runner.calls.last, 'shutdown /a');
    expect(c.restarting, isFalse);
  });
}
