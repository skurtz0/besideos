import 'dart:io';

import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/catalog/distro_page.dart';
import 'package:besideos_site/catalog/routes.dart';
import 'package:besideos_site/catalog/support_matrix.dart';
import 'package:besideos_site/download/download_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Distro d(String id, DistroFamily f, {bool iso = false, String? desktop, String long = ''}) => Distro(
      id: id,
      name: 'Ad $id',
      family: f,
      tagline: 'Slogan $id',
      description: 'Aciklama $id $long',
      bestFor: 'Icin $id',
      desktop: desktop,
      look: 'Gorunum $id',
      accent: 0xFF336699,
      guide: [
        GuideStep(title: 'Adim bir $id', body: 'Govde bir $long'),
        const GuideStep(title: 'Adim iki', body: 'Govde iki'),
      ],
      requirements: const ['Gereksinim A'],
      hosts: const ['windows', 'linux'],
      downloadPage: 'https://example.org/$id',
      userSuppliedIso: iso,
      license: 'Lisans $id',
    );

final catalog = Catalog([
  d('mint', DistroFamily.linux, desktop: 'Cinnamon'),
  d('win', DistroFamily.windows, iso: true, long: 'uzun ' * 80),
]);

Widget routed(String name, {Catalog? c}) => MaterialApp(
      key: UniqueKey(),
      theme: ThemeData.dark(),
      onGenerateRoute: (s) => catalogRoute(s, c ?? catalog),
      onGenerateInitialRoutes: (n) => [catalogRoute(RouteSettings(name: n), c ?? catalog)],
      initialRoute: name,
    );

Widget page(Distro x) => MaterialApp(theme: ThemeData.dark(), home: DistroPage(distro: x));

