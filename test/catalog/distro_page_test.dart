import 'dart:io';

import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/catalog/distro_page.dart';
import 'package:besideos_site/catalog/routes.dart';
import 'package:besideos_site/catalog/support_matrix.dart';
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
      theme: ThemeData.dark(),
      onGenerateRoute: (s) => catalogRoute(s, c ?? catalog),
      initialRoute: name,
    );

Widget page(Distro x) => MaterialApp(theme: ThemeData.dark(), home: DistroPage(distro: x));

void main() {
  testWidgets('shows name, description, look and every guide step', (t) async {
    await t.pumpWidget(page(catalog.distros.first));
    expect(find.text('Ad mint'), findsWidgets);
    expect(find.textContaining('Aciklama mint'), findsOneWidget);
    expect(find.textContaining('Gorunum mint'), findsOneWidget);
    expect(find.textContaining('Cinnamon'), findsOneWidget);
    expect(find.text('Adim bir mint'), findsOneWidget);
    expect(find.text('Adim iki'), findsOneWidget);
    expect(find.textContaining('Gereksinim A'), findsOneWidget);
    expect(find.textContaining('https://example.org/mint'), findsOneWidget);
  });

  testWidgets('shows supported hosts', (t) async {
    await t.pumpWidget(page(catalog.distros.first));
    expect(find.textContaining(supportFor(Host.windows, DistroFamily.linux).reason), findsOneWidget);
    expect(find.textContaining(supportFor(Host.macOther, DistroFamily.linux).reason), findsOneWidget);
    expect(find.text('✓'), findsNWidgets(2));
    expect(find.text('✗'), findsNWidgets(2));
  });

  testWidgets('download button is disabled and says it arrives in the next stage', (t) async {
    await t.pumpWidget(page(catalog.distros.first));
    final b = find.widgetWithText(FilledButton, 'İndir (sonraki aşamada)');
    expect(b, findsOneWidget);
    expect(t.widget<FilledButton>(b).onPressed, isNull);
  });

  testWidgets('windows distro shows the bring-your-own-ISO note', (t) async {
    await t.pumpWidget(page(catalog.distros[1]));
    expect(find.textContaining('BesideOS ISO dosyası sağlamaz'), findsOneWidget);
    await t.pumpWidget(page(catalog.distros[0]));
    expect(find.textContaining('BesideOS ISO dosyası sağlamaz'), findsNothing);
  });

  testWidgets('unknown id route shows "Bulunamadı"', (t) async {
    for (final n in ['/distros/nope', '/distros/', '/distros/a/b']) {
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
}
