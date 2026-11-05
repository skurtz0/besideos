import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart' as impl;

/// Opens a web address in the browser (a new tab on the site, the default browser in the app).
void openExternal(String url) => impl.openExternal(url);

/// The app packages, served from the site root.
const kWindowsDownloadPath = 'BesideOS-Setup.exe';
const kLinuxDownloadPath = 'besideos-linux-amd64.deb';
const kLinuxRpmPath = 'besideos-linux-x86_64.rpm';
const kLinuxArchPath = 'besideos-linux-x86_64.pkg.tar.zst';

/// Linux package formats offered to Linux visitors: label, file under the site root.
const kLinuxPackages = <(String, String, String)>[
  ('.deb', 'Debian, Ubuntu, Linux Mint, Pop!_OS', kLinuxDownloadPath),
  ('.rpm', 'Fedora, openSUSE, RHEL', kLinuxRpmPath),
  ('.pkg.tar.zst', 'Arch, Manjaro, CachyOS, EndeavourOS', kLinuxArchPath),
];

/// The package the visitor's browser hints at (Firefox names Fedora/Ubuntu/...); the `.deb` when it says nothing.
String recommendedLinuxPackage(String userAgent) {
  final ua = userAgent.toLowerCase();
  if (RegExp(r'fedora|red hat|centos|suse').hasMatch(ua)) return kLinuxRpmPath;
  if (RegExp(r'arch|manjaro').hasMatch(ua)) return kLinuxArchPath;
  return kLinuxDownloadPath;
}

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
      final ua = impl.browserUserAgent();
      final file = appDownloadFor(ua);
      if (file == kLinuxDownloadPath) {
        _pickLinuxPackage(context, recommendedLinuxPackage(ua));
      } else {
        impl.startDownload(file, file);
      }
    }
  }

  static Future<void> _pickLinuxPackage(BuildContext context, String recommended) async {
    final file = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Linux'),
        children: [
          for (final (ext, distros, path) in kLinuxPackages)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, path),
              child: ListTile(
                leading: Icon(path == recommended ? Icons.download_for_offline : Icons.download),
                title: Text(ext),
                subtitle: Text(distros),
              ),
            ),
        ],
      ),
    );
    if (file != null) impl.startDownload(file, file);
  }

  @override
  bool updateShouldNotify(SiteMode oldWidget) => oldWidget.web != web;
}
