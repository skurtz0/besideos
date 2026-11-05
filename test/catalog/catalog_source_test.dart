import 'dart:convert';
import 'dart:io';

import 'package:besideos_site/catalog/catalog_source.dart';
import 'package:besideos_site/catalog/distro.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bundledJson = File('assets/catalog/catalog.json').readAsStringSync();
  final bundled = Catalog.parse(bundledJson);

  Future<String> loadWith(String? remote) =>
      loadCatalogJson(() async => bundledJson, fetchRemote: () async => remote);

  test('a newer, complete catalog from the website replaces the bundled one', () async {
    final m = jsonDecode(bundledJson) as Map<String, dynamic>;
    final ubuntu = (m['distros'] as List).first as Map<String, dynamic>;
    (ubuntu['isos'] as List).first['fileName'] = 'ubuntu-99.04-desktop-amd64.iso';
    final fresh = jsonEncode(m);
    expect(await loadWith(fresh), fresh);
  });

  test('no network, bad JSON, missing or unknown distros or http links keep the bundled catalog', () async {
    expect(await loadWith(null), bundledJson);
    expect(await loadWith('{bad'), bundledJson);

    final fewer = jsonDecode(bundledJson) as Map<String, dynamic>;
    (fewer['distros'] as List).removeLast();
    expect(acceptRemoteCatalog(jsonEncode(fewer), bundled), isFalse);

    final extra = jsonDecode(bundledJson) as Map<String, dynamic>;
    final copy = Map<String, dynamic>.from((extra['distros'] as List).first as Map)..['id'] = 'brand-new';
    (extra['distros'] as List).add(copy);
    expect(acceptRemoteCatalog(jsonEncode(extra), bundled), isFalse);

    expect(acceptRemoteCatalog(bundledJson.replaceFirst('"https://releases.ubuntu.com', '"http://releases.ubuntu.com'), bundled),
        isFalse);
  });
}
