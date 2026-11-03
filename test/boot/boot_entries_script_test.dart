import 'dart:convert';
import 'dart:io';

import 'package:besideos_site/boot/boot_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// probe/linux/boot-entries.sh with a fake efibootmgr: the JSON must be what BootController reads.
void main() {
  final script = File('probe/linux/boot-entries.sh').absolute.path;
  late Directory tmp;
  late Map<String, String> env;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bootent');
    File('${tmp.path}/efibootmgr').writeAsStringSync(r'''#!/usr/bin/env bash
if [ "$1" = -v ]; then
printf 'BootCurrent: 0005\nBootNext: 0000\nBootOrder: 0005,0000,2001\n'
printf 'Boot0000* Windows Boot Manager\tHD(1,GPT,x,0x800,0x1)/\\EFI\\Microsoft\\Boot\\bootmgfw.efi\n    dp: 04 01\n'
printf 'Boot0005* Fedora\tHD(1,GPT,x,0x800,0x1)/File(\\EFI\\fedora\\shimx64.efi)RC\n'
printf 'Boot2001* EFI USB Device\tRC\n'
else printf '%s\n' "$*" >> "$FAKE_LOG"; fi
''');
    Process.runSync('chmod', ['+x', '${tmp.path}/efibootmgr']);
    env = {'BESIDEOS_TEST': '1', 'BESIDEOS_EFIBOOTMGR': '${tmp.path}/efibootmgr', 'FAKE_LOG': '${tmp.path}/log'};
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ProcessResult run(List<String> a) => Process.runSync('bash', [script, ...a], environment: env);
  final skip = Platform.isLinux ? null : 'Linux only';

  test('list gives order, next boot and the entries BootController understands', () {
    final r = run(['-Action', 'list']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    expect(j['order'], ['0005', '0000', '2001']);
    expect(j['sequence'], ['0000']);
    final entries = [for (final e in j['entries'] as List) BootEntry.fromJson(e as Map<String, dynamic>)];
    expect(entries.firstWhere((e) => e.id == '0000').isWindows, isTrue);
    expect(entries.firstWhere((e) => e.id == '0005').isSystem, isTrue);
    expect(entries.firstWhere((e) => e.id == '2001').isDevice, isTrue);
  }, skip: skip);

  test('next and default only touch listed entries and only with -Execute', () {
    expect(run(['-Action', 'next', '-Id', '0000']).stdout, contains('DRY-RUN'));
    expect(File('${tmp.path}/log').existsSync(), isFalse);
    expect(run(['-Action', 'next', '-Id', '0000', '-Execute']).exitCode, 0);
    expect(run(['-Action', 'default', '-Id', '0000', '-Execute']).exitCode, 0);
    expect(File('${tmp.path}/log').readAsLinesSync(), ['-n 0000', '-o 0000,0005,2001']);
    expect(run(['-Action', 'next', '-Id', '9999', '-Execute']).exitCode, 2);
    expect(run(['-Action', 'next', '-Id', '0000; rm', '-Execute']).exitCode, 2);
  }, skip: skip);
}
