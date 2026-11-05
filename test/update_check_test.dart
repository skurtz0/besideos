import 'dart:io';

import 'package:besideos_site/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isNewer compares x.y.z numerically', () {
    expect(isNewer('v0.2.0', '0.1.0'), isTrue);
    expect(isNewer('v0.10.0', '0.9.5'), isTrue);
    expect(isNewer('v0.1.0', '0.1.0'), isFalse);
    expect(isNewer('v0.0.9', '0.1.0'), isFalse);
    expect(isNewer('nightly', '0.1.0'), isFalse);
  });

  test('kAppVersion matches pubspec.yaml', () {
    final v = RegExp(r'^version:\s*([0-9.]+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())![1];
    expect(kAppVersion, v);
  });
}
