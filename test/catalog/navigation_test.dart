import 'dart:ui' show Size;

import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/main.dart';
import 'package:flutter_test/flutter_test.dart';

const _json = '''
{"distros":[{"id":"mint","name":"Ad mint","family":"linux","tagline":"Slogan mint","description":"d","bestFor":"b","look":"l","accent":4281558681,"guide":[{"title":"Adim bir","body":"x"}],"requirements":["r"],"hosts":["windows"],"downloadPage":"https://example.com","userSuppliedIso":false,"license":"GPL"}]}
''';

void main() {
  testWidgets('home link opens catalog, tapping a distro opens its guide', (t) async {
    t.view.physicalSize = const Size(1200, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(BesideSite(catalog: Catalog.parse(_json)));
    await t.tap(find.text('Başlamak için tıklayın'));
    await t.pumpAndSettle();
    expect(find.text('Ad mint'), findsOneWidget);

    await t.tap(find.text('Ad mint'));
    await t.pumpAndSettle();
    expect(find.text('Slogan mint'), findsOneWidget);
  });

  testWidgets('a failing catalog load shows an error page, not a blank screen', (t) async {
    t.view.physicalSize = const Size(1200, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(BesideSite(catalogLoader: () async => '{bad'));
    await t.tap(find.text('Başlamak için tıklayın'));
    await t.pumpAndSettle();
    expect(find.textContaining('Katalog yüklenemedi'), findsOneWidget);
    expect(find.textContaining('invalid JSON'), findsOneWidget);
  });
}
