import 'dart:convert';
import 'dart:io';

import 'catalog_source.dart';

/// Downloads the current catalog from besideos.com (desktop app). Null on any problem: the bundled one is used.
Future<String?> fetchRemoteCatalog() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.getUrl(Uri.parse(kRemoteCatalogUrl)).timeout(const Duration(seconds: 6));
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final bytes = <int>[];
    await for (final chunk in res.timeout(const Duration(seconds: 8))) {
      bytes.addAll(chunk);
      if (bytes.length > 4 * 1024 * 1024) return null;
    }
    return utf8.decode(bytes);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
