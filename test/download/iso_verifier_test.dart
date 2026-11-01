import 'dart:io';
import 'package:besideos_site/download/iso_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

const _abc = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

Future<File> _abcFile() async {
  final d = await Directory.systemTemp.createTemp('v');
  addTearDown(() => d.delete(recursive: true));
  return File('${d.path}/x.iso')..writeAsStringSync('abc');
}

void main() {
  test('ok when hash matches (case-insensitive expected)', () async {
    final f = await _abcFile();
    final r = await verifyIso(f, _abc.toUpperCase());
    expect(r.outcome, VerifyOutcome.ok);
    expect(f.existsSync(), isTrue);
  });
  test('mismatch deletes the file and returns both hashes', () async {
    final f = await _abcFile();
    final other = 'a' * 64;
    final r = await verifyIso(f, other);
    expect(r.outcome, VerifyOutcome.mismatch);
    expect(r.actual, _abc);
    expect(r.expected, other);
    expect(f.existsSync(), isFalse);
  });
  test('invalid expected hash returns unreadable and keeps file', () async {
    final f = await _abcFile();
    expect((await verifyIso(f, 'xyz')).outcome, VerifyOutcome.unreadable);
    expect(f.existsSync(), isTrue);
  });
  test('missing file returns unreadable', () async {
    final r = await verifyIso(File('/nonexistent/zz.iso'), _abc);
    expect(r.outcome, VerifyOutcome.unreadable);
  });
}
