import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The engine scripts run under Windows PowerShell 5.1 on the user's disk; these guard known traps.
void main() {
  final scripts = Directory('probe/windows').listSync().whereType<File>().where((f) => f.path.endsWith('.ps1')).toList();

  test('engine scripts are found', () {
    expect(scripts.length, greaterThanOrEqualTo(3));
  });

  for (final f in scripts) {
    final name = f.uri.pathSegments.last;
    final text = f.readAsStringSync();

    test('$name is ASCII-only (5.1 reads BOM-less files as ANSI)', () {
      final bad = f.readAsBytesSync().where((b) => b > 127).length;
      expect(bad, 0);
    });

    test('$name does not use \$PSScriptRoot in param() defaults', () {
      // With [CmdletBinding()], 5.1 leaves it empty there; `-Undo -OutDir x` died at parameter binding.
      final m = RegExp(r'param\((.*?)\n\)', dotAll: true).firstMatch(text);
      if (m != null) expect(m.group(1), isNot(contains(r'$PSScriptRoot')));
    });
  }

  test('undo decides a boot entry exists from bcdedit output, not its exit code', () {
    final text = File('probe/windows/apply-plan.ps1').readAsStringSync();
    expect(text, contains('function Test-BcdEntry'));
    expect(text, isNot(contains(r'$e.Code -ne 0')));
    expect(text, isNot(contains(r'$e2.Code -ne 0')));
  });

  test('a Windows ISO with an install.wim over 4 GiB is split instead of refused', () {
    final inspect = File('probe/windows/inspect-iso.ps1').readAsStringSync();
    expect(inspect, contains('splittable_wim_bytes'));
    expect(inspect, contains('sources/install.wim'));
    final apply = File('probe/windows/apply-plan.ps1').readAsStringSync();
    expect(apply, contains('/Split-Image'));
    expect(apply, contains('/FileSize:3800'));
    expect(apply, contains("'/XF', 'install.wim'"));
    // the copy still refuses any other file of 4 GiB or more
    expect(apply, contains('File too large for FAT32'));
  });

  test('an ISO without a UEFI loader is refused before the disk is touched', () {
    final apply = File('probe/windows/apply-plan.ps1').readAsStringSync();
    final preflight = apply.indexOf('Get-IsoBootInfo');
    final firstDiskChange = apply.indexOf("'shrink_partition' {");
    expect(preflight, greaterThan(0));
    expect(preflight, lessThan(firstDiskChange));
    expect(apply, contains('BIOS-only media cannot be installed this way'));
  });
  test('Windows media boots boot.wim as a RAM disk instead of a copy of {bootmgr}', () {
    final apply = File('probe/windows/apply-plan.ps1').readAsStringSync();
    expect(apply, contains(r"'ramdisksdipath', '\boot\boot.sdi'"));
    expect(apply, contains('winload.efi'));
    expect(apply, contains("'winpe', 'yes'"));
    expect(apply, contains("'{bootmgr}', 'bootsequence'"));
    // undo knows both objects it created and removes them together with the boot sequence
    expect(apply, contains("kind -eq 'ramdisk'"));
    expect(apply, contains('options_guid'));
  });

  test('the app never restarts the computer on its own', () {
    final dart = File('lib/install/install_controller.dart').readAsStringSync();
    expect(dart, isNot(contains("'-Reboot'")));
  });

  test('undo can run without -PlanFile (the app never passes it)', () {
    final text = File('probe/windows/apply-plan.ps1').readAsStringSync();
    expect(text, contains(r'if (-not $PlanFile)'));
    expect(text, contains(r'if (-not $OutDir)'));
  });
}
