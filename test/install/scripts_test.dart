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

  test('undo can run without -PlanFile (the app never passes it)', () {
    final text = File('probe/windows/apply-plan.ps1').readAsStringSync();
    expect(text, contains(r'if (-not $PlanFile)'));
    expect(text, contains(r'if (-not $OutDir)'));
  });
}
