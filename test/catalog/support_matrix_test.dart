import 'package:flutter_test/flutter_test.dart';
import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/catalog/support_matrix.dart';

void main() {
  test('windows→linux supported', () => expect(supportFor(Host.windows, DistroFamily.linux).supported, isTrue));
  test('linux→windows supported', () => expect(supportFor(Host.linux, DistroFamily.windows).supported, isTrue));
  test('windows→windows supported', () => expect(supportFor(Host.windows, DistroFamily.windows).supported, isTrue));
  test('macM1M2→linux supported', () => expect(supportFor(Host.macM1M2, DistroFamily.linux).supported, isTrue));
  test('macM1M2→windows unsupported', () {
    final e = supportFor(Host.macM1M2, DistroFamily.windows);
    expect(e.supported, isFalse);
    expect(e.reason, contains('Apple Silicon'));
  });
  test('macOther→linux unsupported', () {
    final e = supportFor(Host.macOther, DistroFamily.linux);
    expect(e.supported, isFalse);
    expect(e.reason, contains('M1/M2'));
  });
  test('hostKey maps hosts, macOther null', () {
    expect(hostKey(Host.macM1M2), 'mac-m1m2');
    expect(hostKey(Host.macOther), isNull);
  });
  test('macOther→windows unsupported', () => expect(supportFor(Host.macOther, DistroFamily.windows).supported, isFalse));
  test('linux→linux unsupported', () {
    final e = supportFor(Host.linux, DistroFamily.linux);
    expect(e.supported, isFalse);
    expect(e.reason, contains('kapsam dışı'));
  });
  test('unsupportedTargets lists macOS and Windows-on-Apple-Silicon', () {
    final keys = unsupportedTargets.map((e) => e.key);
    expect(keys, contains('macOS (herhangi bir sistemin yanına)'));
    expect(keys, contains('Windows (Apple Silicon Mac yanına)'));
    expect(unsupportedTargets.every((e) => !e.value.supported), isTrue);
  });
}
