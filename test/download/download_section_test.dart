import 'dart:io';

import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/download/download_controller.dart';
import 'package:besideos_site/download/download_section.dart';
import 'package:besideos_site/download/downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Fake extends DownloadController {
  Fake() : super(downloader: Downloader(), targetDir: Directory.systemTemp);
  DownloadPhase ph = DownloadPhase.idle;
  int rec = 0;
  int? tot;
  IsoAsset? started;
  bool cancelled = false;
  (String, String)? manual;
  @override
  DownloadPhase get phase => ph;
  @override
  int get received => rec;
  @override
  int? get total => tot;
  @override
  String? get error => ph == DownloadPhase.mismatch ? 'Sağlama toplamı eşleşmedi' : null;
  @override
  File? get file => ph == DownloadPhase.verified ? File('/tmp/x.iso') : null;
  @override
  String? get expectedHash => 'aaaa1111';
  @override
  String? get actualHash => 'bbbb2222';
  @override
  Future<void> start(IsoAsset iso) async => started = iso;
  @override
  void cancel() => cancelled = true;
  @override
  Future<void> startWithManualHash(File f, String h) async => manual = (f.path, h);
  void set(DownloadPhase p) {
    ph = p;
    notifyListeners();
  }
}

const iso = IsoAsset(
    arch: IsoArch.x86_64,
    url: 'https://e.org/a.iso',
    checksumUrl: 'https://e.org/SUMS',
    fileName: 'a.iso');

Distro dist({bool win = false, List<IsoAsset> isos = const [iso]}) => Distro(
    id: 'u', name: 'U', family: win ? DistroFamily.windows : DistroFamily.linux, tagline: 't',
    description: 'd', bestFor: 'b', look: 'l', accent: 0xFF336699, guide: const [],
    requirements: const [], hosts: const ['linux'], downloadPage: 'https://e.org',
    userSuppliedIso: win, license: 'l', isos: isos);

Widget wrap(Widget w) => MaterialApp(
    theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: w)));

Widget sec(Distro d, Fake f, {IsoArch? arch = IsoArch.x86_64, bool web = false}) =>
    wrap(DownloadSection(distro: d, controllerFactory: () => f, hostArch: arch, isWeb: web));

void main() {
  testWidgets('web build shows disabled button with reason', (t) async {
    await t.pumpWidget(sec(dist(), Fake(), web: true));
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(find.text('Tarayıcıda indirme kapalı; masaüstü uygulamayı kullan.'), findsOneWidget);
  });

  testWidgets('enabled button when iso exists for host arch', (t) async {
    final f = Fake();
    await t.pumpWidget(sec(dist(), f));
    await t.tap(find.widgetWithText(FilledButton, 'İndir'));
    expect(f.started, iso);
  });

  testWidgets('shows "bu mimari için ISO yok" when arch missing', (t) async {
    await t.pumpWidget(sec(dist(), Fake(), arch: IsoArch.arm64));
    expect(find.textContaining('Bu mimari için ISO yok'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await t.pumpWidget(sec(dist(), Fake(), arch: null));
    expect(find.textContaining('Bu mimari için ISO yok'), findsOneWidget);
  });

  testWidgets('progress bar and percentage while downloading', (t) async {
    final f = Fake()..rec = 50..tot = 200;
    await t.pumpWidget(sec(dist(), f));
    f.set(DownloadPhase.downloading);
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('%25'), findsOneWidget);
    f.tot = null;
    f.set(DownloadPhase.downloading);
    await t.pump();
    expect(find.textContaining('MB'), findsOneWidget);
  });

  testWidgets('verified state says İndirildi ve doğrulandı, not kuruldu', (t) async {
    final f = Fake();
    await t.pumpWidget(sec(dist(), f));
    f.set(DownloadPhase.verified);
    await t.pump();
    expect(find.text('İndirildi ve doğrulandı'), findsOneWidget);
    expect(find.textContaining('kuruldu'), findsNothing);
    expect(find.textContaining('Kurulum hazır'), findsNothing);
  });

  testWidgets('mismatch state shows both hashes and a retry button', (t) async {
    final f = Fake();
    await t.pumpWidget(sec(dist(), f));
    f.set(DownloadPhase.mismatch);
    await t.pump();
    expect(find.textContaining('aaaa1111'), findsOneWidget);
    expect(find.textContaining('bbbb2222'), findsOneWidget);
    await t.tap(find.text('Tekrar dene'));
    expect(f.started, iso);
  });

  testWidgets('windows distro shows fields and verify button, no download button', (t) async {
    final f = Fake();
    await t.pumpWidget(sec(dist(win: true, isos: const []), f));
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('İndir'), findsNothing);
    await t.enterText(find.byType(TextField).at(0), '/tmp/w.iso');
    await t.enterText(find.byType(TextField).at(1), 'abc');
    await t.tap(find.text('Doğrula'));
    expect(f.manual, ('/tmp/w.iso', 'abc'));
  });

  testWidgets('cancel button works', (t) async {
    final f = Fake()..ph = DownloadPhase.downloading;
    await t.pumpWidget(sec(dist(), f));
    await t.tap(find.text('İptal'));
    expect(f.cancelled, isTrue);
  });

  testWidgets('no overflow at 320x640', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    for (final p in [DownloadPhase.mismatch, DownloadPhase.downloading, DownloadPhase.verified]) {
      final f = Fake()..ph = p..rec = 1..tot = 3;
      await t.pumpWidget(sec(dist(), f));
      expect(t.takeException(), isNull, reason: '$p');
    }
    await t.pumpWidget(sec(dist(win: true, isos: const []), Fake()..ph = DownloadPhase.mismatch));
    expect(t.takeException(), isNull);
  });
}
