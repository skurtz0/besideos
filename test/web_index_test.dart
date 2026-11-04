import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  webHeadersTest();
  test('the pages.dev address sends visitors on to besideos.com, keeping path and hash', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('pages'));
    expect(html, contains(r'pages\.dev$'));
    expect(html, contains('location.replace("https://besideos.com" + location.pathname + location.search + location.hash)'));
    // runs before the Flutter app is loaded
    expect(html.indexOf('location.replace'), lessThan(html.indexOf('flutter_bootstrap.js')));
  });
}

void webHeadersTest() {
  test('the files that keep their name between releases are never served from a stale cache', () {
    final h = File('web/_headers').readAsStringSync();
    for (final p in ['/main.dart.js', '/flutter_bootstrap.js', '/assets/*']) {
      expect(h, contains('$p\n  Cache-Control: no-cache'));
    }
  });
}
