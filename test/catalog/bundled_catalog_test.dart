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
    expect(catalog.byId('fedora')!.hosts, contains('linux'));
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

  test('no separate "live" entries on the home catalog; choices live in variants', () {
    for (final d in catalog.distros) {
      expect(d.name.toLowerCase(), isNot(contains('live')), reason: d.id);
    }
    expect(catalog.byId('lubuntu'), isNull);
    final deb = catalog.byId('debian')!;
    expect(deb.variants.map((v) => v.id), ['live-xfce', 'live-kde']);
    expect(catalog.byId('linux-mint')!.variants.length, 3);
    expect(catalog.byId('bazzite')!.variants.length, greaterThanOrEqualTo(3));
    for (final d in catalog.distros.where((d) => d.variants.isNotEmpty)) {
      expect(d.isos, d.variants.first.isos.isEmpty ? isEmpty : isNotEmpty, reason: d.id);
      for (final v in d.variants) {
        expect(v.isos, isNotEmpty, reason: '${d.id}/${v.id}');
        expect(v.isos.every((i) => i.url.endsWith(i.fileName)), isTrue, reason: '${d.id}/${v.id}');
      }
    }
  });

  test('related systems sit side by side and Linux comes before Windows', () {
    final ids = catalog.distros.map((d) => d.id).toList();
    int at(String id) => ids.indexOf(id);
    expect((at('xubuntu') - at('ubuntu')).abs(), 1);
    expect((at('kubuntu') - at('xubuntu')).abs(), 1);
    expect(at('windows-xp'), lessThan(at('windows-7')));
    expect(at('windows-7'), lessThan(at('windows-8-1')));
    expect(at('windows-8-1'), lessThan(at('windows-10')));
    expect(at('windows-10'), lessThan(at('windows-11')));
    final lastLinux = ids.lastIndexWhere((id) => catalog.byId(id)!.family == DistroFamily.linux);
    final firstWin = ids.indexWhere((id) => catalog.byId(id)!.family == DistroFamily.windows);
    expect(lastLinux, lessThan(firstWin));
  });

  test('requested distros are present', () {
    for (final id in ['cachyos', 'omarchy', 'bazzite', 'windows-xp', 'windows-7', 'windows-8-1']) {
      expect(catalog.byId(id), isNotNull, reason: id);
    }
    expect(catalog.byId('cachyos')!.userSuppliedIso, isTrue);
    expect(catalog.byId('omarchy')!.userSuppliedIso, isFalse);
  });

  test('catalog offers many Linux and several Windows options', () {
    expect(catalog.distros.where((d) => d.family == DistroFamily.linux).length, greaterThanOrEqualTo(15));
    expect(catalog.distros.where((d) => d.family == DistroFamily.windows).length, greaterThanOrEqualTo(6));
  });

  test('every distro has a screenshot that exists, with a caption and credit', () {
    for (final d in catalog.distros) {
      expect(d.screens, isNotEmpty, reason: d.id);
      for (final s in [...d.screens, for (final v in d.variants) ...v.screens]) {
        final f = File(s.file);
        expect(f.existsSync(), isTrue, reason: '${d.id}: ${s.file}');
        expect(f.lengthSync(), greaterThan(5 * 1024), reason: s.file);
        expect(s.caption, isNotEmpty);
        expect(s.credit, isNotEmpty, reason: d.id);
        // pictures from Wikimedia Commons name it and link the file page; user-supplied ones carry no link
        if (s.source != null) {
          expect(s.credit, contains('Wikimedia Commons'), reason: d.id);
          expect(s.source, startsWith('https://commons.wikimedia.org/'), reason: d.id);
        }
      }
    }
  });
}
