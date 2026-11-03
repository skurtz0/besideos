import 'dart:io';

import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/install/install_controller.dart';
import 'package:besideos_site/install/install_section.dart';
import 'package:besideos_site/install/iso_picker.dart';
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

  Widget section({
    Distro? d,
    bool supported = true,
    InstallController? Function()? factory,
    Future<File?> Function()? pick,
    List<LocalIso> Function()? found,
  }) =>
      wrap(InstallSection(
        distro: d ?? dist(),
        supported: supported,
        hostArch: IsoArch.x86_64,
        controllerFactory: factory ?? () => c,
        pickIso: pick,
        findIsos: found ?? () => const [],
      ));

  Future<void> toReady(WidgetTester t) async {
    t.view.physicalSize = const Size(900, 2600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      await t.pumpWidget(section());
      await t.tap(find.text('Kurmak için tıklayın'));
      for (var i = 0; i < 250 && c.phase != InstallPhase.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pump();
  }

  testWidgets('hidden when not the Windows desktop app', (t) async {
    await t.pumpWidget(section(supported: false));
    expect(find.text('Kurmak için tıklayın'), findsNothing);
  });

  testWidgets('every system gets the one-click box; one without an official ISO asks for a file, never a path or checksum', (t) async {
    await t.pumpWidget(section(d: dist(win: true)));
    expect(find.textContaining('ISO dosyamı seçip kurmak için tıklayın'), findsOneWidget);
    expect(find.text('Kurmak için tıklayın'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('SHA'), findsNothing);
    // a distro that lists no Windows host is still installable from here
    await t.pumpWidget(section(d: dist(hosts: const ['mac-m1m2'])));
    expect(find.text('Kurmak için tıklayın'), findsOneWidget);
  });

  testWidgets('an official distro also offers "my own ISO"; picking a file skips the download', (t) async {
    t.view.physicalSize = const Size(900, 2600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final mine = File('${tmp.path}/my-system.iso')..writeAsBytesSync([1, 2, 3]);
    await t.runAsync(() async {
      await t.pumpWidget(section(pick: () async => mine));
      expect(find.text('Kendi ISO dosyamı seçip kurmak istiyorum'), findsOneWidget);
      await t.tap(find.text('Kendi ISO dosyamı seçip kurmak istiyorum'));
      for (var i = 0; i < 250 && c.phase != InstallPhase.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pump();
    expect(c.phase, InstallPhase.ready);
    expect(c.isLocalIso, isTrue);
    expect(runner.calls.first, startsWith('inspect-iso.ps1'));
    expect(find.text('Her şey hazır!'), findsOneWidget);
    expect(find.textContaining('my-system kurulum dosyaları'), findsOneWidget);
  });

  testWidgets('a Windows ISO: 80 GB recommended, "Yeni sistem" wording and a hint about the unallocated space', (t) async {
    t.view.physicalSize = const Size(900, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final win = Distro(
        id: 'w', name: 'Win', family: DistroFamily.windows, tagline: 't', description: 'd', bestFor: 'b', look: 'l',
        accent: 0xFF336699, guide: const [], requirements: const [], hosts: const ['windows'], downloadPage: 'https://e.org',
        userSuppliedIso: true, license: 'l');
    final mine = File('${tmp.path}/win.iso')..writeAsBytesSync([1]);
    await t.runAsync(() async {
      await t.pumpWidget(section(d: win, pick: () async => mine));
      await t.tap(find.textContaining('ISO dosyamı seçip kurmak için tıklayın'));
      for (var i = 0; i < 250 && c.phase != InstallPhase.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pump();
    expect(c.phase, InstallPhase.ready);
    expect(find.text('Yeni sistem için ne kadar yer ayıralım?'), findsOneWidget);
    expect(find.text('80 GB · önerilen'), findsOneWidget);
    expect(find.text('30 GB · önerilen'), findsNothing);
    expect(find.textContaining('Windows için en az 64 GB'), findsOneWidget);
    expect(find.textContaining('kurulurken diski doğru seç'), findsOneWidget);
    expect(find.textContaining('"Ayrılmamış alan"ı seç'), findsOneWidget);
    expect(find.textContaining('"Diskin tamamını sil"'), findsNothing);
  });
  testWidgets('cancelling the file dialog changes nothing', (t) async {
    await t.runAsync(() async {
      await t.pumpWidget(section(d: dist(win: true), pick: () async => null));
      await t.tap(find.textContaining('ISO dosyamı seçip kurmak için tıklayın'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await t.pump();
    expect(c.phase, InstallPhase.idle);
    expect(runner.calls, isEmpty);
  });

  testWidgets('ISO files found on the computer are listed and one tap starts with that file', (t) async {
    t.view.physicalSize = const Size(900, 2600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final f = File('${tmp.path}/found-one.iso')..writeAsBytesSync([1]);
    await t.runAsync(() async {
      await t.pumpWidget(section(d: dist(win: true), found: () => [LocalIso(f, 3033710592, DateTime(2026))]));
      expect(find.text('Bilgisayarında bulunan ISO dosyaları'), findsOneWidget);
      expect(find.text('found-one.iso'), findsOneWidget);
      expect(find.text('3,0 GB'), findsOneWidget);
      await t.tap(find.text('found-one.iso'));
      for (var i = 0; i < 250 && c.phase != InstallPhase.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pump();
    expect(c.phase, InstallPhase.ready);
    expect(c.isLocalIso, isTrue);
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

  testWidgets('with two drives a picker appears and picking the second one re-plans from it', (t) async {
    runner.drivesJson = '''
[{"disk":0,"partition":3,"letter":"C","label":"","disk_name":"SSD","disk_size_bytes":500000000000,"size_bytes":400000000000,"free_bytes":20000000000,"is_windows":true},
 {"disk":1,"partition":2,"letter":"D","label":"Veri","disk_name":"HDD","disk_size_bytes":1000000000000,"size_bytes":900000000000,"free_bytes":800000000000,"is_windows":false}]''';
    await toReady(t);
    expect(find.text('Yer hangi sürücüden açılsın?'), findsOneWidget);
    expect(find.textContaining('C: sürücüsü · Windows burada'), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.textContaining('D: sürücüsü (Veri)'));
      for (var i = 0; i < 250 && c.target?.letter != 'D'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pump();
    expect(c.target!.letter, 'D');
    expect(find.textContaining('D: sürücüsünde yaklaşık'), findsOneWidget);
  });

  testWidgets('Linux installs are told not to wipe the whole disk, before and after the preparation', (t) async {
    t.view.physicalSize = const Size(900, 2600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await toReady(t);
    expect(find.textContaining('kurulurken diski doğru seç'), findsOneWidget);
    expect(find.textContaining('"Diskin tamamını sil" seçeneğini SEÇME'), findsOneWidget);
    expect(find.textContaining('"Ayrılmamış alan"ı seç'), findsNothing);
  });

  testWidgets('a single drive shows no picker', (t) async {
    await toReady(t);
    expect(find.text('Yer hangi sürücüden açılsın?'), findsNothing);
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
      for (var i = 0; i < 250 && c.phase != InstallPhase.applied; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pump();
    expect(c.phase, InstallPhase.applied);
    expect(runner.calls.last, 'apply-plan.ps1* -PlanFile -Execute -OutDir -Menu');
    // the computer is NOT restarted by itself: the person gets a button and a confirmation
    expect(runner.calls.any((x) => x.startsWith('shutdown')), isFalse);
    expect(find.text('Hazır! Şimdi yeniden başlatabilirsin'), findsOneWidget);
    expect(find.text('Şimdi yeniden başlat'), findsOneWidget);
    await t.tap(find.text('Şimdi yeniden başlat'));
    await t.pumpAndSettle();
    expect(find.text('Şimdi yeniden başlatalım mı?'), findsOneWidget);
    await t.tap(find.text('Şimdi değil'));
    await t.pumpAndSettle();
    expect(runner.calls.any((x) => x.startsWith('shutdown')), isFalse);
  });

  testWidgets('the idle card states the ISO size, with no scary wording', (t) async {
    const sized = IsoAsset(
        arch: IsoArch.x86_64, url: 'https://e.org/a.iso', checksumUrl: 'https://e.org/S', fileName: 'a.iso', sizeBytes: 6448529408);
    final d = Distro(
        id: 'big', name: 'U', family: DistroFamily.linux, tagline: 't', description: 'd', bestFor: 'b', look: 'l',
        accent: 0xFF336699, guide: const [], requirements: const [], hosts: const ['windows'], downloadPage: 'https://e.org',
        userSuppliedIso: false, license: 'l', isos: const [sized]);
    await t.pumpWidget(section(d: d));
    expect(find.textContaining('İndirilecek ISO dosyası: 6,4 GB'), findsOneWidget);
    expect(find.textContaining('çok büyük'), findsNothing);
    expect(isoSizeText(3033710592), '3,0 GB');
  });

  testWidgets('Fedora shows its boot caveat before starting', (t) async {
    await t.pumpWidget(section(d: dist(id: 'fedora')));
    expect(find.textContaining('bazı bilgisayarlarda açılmayabilir'), findsOneWidget);
  });
}
