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

  Future<void> toReady(WidgetTester t) async {
    t.view.physicalSize = const Size(900, 2600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      await t.pumpWidget(section());
      await t.tap(find.text('Kurmak için tıklayın'));
      for (var i = 0; i < 50 && c.phase != InstallPhase.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pump();
  }

  testWidgets('hidden when not the Windows desktop app', (t) async {
    await t.pumpWidget(section(supported: false));
    expect(find.text('Kurmak için tıklayın'), findsNothing);
  });

  testWidgets('hidden for user-supplied ISO and for distros without a Windows host', (t) async {
    await t.pumpWidget(section(d: dist(win: true)));
    expect(find.text('Kurmak için tıklayın'), findsNothing);
    await t.pumpWidget(section(d: dist(hosts: const ['mac-m1m2'])));
    expect(find.text('Kurmak için tıklayın'), findsNothing);
  });

  testWidgets('missing engine is reported in plain words', (t) async {
    await t.pumpWidget(section(factory: () => null));
    expect(find.text('Kurulum bileşeni eksik'), findsOneWidget);
  });

  testWidgets('idle card explains the three steps and offers one big button', (t) async {
    await t.pumpWidget(section());
    expect(find.text("Windows'un yanına kur"), findsOneWidget);
    expect(find.text('Tıklarsın'), findsOneWidget);
    expect(find.text('Bilgisayar hazırlanır'), findsOneWidget);
    expect(find.text('Yeniden başlar'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Kurmak için tıklayın'), findsOneWidget);
  });

  testWidgets('one click reaches the plan; start stays disabled until the backup box is ticked', (t) async {
    await toReady(t);
    expect(c.phase, InstallPhase.ready);
    expect(find.text('Her şey hazır!'), findsOneWidget);
    expect(find.textContaining('Bölüm küçültme geri alınamaz'), findsOneWidget);

    FilledButton go() => t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Kurulumu başlat'));
    expect(go().onPressed, isNull);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    expect(go().onPressed, isNotNull);
    expect(runner.calls.any((x) => x.startsWith('apply-plan.ps1')), isFalse);
  });

  testWidgets('the final dialog can be declined, nothing is applied', (t) async {
    await toReady(t);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Kurulumu başlat'));
    await t.pumpAndSettle();
    expect(find.text('Başlayalım mı?'), findsOneWidget);
    await t.tap(find.text('Vazgeç'));
    await t.pumpAndSettle();
    expect(c.phase, InstallPhase.ready);
    expect(runner.calls.any((x) => x.startsWith('apply-plan.ps1')), isFalse);
  });

  testWidgets('confirming in the dialog applies the plan', (t) async {
    await toReady(t);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Kurulumu başlat'));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.text('Evet, başlat'));
      for (var i = 0; i < 50 && c.phase != InstallPhase.applied; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pump();
    expect(c.phase, InstallPhase.applied);
    expect(runner.calls.last, startsWith('apply-plan.ps1* -PlanFile -Execute -Reboot'));
    expect(find.textContaining('Bilgisayar yeniden başlıyor'), findsOneWidget);
  });

  testWidgets('Fedora shows its boot caveat before starting', (t) async {
    await t.pumpWidget(section(d: dist(id: 'fedora')));
    expect(find.textContaining('doğrulanmadı'), findsOneWidget);
  });
}
