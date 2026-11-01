import 'dart:io';
import 'package:flutter/foundation.dart';
import '../catalog/distro.dart';
import 'checksum.dart';
import 'downloader.dart';
import 'iso_verifier.dart';

enum DownloadPhase {
  idle,
  fetchingChecksum,
  downloading,
  verifying,
  verified,
  mismatch,
  failed,
  cancelled,
}

Directory defaultDownloadDir() {
  final env = Platform.environment;
  final home = Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
  return home == null || home.isEmpty
      ? Directory('${Directory.systemTemp.path}/BesideOS')
      : Directory('$home/Downloads/BesideOS');
}

class DownloadController extends ChangeNotifier {
  final Downloader downloader;
  final Directory targetDir;
  DownloadController({required this.downloader, required this.targetDir});

  DownloadPhase _phase = DownloadPhase.idle;
  int _received = 0;
  int? _total;
  String? _error;
  File? _file;
  CancelToken? _token;

  DownloadPhase get phase => _phase;
  int get received => _received;
  int? get total => _total;
  String? get error => _error;
  File? get file => _file;

  void _set(DownloadPhase p, {String? error}) {
    _phase = p;
    _error = error;
    notifyListeners();
  }

  void cancel() => _token?.cancel();

  Future<void> start(IsoAsset iso) async {
    _received = 0;
    _total = null;
    _file = null;
    final token = _token = CancelToken();
    // Re-check at the write site; never trust catalog validation alone.
    if (!isSafeFileName(iso.fileName)) {
      _set(DownloadPhase.failed, error: 'Geçersiz dosya adı.');
      return;
    }
    File? sumsFile;
    try {
      _set(DownloadPhase.fetchingChecksum);
      await targetDir.create(recursive: true);
      sumsFile = File('${targetDir.path}/${iso.fileName}.sha256sums.tmp');
      if (sumsFile.existsSync()) await sumsFile.delete();
      await downloader.download(Uri.parse(iso.checksumUrl), sumsFile, cancel: token);
      final sums = parseChecksums(await sumsFile.readAsString());
      final expected = expectedHashFor(sums, iso.fileName);
      if (expected == null) {
        _set(DownloadPhase.failed,
            error: 'Sağlama dosyasında ${iso.fileName} bulunamadı; doğrulanamadı.');
        return;
      }

      _set(DownloadPhase.downloading);
      final dest = File('${targetDir.path}/${iso.fileName}');
      await downloader.download(Uri.parse(iso.url), dest, cancel: token,
          onProgress: (r, t) {
        _received = r;
        _total = t;
        notifyListeners();
      });
      await _verify(dest, expected);
    } on DownloadCancelled {
      _set(DownloadPhase.cancelled);
    } on DownloadException catch (e) {
      _set(DownloadPhase.failed, error: 'İndirme başarısız: ${e.message}');
    } on FormatException catch (e) {
      _set(DownloadPhase.failed, error: 'Geçersiz adres: ${e.message}');
    } on FileSystemException catch (e) {
      _set(DownloadPhase.failed, error: 'Dosya yazılamadı: ${e.message}');
    } catch (e) {
      _set(DownloadPhase.failed, error: 'Beklenmeyen hata: $e');
    } finally {
      try {
        if (sumsFile != null && sumsFile.existsSync()) await sumsFile.delete();
      } catch (_) {}
    }
  }

  /// Windows "my own ISO" path: verify only.
  Future<void> startWithManualHash(File isoFile, String expectedSha256) async {
    _received = 0;
    _total = null;
    _file = null;
    try {
      await _verify(isoFile, expectedSha256);
    } catch (e) {
      _set(DownloadPhase.failed, error: 'Doğrulama başarısız: $e');
    }
  }

  Future<void> _verify(File f, String expected) async {
    _set(DownloadPhase.verifying);
    final r = await verifyIso(f, expected);
    switch (r.outcome) {
      case VerifyOutcome.ok:
        _file = f;
        _set(DownloadPhase.verified);
      case VerifyOutcome.mismatch:
        _set(DownloadPhase.mismatch,
            error: 'Sağlama toplamı eşleşmedi; dosya silindi.');
      case VerifyOutcome.unreadable:
        _set(DownloadPhase.failed,
            error: 'Dosya okunamadı veya sağlama değeri geçersiz.');
    }
  }
}
