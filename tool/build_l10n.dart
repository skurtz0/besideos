// Turns the translation files into assets/l10n/<code>.json.
//   tool/l10n/<code>.txt          one translation per line, in the order of tool/l10n_keys.txt (the app's texts)
//   tool/l10n/<code>.catalog.txt  the same for tool/l10n_keys_catalog.txt (texts of assets/catalog/catalog.json)
// Checks that every line is there and keeps the {placeholders} of its Turkish key. Usage: dart run tool/build_l10n.dart
import 'dart:convert';
import 'dart:io';

final _ph = RegExp(r'\{[A-Za-z0-9_]+\}');

List<String> _lines(String path) => File(path).readAsLinesSync().where((l) => l.isNotEmpty).toList();

String _phOf(String s) => (_ph.allMatches(s).map((m) => m[0]!).toList()..sort()).join();

void main() {
  final sets = <(String, List<String>)>[
    ('', _lines('tool/l10n_keys.txt')),
    ('.catalog', _lines('tool/l10n_keys_catalog.txt')),
  ];
  var bad = 0;
  for (final f in Directory('tool/l10n').listSync().whereType<File>().where((f) => f.path.endsWith('.txt') && !f.path.endsWith('.catalog.txt'))) {
    final code = f.uri.pathSegments.last.replaceAll('.txt', '');
    final map = <String, String>{};
    for (final (suffix, keys) in sets) {
      final file = File('tool/l10n/$code$suffix.txt');
      if (!file.existsSync()) {
        stderr.writeln('$code: no $code$suffix.txt yet (those texts stay Turkish)');
        continue;
      }
      final lines = file.readAsLinesSync();
      if (lines.length != keys.length) {
        stderr.writeln('$code$suffix: ${lines.length} lines, expected ${keys.length}');
        bad++;
        continue;
      }
      for (var i = 0; i < keys.length; i++) {
        if (_phOf(keys[i]) != _phOf(lines[i])) {
          stderr.writeln('$code$suffix line ${i + 1}: placeholders differ');
          bad++;
        }
        map[keys[i]] = lines[i];
      }
    }
    File('assets/l10n/$code.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(map));
    stdout.writeln('$code: ${map.length} texts');
  }
  if (bad > 0) exit(1);
}
