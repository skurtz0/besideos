import 'dart:io';

import 'package:besideos_site/install/iso_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('besideos_iso_find'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File make(String rel, int bytes, {DateTime? modified}) {
    final f = File('${tmp.path}/$rel')..createSync(recursive: true);
    f.writeAsBytesSync(List.filled(bytes, 7));
    if (modified != null) f.setLastModifiedSync(modified);
    return f;
  }

  test('finds ISO files of a megabyte or more, newest first, ignoring other files', () {
    make('Downloads/old.iso', 2 << 20, modified: DateTime(2024));
    make('Downloads/new.ISO', 3 << 20, modified: DateTime(2026));
    make('Downloads/notes.txt', 5 << 20);
    make('Downloads/tiny.iso', 100); // not a real installer image
    make('Desktop/mid.iso', 2 << 20, modified: DateTime(2025));
    final found = findLocalIsos(dirs: [Directory('${tmp.path}/Downloads'), Directory('${tmp.path}/Desktop')]);
    expect(found.map((x) => x.name), ['new.ISO', 'mid.iso', 'old.iso']);
    expect(found.first.bytes, 3 << 20);
  });

  test('does not go into sub folders, copes with missing folders and respects the limit', () {
    make('Downloads/sub/deep.iso', 2 << 20);
    for (var i = 0; i < 9; i++) {
      make('Downloads/f$i.iso', 2 << 20, modified: DateTime(2026, 1, i + 1));
    }
    final found = findLocalIsos(limit: 4, dirs: [Directory('${tmp.path}/Downloads'), Directory('${tmp.path}/Nope')]);
    expect(found.length, 4);
    expect(found.any((x) => x.name == 'deep.iso'), isFalse);
    expect(found.first.name, 'f8.iso');
  });

  test('uses Downloads, Desktop and Documents of the profile folder by default', () {
    make('home/Downloads/a.iso', 2 << 20);
    make('home/Documents/b.iso', 2 << 20);
    final found = findLocalIsos(env: {'USERPROFILE': '${tmp.path}/home'});
    expect(found.map((x) => x.name).toSet(), {'a.iso', 'b.iso'});
  });
}