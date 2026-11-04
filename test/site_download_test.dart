import 'package:besideos_site/site_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux desktops get the Linux package', () {
    expect(appDownloadFor('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126 Safari/537.36'), kLinuxDownloadPath);
    expect(appDownloadFor('Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0'), kLinuxDownloadPath);
  });

  test('Windows and unknown systems get the Windows package', () {
    expect(appDownloadFor('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126 Safari/537.36'), kWindowsDownloadPath);
    expect(appDownloadFor(''), kWindowsDownloadPath);
  });

  test('Android and ChromeOS report Linux but stay on the default', () {
    expect(appDownloadFor('Mozilla/5.0 (Linux; Android 14; Pixel 8) Chrome/126 Mobile Safari/537.36'), kWindowsDownloadPath);
    expect(appDownloadFor('Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) Chrome/126 Safari/537.36'), kWindowsDownloadPath);
  });
}
