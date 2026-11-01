import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

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
  void Function()? _abort;
  bool get isCancelled => _c;
  void cancel() {
    _c = true;
    _abort?.call(); // unblock a stalled connection immediately
  }
}

final _rangeRe = RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$');
final _unsatisfiedRe = RegExp(r'^bytes \*/(\d+)$');

class Downloader {
  final bool allowInsecureForTesting;
  final Duration idleTimeout;
  final HttpClient _client;
  static const _maxRedirects = 5;

  Downloader({
    this.allowInsecureForTesting = false,
    HttpClient? client,
    this.idleTimeout = const Duration(seconds: 30),
  }) : _client = (client ?? HttpClient())
          ..connectionTimeout = const Duration(seconds: 30);

  /// Scheme rule: https always; http only for tests; never an https -> http downgrade.
  @visibleForTesting
  void checkUrl(Uri u, {Uri? from}) {
    final ok = u.scheme == 'https' || (allowInsecureForTesting && u.scheme == 'http');
    final downgrade = from != null && from.scheme == 'https' && u.scheme == 'http';
    if (!ok || downgrade) {
      throw DownloadException('Güvenli olmayan adres reddedildi');
    }
  }

  Future<File> download(
    Uri url,
    File dest, {
    void Function(int received, int? total)? onProgress,
    CancelToken? cancel,
    int? maxBytes,
  }) async {
    try {
      // Second attempt only after discarding an unusable .part.
      for (var attempt = 0; attempt < 2; attempt++) {
        final r = await _attempt(url, dest, onProgress, cancel, maxBytes);
        if (r != null) return r;
      }
      throw DownloadException('Sunucu yanıtı geçersiz');
    } on DownloadCancelled {
      rethrow;
    } on DownloadException {
      rethrow;
    } on TimeoutException {
      _cancelledOr(cancel, 'Sunucu yanıt vermiyor');
    } on FileSystemException {
      _cancelledOr(cancel, 'Disk hatası');
    } on IOException {
      _cancelledOr(cancel, 'Ağ hatası');
    }
  }

  Never _cancelledOr(CancelToken? c, String msg) =>
      throw (c?.isCancelled ?? false) ? DownloadCancelled() : DownloadException(msg);

  Future<void> _rm(File f) async {
    if (f.existsSync()) await f.delete();
  }

  /// Returns the finished file, or null when the .part was discarded and a retry is needed.
  Future<File?> _attempt(Uri url, File dest, void Function(int, int?)? onProgress,
      CancelToken? cancel, int? maxBytes) async {
    final part = File('${dest.path}.part');
    final existing = part.existsSync() ? part.lengthSync() : 0;
    var uri = url;
    HttpClientResponse? resp;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (cancel?.isCancelled ?? false) throw DownloadCancelled();
      checkUrl(uri);
      final req = await _client.getUrl(uri);
      req.followRedirects = false;
      cancel?._abort = () => req.abort();
      if (existing > 0) req.headers.set('range', 'bytes=$existing-');
      final r = await req.close().timeout(idleTimeout);
      if (r.isRedirect) {
        final loc = r.headers.value('location');
        await r.drain<void>().timeout(idleTimeout);
        if (loc == null) throw DownloadException('Yönlendirme adresi yok');
        final next = uri.resolve(loc);
        checkUrl(next, from: uri);
        uri = next;
        continue;
      }
      resp = r;
      break;
    }
    if (resp == null) throw DownloadException('Çok fazla yönlendirme');
    if (cancel?.isCancelled ?? false) {
      await resp.drain<void>().catchError((_) {});
      throw DownloadCancelled();
    }

    final code = resp.statusCode;
    var start = 0;
    int? total;
    if (code == 416) {
      final m = _unsatisfiedRe.firstMatch(resp.headers.value('content-range') ?? '');
      await resp.drain<void>().timeout(idleTimeout);
      if (existing > 0 && m != null && int.parse(m.group(1)!) == existing) {
        await part.rename(dest.path);
        return dest;
      }
      if (existing == 0) throw DownloadException('Sunucu hata kodu: 416');
      await _rm(part);
      return null;
    } else if (code == 206) {
      final m = _rangeRe.firstMatch(resp.headers.value('content-range') ?? '');
      if (existing == 0 || m == null || int.parse(m.group(1)!) != existing) {
        await resp.drain<void>().timeout(idleTimeout);
        await _rm(part);
        return null;
      }
      start = existing;
      total = m.group(3) == '*' ? null : int.parse(m.group(3)!);
    } else if (code == 200) {
      if (resp.contentLength >= 0) total = resp.contentLength;
    } else {
      await resp.drain<void>().timeout(idleTimeout);
      throw DownloadException('Sunucu hata kodu: $code');
    }
    if (maxBytes != null && (total ?? resp.contentLength) > maxBytes) {
      await resp.drain<void>().catchError((_) {});
      await _rm(part);
      throw DownloadException('Dosya çok büyük');
    }

    var received = start;
    var tooBig = false;
    final sink = part.openWrite(mode: start > 0 ? FileMode.append : FileMode.write);
    final done = Completer<void>();
    void fail(Object e, [StackTrace? st]) {
      if (!done.isCompleted) done.completeError(e, st);
    }

    // Manual subscription so cancel() wakes us even when the server is silent.
    cancel?._abort = () => fail(DownloadCancelled());
    final sub = resp.timeout(idleTimeout).listen((chunk) {
      if (cancel?.isCancelled ?? false) return fail(DownloadCancelled());
      if (maxBytes != null && received + chunk.length > maxBytes) {
        tooBig = true;
        if (!done.isCompleted) done.complete();
        return;
      }
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }, onError: fail, onDone: () {
      if (!done.isCompleted) done.complete();
    }, cancelOnError: true);
    try {
      await done.future;
    } finally {
      unawaited(sub.cancel()); // awaiting it can block on a silent peer
      await sink.close();
    }
    if (tooBig) {
      await _rm(part);
      throw DownloadException('Dosya çok büyük');
    }
    if (cancel?.isCancelled ?? false) throw DownloadCancelled();
    await part.rename(dest.path);
    return dest;
  }
}
