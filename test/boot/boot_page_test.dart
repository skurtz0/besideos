import 'dart:io';

import 'package:besideos_site/boot/boot_controller.dart';
import 'package:besideos_site/boot/boot_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'boot_controller_test.dart' show FakeRunner;

void main() {
  late Directory tmp;
  late FakeRunner runner;
  late BootController c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bootpage');
    runner = FakeRunner();
    c = BootController(runner: runner, script: File('boot-entries.ps1'), workDir: tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> show(WidgetTester t) async {
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: BootPage(controller: c)));
      for (var i = 0; i < 100 && c.phase != BootPhase.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pump();
  }

  testWidgets('lists the installed systems with a one-time and a permanent choice', (t) async {
    await show(t);
    expect(find.text('Bilgisayar hangi sistemle açılsın?'), findsOneWidget);
    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('Linux Mint'), findsOneWidget);
    expect(find.text('Varsayılan'), findsOneWidget);
    expect(find.text('Bir sonraki açılışta bunu aç'), findsNWidgets(2));
    expect(find.text('EFI USB Device'), findsNothing); // folded away
  });

  testWidgets('picking the next start offers a restart that still needs a confirmation', (t) async {
    await show(t);
    await t.runAsync(() async {
      await t.tap(find.text('Bir sonraki açılışta bunu aç').last);
      for (var i = 0; i < 100 && c.notice == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pump();
    expect(find.textContaining('Bir sonraki açılışta Linux Mint açılacak'), findsOneWidget);
    expect(runner.calls.any((x) => x.startsWith('shutdown')), isFalse);
    await t.tap(find.text('Şimdi yeniden başlat'));
    await t.pumpAndSettle();
    expect(find.text('Şimdi yeniden başlatalım mı?'), findsOneWidget);
    await t.tap(find.text('Şimdi değil'));
    await t.pumpAndSettle();
    expect(runner.calls.any((x) => x.startsWith('shutdown')), isFalse);
  });

  testWidgets('a single system gets a hint to install a second one', (t) async {
    runner.list = {
      'order': ['{bootmgr}'],
      'sequence': <String>[],
      'entries': [
        {'id': '{bootmgr}', 'title': 'Windows Boot Manager', 'description': 'Windows Boot Manager', 'path': r'\EFI\Microsoft\Boot\bootmgfw.efi'},
      ],
    };
    await show(t);
    expect(find.textContaining('tek bir sistem görünüyor'), findsOneWidget);
  });
}
