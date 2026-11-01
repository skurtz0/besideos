import 'dart:io';
import 'checksum.dart';

enum VerifyOutcome { ok, mismatch, unreadable }

class VerifyResult {
  final VerifyOutcome outcome;
  final String? actual;
  final String? expected;
  const VerifyResult(this.outcome, {this.actual, this.expected});
}

/// Fails closed: anything but an exact match is not `ok`; a mismatch deletes the file unless deleteOnMismatch is false (user's own files).
Future<VerifyResult> verifyIso(File f, String expectedSha256,
    {bool deleteOnMismatch = true}) async {
  final expected = normalizeSha256(expectedSha256);
  if (expected == null) return const VerifyResult(VerifyOutcome.unreadable);
  try {
    if (!f.existsSync()) return VerifyResult(VerifyOutcome.unreadable, expected: expected);
    final actual = await sha256OfFile(f);
    if (actual == expected) {
      return VerifyResult(VerifyOutcome.ok, actual: actual, expected: expected);
    }
    if (deleteOnMismatch) await f.delete();
    return VerifyResult(VerifyOutcome.mismatch, actual: actual, expected: expected);
  } on IOException {
    return VerifyResult(VerifyOutcome.unreadable, expected: expected);
  }
}