void main() {
  testWidgets('shows name, description, look and every guide step', (t) async {
    t.view.physicalSize = const Size(900, 3200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(page(catalog.distros.first));
    expect(find.text('Ad mint'), findsWidgets);
    expect(find.textContaining('Aciklama mint'), findsOneWidget);
    expect(find.textContaining('Gorunum mint'), findsOneWidget);
    expect(find.textContaining('Cinnamon'), findsOneWidget);
    // The manual guide is folded away; open it.
    expect(find.text('Adim bir mint'), findsNothing);
    await t.tap(find.text('Elle kurmak istersen: adımlar'));
    await t.pumpAndSettle();
    expect(find.text('Adim bir mint'), findsOneWidget);
    expect(find.text('Adim iki'), findsOneWidget);
    expect(find.textContaining('Gereksinim A'), findsOneWidget);
    expect(find.textContaining('https://example.org/mint'), findsOneWidget);
  });

  testWidgets('shows supported hosts: check only for hosts in distro.hosts', (t) async {
    // mint hosts: windows, linux. Linux guest on linux is unsupported by matrix; mac M1/M2 not in hosts.
    await t.pumpWidget(page(catalog.distros.first));
    expect(find.textContaining(supportFor(Host.windows, DistroFamily.linux).reason), findsOneWidget);
    expect(find.textContaining(supportFor(Host.macOther, DistroFamily.linux).reason), findsOneWidget);
    expect(find.text('✓'), findsOneWidget);
    expect(find.text('✗'), findsNWidgets(3));
  });

  testWidgets('hosts [windows] gives no check for Mac M1/M2', (t) async {
    final x = Distro(
      id: 'u', name: 'U', family: DistroFamily.linux, tagline: 't', description: 'd', bestFor: 'b',
      look: 'l', accent: 0xFF336699, guide: const [], requirements: const [], hosts: const ['windows'],
      downloadPage: 'x', userSuppliedIso: false, license: 'l');
    await t.pumpWidget(page(x));
    expect(find.text('✓'), findsOneWidget);
    expect(find.textContaining('Mac M1/M2: Bu dağıtım için bu rehberde yok'), findsOneWidget);
    expect(find.textContaining('Asahi Linux ile Linux, macOS yanına kurulabilir'), findsNothing);
  });

  testWidgets('distro page embeds the download section', (t) async {
    await t.pumpWidget(page(catalog.distros.first));
    expect(find.byType(DownloadSection), findsOneWidget);
    expect(find.textContaining('sonraki aşamada'), findsNothing);
  });

  testWidgets('windows distro shows the bring-your-own-ISO note', (t) async {
    await t.pumpWidget(page(catalog.distros[1]));
    expect(find.textContaining('BesideOS ISO dosyası sağlamaz'), findsOneWidget);
    await t.pumpWidget(page(catalog.distros[0]));
    expect(find.textContaining('BesideOS ISO dosyası sağlamaz'), findsNothing);
  });

  testWidgets('unknown id route shows "Bulunamadı"', (t) async {
    for (final n in ['/distros/nope', '/distros/a/b']) {
      await t.pumpWidget(routed(n));
      expect(find.textContaining('Bulunamadı'), findsOneWidget, reason: n);
    }
  });

  testWidgets('/distros route shows the catalog and opens a distro', (t) async {
    await t.pumpWidget(routed('/distros'));
    expect(find.text('Ad mint'), findsOneWidget);
    await t.tap(find.text('Ad mint'));
    await t.pumpAndSettle();
    expect(find.textContaining('Aciklama mint'), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('Slogan mint'), findsOneWidget);
  });

  testWidgets('no overflow at 320x640', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(page(catalog.distros[1]));
    expect(t.takeException(), isNull);
    final real = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync());
    await t.pumpWidget(page(real.byId('ubuntu')!));
    expect(t.takeException(), isNull);
  });

  testWidgets('trailing slash and query string routes', (t) async {
    for (final n in ['/distros/', '/distros?x=1']) {
      await t.pumpWidget(routed(n));
      expect(find.text('Ad mint'), findsOneWidget, reason: n);
    }
    for (final n in ['/distros/mint/', '/distros/mint?ref=1']) {
      await t.pumpWidget(routed(n));
      expect(find.textContaining('Aciklama mint'), findsOneWidget, reason: n);
    }
  });

  testWidgets('deep link without back stack shows fallback back button', (t) async {
    await t.pumpWidget(routed('/distros/mint'));
    expect(find.byType(BackButton), findsNothing);
    await t.tap(find.byTooltip('Dağıtımlar'));
    await t.pumpAndSettle();
    expect(find.text('Slogan mint'), findsOneWidget);
  });

  testWidgets('a distro with variants asks which one on its own page and switches', (t) async {
    t.view.physicalSize = const Size(900, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const a = IsoAsset(arch: IsoArch.x86_64, url: 'https://e.org/a.iso', checksumUrl: 'https://e.org/S', fileName: 'a.iso');
    const b = IsoAsset(arch: IsoArch.x86_64, url: 'https://e.org/b.iso', checksumUrl: 'https://e.org/S', fileName: 'b.iso');
    final x = Distro(
      id: 'v', name: 'Ad v', family: DistroFamily.linux, tagline: '', description: '', bestFor: '',
      look: '', accent: 0xFF336699, guide: const [], requirements: const [], hosts: const ['windows'],
      downloadPage: '', userSuppliedIso: false, license: '', isos: const [a],
      variants: const [
        DistroVariant(id: 'one', label: 'Birinci secenek', note: 'n1', isos: [a]),
        DistroVariant(id: 'two', label: 'Ikinci secenek', note: 'n2', isos: [b]),
      ],
    );
    await t.pumpWidget(page(x));
    expect(find.text('Hangisini istersin?'), findsOneWidget);
    expect(find.text('Birinci secenek'), findsOneWidget);
    await t.tap(find.text('Ikinci secenek'));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
    expect(t.takeException(), isNull);
    // a distro with a single choice shows no picker
    await t.pumpWidget(page(catalog.distros.first));
    expect(find.text('Hangisini istersin?'), findsNothing);
  });

  testWidgets('summary excludes hosts the matrix rejects', (t) async {
    final x = Distro(
      id: 'lx', name: 'Ad lx', family: DistroFamily.linux, tagline: '', description: '', bestFor: '',
      look: '', accent: 0xFF336699, guide: const [], requirements: const [], hosts: const ['linux'],
      downloadPage: '', userSuppliedIso: false, license: '',
    );
    await t.pumpWidget(page(x));
    expect(find.text('Yok'), findsOneWidget);
  });

  testWidgets('shows unsupported targets and basedOn only when set', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(page(catalog.distros.first));
    await t.scrollUntilVisible(find.text('Kurulamayanlar'), 300, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Kurulamayanlar'));
    await t.pumpAndSettle();
    for (final u in unsupportedTargets) {
      expect(find.textContaining(u.key), findsOneWidget);
    }
    expect(find.textContaining('Temel aldığı sistem'), findsNothing);
    expect(t.takeException(), isNull);
    final b = Distro(
      id: 'b', name: 'Ad b', family: DistroFamily.linux, tagline: '', description: '', bestFor: '',
      look: '', accent: 0xFF336699, guide: const [], requirements: const [], hosts: const ['linux'],
      downloadPage: '', userSuppliedIso: false, license: '', basedOn: 'Debian',
    );
    await t.pumpWidget(page(b));
    expect(find.text('Temel aldığı sistem: Debian'), findsOneWidget);
  });
}
