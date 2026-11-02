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
