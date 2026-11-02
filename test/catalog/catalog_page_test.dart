import 'package:besideos_site/catalog/catalog_page.dart';
import 'package:besideos_site/catalog/distro.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Distro d(String id, DistroFamily f, List<String> hosts) => Distro(
      id: id,
      name: 'Ad $id',
      family: f,
      tagline: 'Slogan $id',
      description: '',
      bestFor: '',
      look: '',
      accent: 0xFF336699,
      guide: const [],
      requirements: const [],
      hosts: hosts,
      downloadPage: '',
      userSuppliedIso: false,
      license: '',
    );

final catalog = Catalog([
  d('mint', DistroFamily.linux, ['windows', 'linux', 'mac-m1m2']),
  d('win', DistroFamily.windows, ['windows', 'linux']),
]);

Future<void> pump(WidgetTester t, Catalog c, {void Function(Distro)? onOpen}) =>
    t.pumpWidget(MaterialApp(
      home: Scaffold(body: CatalogPage(catalog: c, onOpen: onOpen ?? (_) {})),
    ));

void main() {
  testWidgets('lists every distro name', (t) async {
    await pump(t, catalog);
    expect(find.text('Ad mint'), findsOneWidget);
    expect(find.text('Ad win'), findsOneWidget);
  });

  testWidgets('family filter shows only windows', (t) async {
    await pump(t, catalog);
    await t.tap(find.text('Windows').first);
    await t.pump();
    expect(find.text('Ad mint'), findsNothing);
    expect(find.text('Ad win'), findsOneWidget);
  });

  testWidgets('host filter "Mac M1/M2" hides windows distros', (t) async {
    await pump(t, catalog);
    await t.tap(find.text('Mac M1/M2'));
    await t.pump();
    expect(find.text('Ad mint'), findsOneWidget);
    expect(find.text('Ad win'), findsNothing);
  });

  testWidgets('other Mac matches nothing and explains', (t) async {
    await pump(t, catalog);
    await t.tap(find.text('Diğer Mac'));
    await t.pump();
    expect(find.text('Ad mint'), findsNothing);
    expect(find.textContaining('Asahi'), findsOneWidget);
  });

  testWidgets('empty catalog shows "Katalog boş"', (t) async {
    await pump(t, const Catalog([]));
    expect(find.text('Katalog boş'), findsOneWidget);
  });

  testWidgets('does not overflow at 320x640', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pump(t, catalog);
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping a card calls onOpen with that distro', (t) async {
    Distro? opened;
    t.view.physicalSize = const Size(1000, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pump(t, catalog, onOpen: (x) => opened = x);
    await t.tap(find.text('Ad win'));
    expect(opened?.id, 'win');
  });

  testWidgets('card exposes button semantics with the distro name', (t) async {
    final h = t.ensureSemantics();
    await pump(t, catalog);
    final n = t.getSemantics(find.text('Ad win'));
    expect(n.label, contains('Ad win'));
    expect(n.flagsCollection.isButton, isTrue);
    h.dispose();
  });

  testWidgets('focused card activates with Enter', (t) async {
    Distro? opened;
    await pump(t, catalog, onOpen: (x) => opened = x);
    Focus.of(t.element(find.text('Ad win'))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened?.id, 'win');
  });

  testWidgets('host filter hides distro whose host the matrix rejects', (t) async {
    await pump(t, Catalog([d('lx', DistroFamily.linux, ['linux'])]));
    await t.tap(find.text('Linux').last);
    await t.pump();
    expect(find.text('Ad lx'), findsNothing);
  });
}
