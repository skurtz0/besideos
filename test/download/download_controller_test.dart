import 'dart:async';
import 'dart:io';
import 'package:besideos_site/catalog/distro.dart';
import 'package:besideos_site/download/checksum.dart';
import 'package:besideos_site/download/download_controller.dart';
import 'package:besideos_site/download/downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  late int hits;
  final data = List<int>.generate(60000, (i) => i % 241);
  late String hash;
  String sums = '';
  Future<void> Function(HttpRequest)? isoHandler;

  IsoAsset iso([String name = 'a.iso']) => IsoAsset(
        arch: IsoArch.x86_64,
        url: 'http://127.0.0.1:${server.port}/iso',
        checksumUrl: 'http://127.0.0.1:${server.port}/sums',
        fileName: name,
      );

  DownloadController ctl([Directory? d]) => DownloadController(
      downloader: Downloader(allowInsecureForTesting: true),
      targetDir: d ?? dir);

  setUp(() async {
    hits = 0;
    isoHandler = null;
    dir = await Directory.systemTemp.createTemp('ctl');
    final tmp = File('${dir.path}/h')..writeAsBytesSync(data);
    hash = await sha256OfFile(tmp);
    tmp.deleteSync();
    sums = '$hash  a.iso\n';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      hits++;
      if (r.uri.path == '/sums') {
        r.response.write(sums);
        await r.response.close();
      } else if (isoHandler != null) {
        await isoHandler!(r);
      } else {
        r.response.add(data);
        await r.response.close();
      }
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  test('an ISO that is already on disk and matches its checksum is reused, not downloaded again', () async {
    File('${dir.path}/a.iso').writeAsBytesSync(data);
    final c = ctl();
    await c.start(iso());
    expect(c.phase, DownloadPhase.verified);
    expect(c.file!.path, '${dir.path}/a.iso');
    expect(hits, 1, reason: 'only the checksum file was fetched');
  });

  test('a wrong ISO already on disk is replaced by a fresh download', () async {
    File('${dir.path}/a.iso').writeAsBytesSync([1, 2, 3]);
    final c = ctl();
    await c.start(iso());
    expect(c.phase, DownloadPhase.verified);
    expect(hits, 2);
  });

  test('happy path ends verified with matching checksum file', () async {
    final c = ctl();
    await c.start(iso());
    expect(c.phase, DownloadPhase.verified);
    expect(c.file!.path, '${dir.path}/a.iso');
    expect(c.received, data.length);
  });

  test('checksum file missing the iso name ends failed (fail closed)', () async {
    sums = '$hash  other.iso\n';
    final c = ctl();
    await c.start(iso());
    expect(c.phase, DownloadPhase.failed);
    expect(c.error, contains('Katalog eskimiş olabilir; resmi sayfadan indir'));
    expect(File('${dir.path}/a.iso').existsSync(), isFalse);
  });

  test('hash mismatch ends mismatch and deletes file', () async {
    sums = '${'0' * 64}  a.iso\n';
    final c = ctl();
    await c.start(iso());
    expect(c.phase, DownloadPhase.mismatch);
    expect(File('${dir.path}/a.iso').existsSync(), isFalse);
  });

  test('network error ends failed with message', () async {
    final i = iso();
    await server.close(force: true);
    final c = ctl();
    await c.start(i);
    expect(c.phase, DownloadPhase.failed);
    expect(c.error, isNotEmpty);
  });

  test('cancel ends cancelled and keeps .part; restart after cancel resumes',
      () async {
    final gate = Completer<void>();
    isoHandler = (r) async {
      if (r.headers.value('range') != null) {
        final from = int.parse(
            RegExp(r'bytes=(\d+)-').firstMatch(r.headers.value('range')!)!.group(1)!);
        r.response.statusCode = 206;
        r.response.headers.set('content-range', 'bytes $from-${data.length - 1}/${data.length}');
        r.response.add(data.sublist(from));
        await r.response.close();
        return;
      }
      r.response.contentLength = data.length;
      r.response.add(data.sublist(0, 20000));
      await r.response.flush();
      await gate.future;
      try {
        r.response.add(data.sublist(20000));
        await r.response.close();
      } catch (_) {} // client may already be gone after cancel
    };
    final c = ctl();
    c.addListener(() {
      if (c.phase == DownloadPhase.downloading && c.received > 0 && !gate.isCompleted) {
        c.cancel();
        gate.complete();
      }
    });
    await c.start(iso());
    expect(c.phase, DownloadPhase.cancelled);
    expect(File('${dir.path}/a.iso.part').existsSync(), isTrue);
    final c2 = ctl();
    await c2.start(iso());
    expect(c2.phase, DownloadPhase.verified);
  });

  test('unwritable target dir ends failed without throwing', () async {
    final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
    final c = ctl(Directory('${blocker.path}/sub'));
    await c.start(iso());
    expect(c.phase, DownloadPhase.failed);
    expect(c.error, isNotEmpty);
  });

  test('startWithManualHash ok and mismatch', () async {
    final f = File('${dir.path}/m.iso')..writeAsBytesSync(data);
    final c = ctl();
    await c.startWithManualHash(f, hash);
    expect(c.phase, DownloadPhase.verified);
    await c.startWithManualHash(f, '1' * 64);
    expect(c.phase, DownloadPhase.mismatch);
    expect(f.existsSync(), isTrue); // user's own file is never deleted
    expect(c.error, contains('Dosya silinmedi'));
    await c.startWithManualHash(f, hash); // retry on the same file
    expect(c.phase, DownloadPhase.verified);
    await c.startWithManualHash(f, 'bad');
    expect(c.phase, DownloadPhase.failed);
  });

  test('unsafe iso fileName ends failed before any network call', () async {
    for (final n in ['C:x.iso', '.', 'a b', '../x', 'a/b']) {
      final c = ctl();
      await c.start(iso(n));
      expect(c.phase, DownloadPhase.failed, reason: n);
    }
    expect(hits, 0);
  });

  test('phases notified in order', () async {
    final c = ctl();
    final seen = <DownloadPhase>[];
    c.addListener(() {
      if (seen.isEmpty || seen.last != c.phase) seen.add(c.phase);
    });
    await c.start(iso());
    expect(seen, [
      DownloadPhase.fetchingChecksum,
      DownloadPhase.downloading,
      DownloadPhase.verifying,
      DownloadPhase.verified,
    ]);
  });

  test('oversize checksum file ends failed and leaves no files', () async {
    final c = ctl();
    final big = iso();
    await server.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      for (var i = 0; i < 20; i++) {
        r.response.add(List.filled(100 * 1024, 0x61));
      }
      await r.response.close();
    });
    await c.start(IsoAsset(
        arch: IsoArch.x86_64,
        url: big.url.replaceFirst(RegExp(r':\d+'), ':${server.port}'),
        checksumUrl: 'http://127.0.0.1:${server.port}/sums',
        fileName: 'a.iso'));
    expect(c.phase, DownloadPhase.failed);
    expect(dir.listSync(), isEmpty);
  });

  test('cancel during checksum fetch leaves no .tmp or .part', () async {
    await server.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      try {
        r.response.contentLength = 1000;
        r.response.add(List.filled(10, 0x61));
        await r.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        r.response.add(List.filled(10, 0x61));
        await r.response.flush();
      } catch (_) {}
    });
    final c = ctl();
    final f = c.start(iso());
    await Future<void>.delayed(const Duration(milliseconds: 30));
    c.cancel();
    await f;
    expect(c.phase, DownloadPhase.cancelled);
    expect(dir.listSync(), isEmpty);
  });

  test('second start during a run is a no-op; cancel still cancels first', () async {
    final gate = Completer<void>();
    isoHandler = (r) async {
      r.response.contentLength = data.length;
      r.response.add(data.sublist(0, 20000));
      await r.response.flush();
      await gate.future;
      try {
        await r.response.close();
      } catch (_) {}
    };
    final c = ctl();
    c.addListener(() {
      if (c.phase == DownloadPhase.downloading && c.received > 0) {
        c.start(iso()); // re-entrant call
        c.cancel();
        gate.complete();
      }
    });
    final before = hits;
    await c.start(iso());
    expect(c.phase, DownloadPhase.cancelled, reason: '${c.error}');
    expect(hits - before, 2); // one sums + one iso, no second run
  });

  test('stalled server ends failed within idle timeout', () async {
    isoHandler = (r) async {
      r.response.contentLength = data.length;
      r.response.add(data.sublist(0, 10));
      await r.response.flush();
    };
    final c = DownloadController(
        downloader: Downloader(
            allowInsecureForTesting: true,
            idleTimeout: const Duration(milliseconds: 200)),
        targetDir: dir);
    await c.start(iso()).timeout(const Duration(seconds: 5));
    expect(c.phase, DownloadPhase.failed);
    expect(c.error, contains('yanıt vermiyor'));
  });

  test('dispose mid-download does not throw', () async {
    final gate = Completer<void>();
    isoHandler = (r) async {
      r.response.contentLength = data.length;
      r.response.add(data.sublist(0, 20000));
      await r.response.flush();
      await gate.future;
      try {
        r.response.add(data.sublist(20000));
        await r.response.close();
      } catch (_) {}
    };
    final c = ctl();
    final f = c.start(iso());
    while (c.received == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    c.dispose();
    gate.complete();
    await f;
  });

  test('defaultDownloadDir ends in BesideOS', () {
    expect(defaultDownloadDir().path, endsWith('BesideOS'));
  });
}
