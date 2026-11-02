import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _json = '''
{"distros":[
{"id":"mint","name":"Ad mint","family":"linux","tagline":"Slogan mint","description":"d","bestFor":"b","look":"l","accent":4281558681,"guide":[{"title":"Adim bir","body":"x"}],"requirements":["r"],"hosts":["windows"],"downloadPage":"https://example.com","userSuppliedIso":false,"license":"GPL","isos":[{"arch":"x86_64","url":"https://e.org/a.iso","checksumUrl":"https://e.org/S","fileName":"a.iso"}]},
{"id":"win","name":"Ad win","family":"windows","tagline":"Slogan win","description":"d","bestFor":"b","look":"l","accent":4278221012,"guide":[{"title":"Adim iki","body":"y"}],"requirements":["r"],"hosts":["windows"],"downloadPage":"https://example.com","userSuppliedIso":true,"license":"Ticari"}
]}
''';

/// The home page animates forever, so pumpAndSettle never returns; step a fixed number of frames instead.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

Future<int> _pump(WidgetTester t, {required bool web, String route = '/'}) async {
  t.view.physicalSize = const Size(1200, 6000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  var downloads = 0;
  await t.pumpWidget(BesideSite(
    catalog: Catalog.parse(_json),
    web: web,
    initialRoute: route,
    onDownload: () => downloads++,
  ));
  await _settle(t);
  return downloads;
}

void main() {
  testWidgets('website home: the big button downloads the app; the bar has an İndir button', (t) async {
    var downloads = 0;
    t.view.physicalSize = const Size(1200, 6000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(BesideSite(catalog: Catalog.parse(_json), web: true, onDownload: () => downloads++));
    await _settle(t);
    expect(find.text('İndirmek için tıklayın'), findsOneWidget);
    expect(find.text('Başlamak için tıklayın'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'İndir'), findsOneWidget);
    await t.tap(find.text('İndirmek için tıklayın'));
    await t.tap(find.widgetWithText(FilledButton, 'İndir'));
    expect(downloads, 2);
  });

  testWidgets('website home lists the systems right above the status note', (t) async {
    await _pump(t, web: true);
    expect(find.text('Hangi sistemleri kurabilirsin?'), findsOneWidget);
    expect(find.text('Ad mint'), findsOneWidget);
    expect(find.text('Ad win'), findsOneWidget);
    final cards = t.getTopLeft(find.text('Ad win')).dy;
    final status = t.getTopLeft(find.text('Durum: erken geliştirme')).dy;
    final safety = t.getTopLeft(find.text('Önce güvenlik')).dy;
    expect(cards, lessThan(status));
    expect(cards, greaterThan(safety));
    // a card opens its distro page
    await t.tap(find.text('Ad mint'));
    await _settle(t);
    expect(find.text('Slogan mint'), findsWidgets);
  });

  testWidgets('desktop app keeps "Başlamak için tıklayın" and has no download button', (t) async {
    await _pump(t, web: false);
    expect(find.text('Başlamak için tıklayın'), findsOneWidget);
    expect(find.text('İndirmek için tıklayın'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'İndir'), findsNothing);
  });

  testWidgets('the İndir button stays in the bar while browsing the catalog and a distro', (t) async {
    await _pump(t, web: true, route: '/distros');
    expect(find.widgetWithText(FilledButton, 'İndir'), findsOneWidget);
    await t.tap(find.text('Ad mint'));
    await _settle(t);
    expect(find.widgetWithText(FilledButton, 'İndir'), findsOneWidget);
  });

  testWidgets('website distro page ends after the requirements: no manual steps, ISO tools or licence', (t) async {
    await _pump(t, web: true, route: '/distros/mint');
    expect(find.text('Bilgisayarında neler olmalı?'), findsOneWidget);
    expect(find.text('Elle kurmak istersen: adımlar'), findsNothing);
    expect(find.text('Kurulamayanlar'), findsNothing);
    expect(find.text('Sadece ISO dosyasını indir'), findsNothing);
    expect(find.textContaining('Lisans:'), findsNothing);
    expect(find.text('Resmi sayfa'), findsNothing);
    expect(find.text('Kurmak için BesideOS uygulamasını indir'), findsOneWidget);
  });

  testWidgets('the same distro page in the app has no manual steps either, but keeps licence and the one-click box', (t) async {
    await _pump(t, web: false, route: '/distros/mint');
    expect(find.text('Elle kurmak istersen: adımlar'), findsNothing);
    expect(find.text('Kurulamayanlar'), findsNothing);
    expect(find.textContaining('Lisans:'), findsOneWidget);
  });

  testWidgets('every distro page on the website offers the app download, own-ISO systems included', (t) async {
    for (final id in ['mint', 'win']) {
      await _pump(t, web: true, route: '/distros/$id');
      expect(find.text('Kurmak için BesideOS uygulamasını indir'), findsOneWidget, reason: id);
      expect(find.textContaining('kendi ISO dosyanı getirmen'), findsNothing, reason: id);
    }
  });
}