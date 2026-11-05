import 'dart:io';

/// Not on the web: the desktop app never offers its own download.
void startDownload(String path, String fileName) {}

/// No browser here.
String browserUserAgent() => '';

/// Opens [url] in the default browser of the desktop app.
void openExternal(String url) {
  if (Platform.isWindows) {
    Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
  } else if (Platform.isLinux) {
    Process.run('xdg-open', [url]);
  }
}
