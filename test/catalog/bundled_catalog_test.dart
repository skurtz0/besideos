import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/catalog/support_matrix.dart';
import 'package:besideos_site/download/checksum.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled catalog parses and is sane', () async {
    final catalog = Catalog.parse(await rootBundle.loadString('assets/catalog/catalog.json'));
    final ds = catalog.distros;
    expect(ds.length, greaterThanOrEqualTo(5));
    expect(ds.map((d) => d.id).toSet().length, ds.length);
    for (final d in ds) {
      expect(d.id, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
      expect(d.guide.length, greaterThanOrEqualTo(3), reason: d.id);
      expect(d.hosts, isNotEmpty, reason: d.id);
      expect(d.hosts, isNot(contains('macos')), reason: d.id);
      expect(d.requirements, isNotEmpty, reason: d.id);
      expect(d.downloadPage, startsWith('https://'), reason: d.id);
      for (final k in d.hosts) {
        final h = Host.values.firstWhere((h) => hostKey(h) == k);
        expect(supportFor(h, d.family).supported, isTrue, reason: '${d.id} $k');
      }
      if (d.family == DistroFamily.windows) {
        expect(d.downloadPage.endsWith('.iso'), isFalse, reason: d.id);
      }
    }
    expect(catalog.byId('windows-11')!.userSuppliedIso, isTrue);
    expect(catalog.byId('ubuntu')!.basedOn, 'Debian');
    expect(catalog.byId('fedora')!.basedOn, isNull);
    expect(catalog.byId('fedora')!.hosts, contains('mac-m1m2'));
  });

  bundledIsoTests();
}

void bundledIsoTests() {
  late Catalog catalog;
  setUpAll(() async {
    catalog = Catalog.parse(await rootBundle.loadString('assets/catalog/catalog.json'));
  });

  test('bundled isos are https, have checksumUrl, safe fileName, and windows has none', () {
    for (final d in catalog.distros) {
      if (d.family == DistroFamily.windows) {
        expect(d.isos, isEmpty, reason: d.id);
      }
      for (final i in d.isos) {
        expect(Uri.parse(i.url).scheme, 'https', reason: d.id);
        expect(Uri.parse(i.checksumUrl).scheme, 'https', reason: d.id);
        expect(isSafeFileName(i.fileName), isTrue, reason: d.id);
        expect(i.url.endsWith(i.fileName), isTrue, reason: d.id);
      }
    }
  });

  test('every non-windows distro without a user-supplied ISO has an x86_64 iso', () {
    for (final d in catalog.distros.where((d) => d.family != DistroFamily.windows)) {
      if (d.userSuppliedIso) {
        expect(d.isos, isEmpty, reason: d.id);
      } else {
        expect(d.isoFor(IsoArch.x86_64), isNotNull, reason: d.id);
      }
    }
  });

  test('catalog offers many Linux and several Windows options', () {
    expect(catalog.distros.where((d) => d.family == DistroFamily.linux).length, greaterThanOrEqualTo(15));
    expect(catalog.distros.where((d) => d.family == DistroFamily.windows).length, greaterThanOrEqualTo(3));
  });

  test('every distro has a screenshot that exists, with a caption and credit', () {
    for (final d in catalog.distros) {
      expect(d.screens, isNotEmpty, reason: d.id);
      for (final s in d.screens) {
        final f = File(s.file);
        expect(f.existsSync(), isTrue, reason: '${d.id}: ${s.file}');
        expect(f.lengthSync(), greaterThan(5 * 1024), reason: s.file);
        expect(s.caption, isNotEmpty);
        expect(s.credit, contains('Wikimedia Commons'), reason: d.id);
        expect(s.source, startsWith('https://commons.wikimedia.org/'), reason: d.id);
      }
    }
  });
}
