import 'dart:io';
import 'package:besideos_site/download/checksum.dart';
import 'package:flutter_test/flutter_test.dart';

const _h1 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const _h2 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

Future<File> _tmp(List<int> bytes) async {
  final d = await Directory.systemTemp.createTemp('cks');
  addTearDown(() => d.delete(recursive: true));
  final f = File('${d.path}/x');
  await f.writeAsBytes(bytes);
  return f;
}

void main() {
  test('parses two-space and star formats', () {
    final m = parseChecksums('$_h1  a.iso\n$_h2 *b.iso\n');
    expect(m, {'a.iso': _h1, 'b.iso': _h2});
  });
  test('ignores comments and blank and bad lines', () {
    final m = parseChecksums('# c\n\nzz  bad.iso\n$_h1  ok.iso\n${_h1}x  no.iso\n');
    expect(m, {'ok.iso': _h1});
  });
  test('uppercase hash normalized to lowercase', () {
    expect(parseChecksums('${_h2.toUpperCase()}  a.iso')['a.iso'], _h2);
  });
  test('expectedHashFor missing name returns null', () {
    expect(expectedHashFor({'a': _h1}, 'b'), isNull);
    expect(expectedHashFor({'a': _h1}, 'a'), _h1);
  });
  test('sha256OfFile of empty file equals $_h1', () async {
    expect(await sha256OfFile(await _tmp([])), _h1);
  });
  test('sha256OfFile of "abc" equals $_h2', () async {
    expect(await sha256OfFile(await _tmp('abc'.codeUnits)), _h2);
  });
  test('sha256OfFile streams a 20 MB file', () async {
    final f = await _tmp(List.filled(20 * 1024 * 1024, 0));
    expect(await sha256OfFile(f), hasLength(64));
    expect(await sha256OfFile(f), await sha256OfFile(f));
  });
  test('normalizeSha256 rejects 63 chars and non-hex', () {
    expect(normalizeSha256(_h2.substring(1)), isNull);
    expect(normalizeSha256('g${_h2.substring(1)}'), isNull);
    expect(normalizeSha256(' sha256:${_h2.toUpperCase()} \n'), _h2);
  });
  test('isSafeFileName accepts ubuntu-24.04-desktop-amd64.iso and rejects bad', () {
    expect(isSafeFileName('ubuntu-24.04-desktop-amd64.iso'), isTrue);
    for (final bad in [
      '..', '.', 'a/b', r'a\b', 'C:x.iso', 'a b', 'a\x00b', '%2f', 'a.',
      'a..b', '', 'a' * 256,
    ]) {
      expect(isSafeFileName(bad), isFalse, reason: bad);
    }
  });
}
