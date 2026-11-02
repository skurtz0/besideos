import 'dart:io';

import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/install/install_controller.dart';
import 'package:besideos_site/install/install_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'install_controller_test.dart' show FakeDownload, FakeRunner, engine, iso;

Distro dist({String id = 'u', bool win = false, List<String> hosts = const ['windows']}) => Distro(
    id: id, name: 'U', family: DistroFamily.linux, tagline: 't', description: 'd', bestFor: 'b', look: 'l',
    accent: 0xFF336699, guide: const [], requirements: const [], hosts: hosts, downloadPage: 'https://e.org',
    userSuppliedIso: win, license: 'l', isos: const [iso]);

Widget wrap(Widget w) => MaterialApp(
    theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  late Directory tmp;
  late FakeRunner runner;
  late InstallController c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('besideos_install_ui');
    runner = FakeRunner(tmp);
    c = InstallController(
        runner: runner, engine: engine(), workDir: Directory('${tmp.path}/work'), download: FakeDownload(tmp));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget section({Distro? d, bool supported = true, InstallController? Function()? factory}) => wrap(InstallSection(
      distro: d ?? dist(), supported: supported, hostArch: IsoArch.x86_64, controllerFactory: factory ?? () => c));

  testWidgets('hidden when not the Windows desktop app', (t) async {
    await t.pumpWidget(section(supported: false));
    expect(find.text('Tek tıkla kur'), findsNothing);
  });

  testWidgets('hidden for user-supplied ISO and for distros without a Windows host', (t) async {
    await t.pumpWidget(section(d: dist(win: true)));
    expect(find.text('Tek tıkla kur'), findsNothing);
    await t.pumpWidget(section(d: dist(hosts: const ['mac-m1m2'])));
    expect(find.text('Tek tıkla kur'), findsNothing);
  });

  testWidgets('missing engine is reported', (t) async {
    await t.pumpWidget(section(factory: () => null));
    expect(find.textContaining('Kurulum motoru bulunamadı'), findsOneWidget);
  });

  testWidgets('one click reaches the plan; apply stays disabled until backup box and KUR', (t) async {
    await t.runAsync(() async {
      await t.pumpWidget(section());
      await t.tap(find.widgetWithText(ElevatedButton, 'U kur'));
      for (var i = 0; i < 50 && c.phase != InstallPhase.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pump();
    expect(c.phase, InstallPhase.ready);
    expect(find.textContaining('Plan hazır'), findsOneWidget);
    expect(find.textContaining('küçültülecek'), findsOneWidget);

    ElevatedButton go() => t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Kurulumu başlat ve yeniden başlat'));
    expect(go().onPressed, isNull);
    await t.enterText(find.byType(TextField), 'KUR');
    await t.pump();
    expect(go().onPressed, isNull, reason: 'backup box not ticked');
    await t.tap(find.byType(Checkbox));
    await t.pump();
    expect(go().onPressed, isNotNull);
    await t.enterText(find.byType(TextField), 'kurma');
    await t.pump();
    expect(go().onPressed, isNull);
    expect(runner.calls.any((x) => x.startsWith('apply-plan.ps1')), isFalse);
  });

  testWidgets('Fedora shows its boot caveat before starting', (t) async {
    await t.pumpWidget(section(d: dist(id: 'fedora')));
    expect(find.textContaining('doğrulanmadı'), findsOneWidget);
  });
}
