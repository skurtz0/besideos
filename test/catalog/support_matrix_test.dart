import 'package:flutter_test/flutter_test.dart';
import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/catalog/support_matrix.dart';

void main() {
  test('windows→linux supported', () => expect(supportFor(Host.windows, DistroFamily.linux).supported, isTrue));
  test('linux→windows supported', () => expect(supportFor(Host.linux, DistroFamily.windows).supported, isTrue));
  test('windows→windows supported', () => expect(supportFor(Host.windows, DistroFamily.windows).supported, isTrue));
  test('hostKey maps hosts', () {
    expect(hostKey(Host.windows), 'windows');
    expect(hostKey(Host.linux), 'linux');
  });
  test('linux→linux supported through a GRUB entry, no shrinking', () {
    final e = supportFor(Host.linux, DistroFamily.linux);
    expect(e.supported, isTrue);
    expect(e.reason, contains('GRUB'));
  });
}
