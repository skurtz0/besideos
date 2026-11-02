import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart' as impl;

/// The Windows app package, served from the site root.
const kAppDownloadPath = 'BesideOS-windows.zip';

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
      impl.startDownload(kAppDownloadPath, kAppDownloadPath);
    }
  }

  @override
  bool updateShouldNotify(SiteMode oldWidget) => oldWidget.web != web;
}
