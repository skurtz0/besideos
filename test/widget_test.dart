import 'package:besideos_site/main.dart';
import 'dart:ui' show Size;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home page shows the pitch and the honest status', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BesideSite());

    expect(find.textContaining('Install another operating system'), findsOneWidget);
    expect(find.text('Status: early development'), findsOneWidget);
  });
}
