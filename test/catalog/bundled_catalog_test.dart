import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/catalog/support_matrix.dart';

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
}
