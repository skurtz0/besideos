import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart' as impl;

/// The app packages, served from the site root.
const kWindowsDownloadPath = 'BesideOS-Setup.exe';
const kLinuxDownloadPath = 'besideos-linux-amd64.deb';

/// Which package fits the visitor's system: Linux desktops get the Linux build, everything else the Windows one
/// (Android and ChromeOS report "Linux" too, but cannot run either; they stay on the default).
String appDownloadFor(String userAgent) {
  final ua = userAgent.toLowerCase();
  final linuxDesktop = ua.contains('linux') && !ua.contains('android') && !ua.contains('cros');
  return linuxDesktop ? kLinuxDownloadPath : kWindowsDownloadPath;
}

/// Whether this is the public website (shows "download the app") or the desktop app itself.
/// Defaults to [kIsWeb]; tests and previews can force either.
class SiteMode extends InheritedWidget {
  const SiteMode({super.key, required this.web, this.onDownload, required super.child});
  final bool web;

  /// Replaces the real browser download (tests).
  final VoidCallback? onDownload;

  static bool isWeb(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SiteMode>()?.web ?? kIsWeb;

  /// Starts the app download.
  static void download(BuildContext context) {
    final cb = context.getInheritedWidgetOfExactType<SiteMode>()?.onDownload;
    if (cb != null) {
      cb();
    } else {
      final file = appDownloadFor(impl.browserUserAgent());
      impl.startDownload(file, file);
    }
  }

  @override
  bool updateShouldNotify(SiteMode oldWidget) => oldWidget.web != web;
}
