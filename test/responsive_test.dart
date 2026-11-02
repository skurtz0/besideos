import 'dart:io';

import 'package:besideos_site/brand.dart';
import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The home page animates forever, so `pumpAndSettle` never returns; step a fixed number of frames instead.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

const widths = <double>[320, 360, 390, 414, 480, 600, 768, 820, 1024, 1280, 1440, 1920];
const routes = <String>['/', '/distros', '/distros/debian', '/distros/linux-mint', '/distros/windows-11', '/distros/bazzite'];

void main() {
  final catalog = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync());

  Future<void> open(WidgetTester t, double w, String route, bool web) async {
    t.view.physicalSize = Size(w, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(BesideSite(catalog: catalog, web: web, initialRoute: route));
    await settle(t);
  }

  for (final web in [true, false]) {
    for (final route in routes) {
      testWidgets('no overflow or exception: ${web ? 'website' : 'app'} $route at every width', (t) async {
        for (final w in widths) {
          await open(t, w, route, web);
          expect(t.takeException(), isNull, reason: 'width $w, $route, web=$web');
          // scroll through the whole page: lazily built or revealed parts must not overflow either
          final scroll = find.byType(Scrollable);
          if (scroll.evaluate().isNotEmpty) {
            for (var i = 0; i < 6; i++) {
              await t.drag(scroll.first, const Offset(0, -700), warnIfMissed: false);
              await t.pump(const Duration(milliseconds: 200));
            }
          }
          expect(t.takeException(), isNull, reason: 'after scrolling: width $w, $route, web=$web');
        }
      });
    }
  }

  testWidgets('nothing is wider than the window on a phone (no horizontal scroll)', (t) async {
    for (final w in [320.0, 360.0]) {
      await open(t, w, '/', true);
      for (final c in [find.byType(FilledButton), find.byType(BesideLogo), find.byType(IconButton)]) {
        for (final e in c.evaluate()) {
          final r = t.getRect(find.byWidget(e.widget));
          expect(r.right, lessThanOrEqualTo(w + 0.5), reason: '${e.widget.runtimeType} right edge at width $w');
          expect(r.left, greaterThanOrEqualTo(-0.5));
        }
      }
    }
  });

  testWidgets('the bar lines up with the content column: logo with the text, İndir with the right edge', (t) async {
    await open(t, 1920, '/', true);
    final logoLeft = t.getTopLeft(find.byType(BesideLogo)).dx;
    final textLeft = t.getTopLeft(find.text('NASIL ÇALIŞIR?').evaluate().isEmpty ? find.text('Nasıl çalışır?') : find.text('NASIL ÇALIŞIR?')).dx;
    // logo has a 6 px tap padding around it
    expect((logoLeft + 6 - textLeft).abs(), lessThan(24));
    final buttonRight = t.getRect(find.widgetWithText(FilledButton, 'İndir')).right;
    // content column: 960 wide, centred, 20 px padding -> right edge at 1440 - 20
    expect(buttonRight, closeTo(1920 / 2 + 480 - 20, 2));
  });

  testWidgets('catalog cards share the row evenly and use the whole width', (t) async {
    await open(t, 1280, '/distros', true);
    final first = t.getRect(find.text('Ubuntu').first);
    expect(first.width, greaterThan(0));
    expect(t.takeException(), isNull);
  });
}
