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

  Map<String, dynamic> shot({String file = 'assets/screens/a.jpg'}) =>
      {'file': file, 'caption': 'Masaüstü', 'credit': 'Görsel: X', 'source': 'https://commons.wikimedia.org/wiki/File:A.png'};

  test('screens are optional and parsed when present', () {
    expect(Catalog.parse(cat([d('a')])).byId('a')!.screens, isEmpty);
    final s = Catalog.parse(cat([d('a', over: {'screens': [shot()]})])).byId('a')!.screens.single;
    expect(s.file, 'assets/screens/a.jpg');
    expect(s.caption, 'Masaüstü');
    expect(s.source, startsWith('https://'));
  });

  test('rejects unsafe or malformed screens', () {
    for (final bad in <Object>[
      [shot(file: 'assets/catalog/catalog.json')],
      [shot(file: 'assets/screens/../x.jpg')],
      [shot(file: r'assets\screens\x.jpg')],
      [{'file': 'assets/screens/a.jpg', 'caption': '', 'credit': 'c'}],
      [{'file': 'assets/screens/a.jpg', 'caption': 'c', 'credit': 'c', 'source': 'http://x.org'}],
      ['x'],
      'nope',
    ]) {
      expect(() => Catalog.parse(cat([d('a', over: {'screens': bad})])), throwsA(isA<CatalogException>()), reason: '$bad');
    }
  });

  Map<String, dynamic> variant(String id, {List? isos}) => {
        'id': id,
        'label': 'Etiket $id',
        'note': 'Not $id',
        'isos': isos ??
            [
              {'arch': 'x86_64', 'url': 'https://e.org/$id.iso', 'checksumUrl': 'https://e.org/SUMS', 'fileName': '$id.iso'}
            ],
      };

  test('variants parse, and withVariant swaps ISOs and pictures only', () {
    final x = Catalog.parse(cat([
      d('a', over: {
        'screens': [shot()],
        'variants': [variant('one'), {...variant('two'), 'screens': [shot(file: 'assets/screens/two.jpg')]}],
      })
    ])).byId('a')!;
    expect(x.variants.map((v) => v.id), ['one', 'two']);
    final two = x.withVariant(x.variants[1]);
    expect(two.name, x.name);
    expect(two.isoFor(IsoArch.x86_64)!.fileName, 'two.iso');
    expect(two.screens.single.file, 'assets/screens/two.jpg');
    expect(x.withVariant(x.variants[0]).screens.single.file, 'assets/screens/a.jpg');
  });

  test('rejects malformed or duplicate variants', () {
    for (final bad in <Object>[
      [variant('x'), variant('x')],
      [{...variant('x'), 'label': ''}],
      [{...variant('x'), 'isos': [{'arch': 'sparc'}]}],
      ['x'],
      'nope',
    ]) {
      expect(() => Catalog.parse(cat([d('a', over: {'variants': bad})])), throwsA(isA<CatalogException>()), reason: '$bad');
    }
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

  test('basedOn parsed when present, null when absent', () {
    final c = Catalog.parse(cat([d('a', over: {'basedOn': 'Debian'}), d('b')]));
    expect(c.byId('a')!.basedOn, 'Debian');
    expect(c.byId('b')!.basedOn, isNull);
  });

  Map<String, dynamic> iso({String arch = 'x86_64', String url = 'https://e.com/x.iso', String sum = 'https://e.com/SHA256SUMS', String file = 'x.iso', Object? size = 123}) =>
      {'arch': arch, 'url': url, 'checksumUrl': sum, 'fileName': file, 'sizeBytes': size};

  void bad(List<Map<String, dynamic>> isos) => expect(
      () => Catalog.parse(cat([d('a', over: {'isos': isos})])),
      throwsA(isA<CatalogException>()
          .having((e) => e.message, 'message', allOf(contains('a:'), contains('isos')))));

  test('parses isos list', () {
    final x = Catalog.parse(cat([d('a', over: {'isos': [iso(), iso(arch: 'arm64', size: null)]})])).byId('a')!;
    expect(x.isos.length, 2);
    expect(x.isos[0].arch, IsoArch.x86_64);
    expect(x.isos[0].url, 'https://e.com/x.iso');
    expect(x.isos[0].checksumUrl, 'https://e.com/SHA256SUMS');
    expect(x.isos[0].fileName, 'x.iso');
    expect(x.isos[0].sizeBytes, 123);
    expect(x.isos[1].sizeBytes, isNull);
    expect(x.isoFor(IsoArch.arm64), x.isos[1]);
  });

  test('isos absent means empty list', () {
    expect(Catalog.parse(cat([d('a')])).byId('a')!.isos, isEmpty);
  });

  test('rejects http url', () => bad([iso(url: 'http://e.com/x.iso')]));
  test('rejects http checksumUrl', () => bad([iso(sum: 'http://e.com/SUMS')]));

  test('rejects fileName with path separator or ..', () {
    for (final f in ['a/b.iso', r'a\b.iso', '..', '../x.iso', '']) {
      bad([iso(file: f)]);
    }
  });

  test('rejects unknown arch', () => bad([iso(arch: 'riscv')]));
  test('rejects duplicate arch within a distro', () => bad([iso(), iso()]));

  test('isoFor returns null when arch missing', () {
    final x = Catalog.parse(cat([d('a', over: {'isos': [iso()]})])).byId('a')!;
    expect(x.isoFor(IsoArch.arm64), isNull);
  });
}
