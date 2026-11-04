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

  test('Explorer pop-ups are suppressed while the steps run and the service is always restored', () {
    final text = File('probe/windows/apply-plan.ps1').readAsStringSync();
    expect(text, contains('Stop-Service -Name ShellHWDetection'));
    expect('Resume-ShellHw'.allMatches(text).length, greaterThanOrEqualTo(3)); // definition + failure exit + normal end
    expect(text, contains('PowerShell.Exiting'));
  });

  test('label patching leaves menu titles alone', () {
    final text = File('probe/windows/apply-plan.ps1').readAsStringSync();
    expect(text, contains('menuentry|submenu'));
    expect(text, contains(r'menu\s+label'));
  });

  test('the staged installer menu gets a back-to-Windows entry (GRUB leaves to the firmware)', () {
    final text = File('probe/windows/apply-plan.ps1').readAsStringSync();
    expect(text, contains('function Add-WindowsEntryToGrub'));
    expect(text, contains('--id besideos_windows {'));
    expect(text, contains(r'[string]$BackLabel'));          // the entry's text comes from the app, in the person's language
    expect(text, contains('Windows (cancel installation)')); // ... with an English default
    expect(text, contains(r'$desc = $et'));                // -EntryTitle is the whole boot entry name
    expect(text, contains('exit 0'));
    // only the staged copy on the new partition is edited, and only for non-Windows media
    expect(text.indexOf(r'Add-WindowsEntryToGrub $dst'), greaterThan(text.indexOf('Update-BootLabel \$dst')));
  });

  test('the boot menu is set up with a fallback and always put back by undo and by a startup task', () {
    final text = File('probe/windows/apply-plan.ps1').readAsStringSync();
    expect(text, contains('function Enable-BesideMenu'));
    expect(text, contains('function Disable-BesideMenu'));
    // the old settings are saved before anything is changed
    expect(text.indexOf(r'$script:State.menu = [ordered]'), lessThan(text.indexOf("@('/displayorder', \$g, '/addfirst')")));
    // both boot entry kinds fall back to the direct one-shot start when the menu cannot be set up
    expect('boot menu not set up, using the direct one-shot start'.allMatches(text), hasLength(2));
    expect(text, contains('bcdedit /set {bootmgr} default'));
    expect(text, contains('schtasks /delete /tn'));
    // undo restores before it deletes the entry
    expect(text.indexOf(r'Disable-BesideMenu $st.menu'), lessThan(text.indexOf('# 1. boot entry')));
  });

  test('the boot menu also lists the other installed systems and removes them again', () {
    final text = File('probe/windows/apply-plan.ps1').readAsStringSync();
    expect(text, contains('function Get-OtherSystems'));
    expect(text, contains('function Add-OtherSystemsToMenu'));
    // Windows itself and BesideOS entries are never added, and only .efi files on a local partition are
    expect(text, contains('bootmgfw'));
    expect(text, contains(r'^BesideOS'));
    expect(text, contains(r'\.efi$'));
    // every created entry is recorded in the state before it is configured, and deleted by undo and by the startup task
    expect(text.indexOf(r'$script:State.menu.extra = @($added); Save-State'), lessThan(text.indexOf("@('/set', \$g, 'device', \$o.device)")));
    expect(text, contains(r'bcdedit /delete $x /cleanup'));
    expect(text, contains("@('/delete', [string]\$x, '/cleanup')"));
  });

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

  test('boot configs that name the ISO label or archiso uuid are pointed at the staging label', () {
    final apply = File('probe/windows/apply-plan.ps1').readAsStringSync();
    expect(apply, contains('function Update-BootLabel'));
    expect(apply, contains('function Get-IsoVolumeLabel'));   // Windows shows the label cut to 16 characters
    expect(apply, contains('archisosearchuuid='));
    expect(apply, contains('IsReadOnly'));                   // ISO files keep their read-only flag after robocopy
    expect(apply, isNot(contains('-Include')));              // ignored together with -LiteralPath
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
