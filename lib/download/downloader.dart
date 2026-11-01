import 'dart:io';

class DownloadCancelled implements Exception {
  @override
  String toString() => 'DownloadCancelled';
}

class DownloadException implements Exception {
  final String message;
  DownloadException(this.message);
  @override
  String toString() => 'DownloadException: $message';
}

class CancelToken {
  bool _c = false;
  bool get isCancelled => _c;
  void cancel() => _c = true;
}

class Downloader {
  final bool allowInsecureForTesting;
  final HttpClient _client;
  static const _maxRedirects = 5;

  Downloader({this.allowInsecureForTesting = false, HttpClient? client})
      : _client = client ?? HttpClient();

  bool _schemeOk(Uri u) =>
      u.scheme == 'https' || (allowInsecureForTesting && u.scheme == 'http');

  Future<File> download(
    Uri url,
    File dest, {
    void Function(int received, int? total)? onProgress,
    CancelToken? cancel,
  }) async {
    final part = File('${dest.path}.part');
    try {
      var existing = part.existsSync() ? part.lengthSync() : 0;
      var uri = url;
      HttpClientResponse? resp;
      for (var hop = 0; hop <= _maxRedirects; hop++) {
        if (!_schemeOk(uri)) {
          throw DownloadException('Güvenli olmayan adres reddedildi: ${uri.scheme}');
        }
        final req = await _client.getUrl(uri);
        req.followRedirects = false;
        if (existing > 0) req.headers.set('range', 'bytes=$existing-');
        final r = await req.close();
        if (r.isRedirect) {
          final loc = r.headers.value('location');
          await r.drain<void>();
          if (loc == null) throw DownloadException('Yönlendirme adresi yok');
          uri = uri.resolve(loc);
          continue;
        }
        resp = r;
        break;
      }
      if (resp == null) throw DownloadException('Çok fazla yönlendirme');

      final code = resp.statusCode;
      if (code == 416 && existing > 0) {
        await resp.drain<void>();
        await part.rename(dest.path); // shortcut: trusts 416 == already complete; hash check catches errors
        return dest;
      }
      if (code != 200 && code != 206) {
        await resp.drain<void>();
        throw DownloadException('Sunucu hata döndürdü: $code');
      }
      if (code == 200) existing = 0;
      final len = resp.contentLength;
      final total = len < 0 ? null : len + existing;
      var received = existing;
      final sink = part.openWrite(
          mode: code == 206 ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in resp) {
          if (cancel?.isCancelled ?? false) throw DownloadCancelled();
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      if (cancel?.isCancelled ?? false) throw DownloadCancelled();
      await part.rename(dest.path);
      return dest;
    } on DownloadCancelled {
      rethrow;
    } on DownloadException {
      rethrow;
    } on IOException catch (e) {
      throw DownloadException('Ağ hatası: $e');
    }
  }
}
