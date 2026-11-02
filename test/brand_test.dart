import 'package:besideos_site/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('logo shows the mark and the word; mark alone when the word is hidden', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: BesideLogo())));
    expect(find.byType(BesideMark), findsOneWidget);
    expect(find.bySemanticsLabel('BesideOS'), findsOneWidget);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: BesideLogo(showWord: false))));
    expect(find.byType(BesideMark), findsOneWidget);
    expect(find.bySemanticsLabel('BesideOS'), findsNothing);
  });

  testWidgets('the site bar has a logo that goes home and names the page', (t) async {
    String? last;
    await t.pumpWidget(MaterialApp(
      onGenerateRoute: (s) {
        last = s.name;
        return MaterialPageRoute(
          settings: s,
          builder: (_) => Scaffold(appBar: const SiteBar(page: 'Dağıtımlar'), body: const SizedBox()),
        );
      },
    ));
    expect(find.text('Dağıtımlar'), findsOneWidget);
    await t.tap(find.byType(BesideLogo));
    await t.pumpAndSettle();
    expect(last, '/');
  });

  testWidgets('PageScroll keeps an always-visible scrollbar at the window edge and centres the content', (t) async {
    t.view.physicalSize = const Size(1400, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: PageScroll(maxWidth: 600, child: SizedBox(key: Key('c'), width: double.infinity, height: 3000, child: Text('icerik')))),
    ));
    await t.pump();
    final bar = t.widget<Scrollbar>(find.byType(Scrollbar));
    expect(bar.thumbVisibility, isTrue);
    expect(bar.trackVisibility, isTrue);
    // the scrollbar spans the whole window width (so its thumb sits at the far right) ...
    expect(t.getRect(find.byType(Scrollbar)).right, 1400);
    // ... while the content is a centred column no wider than maxWidth
    final box = t.getRect(find.byKey(const Key('c')));
    expect(box.width, 600);
    expect(box.center.dx, closeTo(700, 1));
  });
}
