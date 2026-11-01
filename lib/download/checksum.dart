import 'dart:io';
import 'package:crypto/crypto.dart';

final _line = RegExp(r'^([0-9A-Fa-f]{64}) [ *](.+)$');
final _bsd = RegExp(r'^SHA256 \((.+)\) = ([0-9A-Fa-f]{64})$');
final _hex64 = RegExp(r'^[0-9a-f]{64}$');
final _safeName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$');

/// Parses SHA256SUMS text: name -> lowercase hex. Bad lines are skipped.
Map<String, String> parseChecksums(String text) {
  final out = <String, String>{};
  final conflicts = <String>{};
  for (final raw in text.split('\n')) {
    final t = raw.trim();
    final b = _bsd.firstMatch(t);
    final m = b ?? _line.firstMatch(t);
    if (m == null) continue;
    final name = b != null ? m.group(1)! : m.group(2)!;
    final h = (b != null ? m.group(2)! : m.group(1)!).toLowerCase();
    if (out.containsKey(name) && out[name] != h) conflicts.add(name);
    out[name] = h;
  }
  out.removeWhere((k, _) => conflicts.contains(k)); // fail closed on ambiguity
  return out;
}

String? expectedHashFor(Map<String, String> sums, String fileName) =>
    sums[fileName];

Future<String> sha256OfFile(File f) async =>
    (await sha256.bind(f.openRead()).first).toString();

bool isSafeFileName(String name) =>
    name.length <= 255 &&
    _safeName.hasMatch(name) &&
    !name.contains('..') &&
    !name.endsWith('.');

String? normalizeSha256(String input) {
  var s = input.trim().toLowerCase();
  if (s.startsWith('sha256:')) s = s.substring(7).trim();
  return _hex64.hasMatch(s) ? s : null;
}
