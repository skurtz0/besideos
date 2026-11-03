import 'package:besideos_site/main.dart';
import 'dart:ui' show Size;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home page shows the pitch and the honest status', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BesideSite());

    expect(find.textContaining('Bilgisayarına USB bellek gerekmeden ikinci bir sistem kur.'), findsOneWidget);
    expect(find.text('Başlamak için tıklayın'), findsOneWidget);
    expect(find.text('Kurmadan önce yedek al'), findsOneWidget);
  });
}
