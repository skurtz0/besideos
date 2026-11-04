import 'package:web/web.dart' as web;

/// Starts a browser download of [path] (relative to the site root) as [fileName].
void startDownload(String path, String fileName) {
  final a = web.HTMLAnchorElement()
    ..href = path
    ..download = fileName;
  web.document.body!.append(a);
  a.click();
  a.remove();
}

/// The visitor's browser user agent, used to pick the matching app package.
String browserUserAgent() => web.window.navigator.userAgent;
