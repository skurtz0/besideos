import 'dart:convert';
import 'dart:io';

import 'update_check.dart';

const _api = 'https://api.github.com/repos/skurtz0/besideos/releases/latest';

/// The newest released version if it is newer than this app, else null. Null on any problem: no banner, no error.
Future<String?> newerRelease({String current = kAppVersion}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.getUrl(Uri.parse(_api)).timeout(const Duration(seconds: 6));
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('User-Agent', 'BesideOS/$current');
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
    final tag = (jsonDecode(body) as Map)['tag_name'];
    return tag is String && isNewer(tag, current) ? tag.replaceFirst('v', '') : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
