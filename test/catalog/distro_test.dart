import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:besideos_site/catalog/distro.dart';

Map<String, dynamic> d(String id, {Object? family = 'linux', Map<String, dynamic>? over}) => {
      'id': id,
      'name': 'Name $id',
      'family': family,
      'tagline': 't',
      'description': 'desc',
      'bestFor': 'b',
      'desktop': 'GNOME',
      'look': 'l',
      'accent': 0xFFE95420,
      'guide': [
        {'title': 'Step', 'body': 'Body'}
      ],
      'requirements': ['2 GB RAM'],
      'hosts': ['windows', 'linux', 'mac-m1m2'],
      'downloadPage': 'https://example.com',
      'userSuppliedIso': false,
      'license': 'GPL',
      ...?over,
    };

String cat(List<Map<String, dynamic>> l) => jsonEncode({'distros': l});

void main() {
  test('parses a valid catalog', () {
    final c = Catalog.parse(cat([d('a')]));
    expect(c.distros.length, 1);
    final x = c.byId('a')!;
    expect(x.name, 'Name a');
    expect(x.family, DistroFamily.linux);
    expect(x.desktop, 'GNOME');
    expect(x.accent, 0xFFE95420);
    expect(x.guide.single.title, 'Step');
    expect(x.hosts, ['windows', 'linux', 'mac-m1m2']);
    expect(x.userSuppliedIso, false);
  });

  test('rejects duplicate ids', () {
    expect(() => Catalog.parse(cat([d('a'), d('a')])), throwsA(isA<CatalogException>()));
  });

  test('rejects unknown family', () {
    expect(() => Catalog.parse(cat([d('a', family: 'bsd')])), throwsA(isA<CatalogException>()));
  });

  test('rejects empty id', () {
    expect(() => Catalog.parse(cat([d('')])), throwsA(isA<CatalogException>()));
  });

  test('rejects unknown host', () {
    expect(() => Catalog.parse(cat([d('a', over: {'hosts': ['beos']})])),
        throwsA(isA<CatalogException>()));
  });

  test('error names id and field', () {
    expect(
        () => Catalog.parse(cat([d('a', over: {'name': 3})])),
        throwsA(isA<CatalogException>()
            .having((e) => e.message, "message", allOf(contains("a"), contains("name")))));
  });

  test('optional desktop may be null', () {
    final c = Catalog.parse(cat([d('a', over: {'desktop': null})]));
    expect(c.byId('a')!.desktop, isNull);
  });

  test('byId unknown returns null', () {
    expect(Catalog.parse(cat([d('a')])).byId('zzz'), isNull);
  });

  test('empty distros list parses', () {
    expect(Catalog.parse(cat([])).distros, isEmpty);
  });
}
