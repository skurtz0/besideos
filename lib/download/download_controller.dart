import 'dart:convert';
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
  /// Set only in the mismatch phase, so the UI can show both hashes.
  String? expectedHash, actualHash;

  bool _disposed = false;
  bool get _busy =>
      _phase == DownloadPhase.fetchingChecksum ||
      _phase == DownloadPhase.downloading ||
      _phase == DownloadPhase.verifying;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }

  void _set(DownloadPhase p, {String? error}) {
    if (_disposed) return;
    _phase = p;
    _error = error;
    notifyListeners();
  }

  void cancel() => _token?.cancel();

  Future<void> _rm(File f) async {
    try {
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  Future<void> start(IsoAsset iso) async {
    if (_busy) return;
    _received = 0;
    _total = null;
    _file = null;
    expectedHash = actualHash = null;
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
      // The checksum file never resumes: always fetched fresh from 0.
      await _rm(sumsFile);
      await _rm(File('${sumsFile.path}.part'));
      await downloader.download(Uri.parse(iso.checksumUrl), sumsFile,
          cancel: token, maxBytes: 1 << 20);
      final sums = parseChecksums(
          utf8.decode(await sumsFile.readAsBytes(), allowMalformed: true));
      final expected = expectedHashFor(sums, iso.fileName);
      if (expected == null) {
        _set(DownloadPhase.failed,
            error: 'Sağlama dosyasında bu dosya adı yok; doğrulanamadı. Katalog eskimiş olabilir; resmi sayfadan indir.');
        return;
      }

      _set(DownloadPhase.downloading);
      final dest = File('${targetDir.path}/${iso.fileName}');
      await downloader.download(Uri.parse(iso.url), dest, cancel: token,
          onProgress: (r, t) {
        if (_disposed) return;
        _received = r;
        _total = t;
        notifyListeners();
      });
      await _verify(dest, expected);
    } on DownloadCancelled {
      _set(DownloadPhase.cancelled);
    } on DownloadException catch (e) {
      _set(DownloadPhase.failed, error: 'İndirme başarısız: ${e.message}');
    } on FormatException {
      _set(DownloadPhase.failed, error: 'Geçersiz adres.');
    } on FileSystemException {
      _set(DownloadPhase.failed, error: 'Disk hatası: dosya yazılamadı.');
    } catch (_) {
      _set(DownloadPhase.failed, error: 'Beklenmeyen hata.');
    } finally {
      if (sumsFile != null) {
        await _rm(sumsFile);
        await _rm(File('${sumsFile.path}.part'));
      }
    }
  }

  /// Windows "my own ISO" path: verify only.
  Future<void> startWithManualHash(File isoFile, String expectedSha256) async {
    if (_busy) return;
    _received = 0;
    _total = null;
    _file = null;
    expectedHash = actualHash = null;
    try {
      await _verify(isoFile, expectedSha256, keep: true);
    } catch (_) {
      _set(DownloadPhase.failed, error: 'Doğrulama başarısız (disk hatası).');
    }
  }

  Future<void> _verify(File f, String expected, {bool keep = false}) async {
    _set(DownloadPhase.verifying);
    final r = await verifyIso(f, expected, deleteOnMismatch: !keep);
    switch (r.outcome) {
      case VerifyOutcome.ok:
        _file = f;
        _set(DownloadPhase.verified);
      case VerifyOutcome.mismatch:
        expectedHash = r.expected;
        actualHash = r.actual;
        _set(DownloadPhase.mismatch,
            error: keep
                ? 'Sağlama toplamı eşleşmedi. Dosya silinmedi; SHA-256 değerini kontrol et.'
                : 'Sağlama toplamı eşleşmedi; dosya silindi.');
      case VerifyOutcome.unreadable:
        _set(DownloadPhase.failed,
            error: 'Dosya okunamadı veya sağlama değeri geçersiz.');
    }
  }
}
