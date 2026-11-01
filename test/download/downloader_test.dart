import 'dart:async';
import 'dart:io';
import 'package:besideos_site/download/downloader.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Handler = FutureOr<void> Function(HttpRequest r);

void main() {
  late HttpServer server;
  late Directory dir;
  late File dest;
  final data = List<int>.generate(100000, (i) => i % 251);

  Uri u(String p) => Uri.parse('http://127.0.0.1:${server.port}$p');

  Future<void> serve(Handler h) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      await h(r);
    });
  }

  Future<void> full(HttpRequest r) async {
    r.response.contentLength = data.length;
    r.response.add(data);
    await r.response.close();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dl');
    dest = File('${dir.path}/a.iso');
  });
  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  Downloader dl() => Downloader(allowInsecureForTesting: true);

  test('downloads full file and reports progress', () async {
    await serve(full);
    var last = 0;
    int? tot;
    final f = await dl().download(u('/a'), dest, onProgress: (r, t) {
      last = r;
      tot = t;
    });
    expect(await f.readAsBytes(), data);
    expect(last, data.length);
    expect(tot, data.length);
    expect(File('${dest.path}.part').existsSync(), isFalse);
  });

  test('resumes from existing .part using Range (206)', () async {
    String? range;
    await serve((r) async {
      range = r.headers.value('range');
      r.response.statusCode = 206;
      r.response.headers.set('content-range', 'bytes 1000-${data.length - 1}/${data.length}');
      r.response.add(data.sublist(1000));
      await r.response.close();
    });
    await File('${dest.path}.part').writeAsBytes(data.sublist(0, 1000));
    await dl().download(u('/a'), dest);
    expect(range, 'bytes=1000-');
    expect(await dest.readAsBytes(), data);
  });

  test('server ignoring Range (200) restarts from zero without corrupt result',
      () async {
    await serve(full);
    await File('${dest.path}.part').writeAsBytes(List.filled(500, 7));
    await dl().download(u('/a'), dest);
    expect(await dest.readAsBytes(), data);
  });

  test('non-200 non-206 throws DownloadException', () async {
    await serve((r) async {
      r.response.statusCode = 404;
      await r.response.close();
    });
    await expectLater(dl().download(u('/a'), dest), throwsA(isA<DownloadException>()));
  });

  test('cancel keeps .part and throws DownloadCancelled', () async {
    await serve((r) async {
      r.response.contentLength = data.length * 100;
      for (var i = 0; i < 100; i++) {
        r.response.add(data);
        await r.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await r.response.close();
    });
    final c = CancelToken();
    final fut = dl().download(u('/a'), dest, cancel: c, onProgress: (r, t) {
      if (r > 0) c.cancel();
    });
    await expectLater(fut, throwsA(isA<DownloadCancelled>()));
    expect(File('${dest.path}.part').existsSync(), isTrue);
    expect(dest.existsSync(), isFalse);
  });

  test('rejects http url when allowInsecureForTesting is false', () async {
    await serve(full);
    await expectLater(Downloader().download(u('/a'), dest),
        throwsA(isA<DownloadException>()));
  });

  test('follows redirect; non-http(s) redirect target rejected', () async {
    await serve((r) async {
      if (r.uri.path == '/go') {
        r.response.redirect(Uri.parse('/a'), status: 302);
        await r.response.close();
      } else if (r.uri.path == '/bad') {
        r.response.statusCode = 302;
        r.response.headers.set('location', 'ftp://example.com/x');
        await r.response.close();
      } else {
        await full(r);
      }
    });
    await dl().download(u('/go'), dest);
    expect(await dest.readAsBytes(), data);
    await expectLater(dl().download(u('/bad'), File('${dir.path}/b.iso')),
        throwsA(isA<DownloadException>()));
  });

  test('checkUrl scheme rules', () async {
    await serve(full);
    final strict = Downloader();
    final lax = Downloader(allowInsecureForTesting: true);
    final s = Uri.parse('https://a.example/x'), h = Uri.parse('http://a.example/x');
    strict.checkUrl(s);
    strict.checkUrl(s, from: s);
    expect(() => strict.checkUrl(h), throwsA(isA<DownloadException>()));
    expect(() => strict.checkUrl(h, from: s), throwsA(isA<DownloadException>()));
    expect(() => lax.checkUrl(h, from: s), throwsA(isA<DownloadException>()));
    lax.checkUrl(h);
    lax.checkUrl(h, from: h);
    expect(() => lax.checkUrl(Uri.parse('ftp://x/y')), throwsA(isA<DownloadException>()));
  });

  test('redirect loop is capped: 5 followed, 6th fails', () async {
    var n = 0;
    await serve((r) async {
      n++;
      r.response.redirect(Uri.parse('/loop'), status: 302);
      await r.response.close();
    });
    await expectLater(dl().download(u('/loop'), dest), throwsA(isA<DownloadException>()));
    expect(n, 6);
  });

  test('completes when .part already full and server says 416', () async {
    await serve((r) async {
      r.response.statusCode = 416;
      r.response.headers.set('content-range', 'bytes */${data.length}');
      await r.response.close();
    });
    await File('${dest.path}.part').writeAsBytes(data);
    await dl().download(u('/a'), dest);
    expect(await dest.readAsBytes(), data);
  });

  test('416 with mismatching total discards .part and restarts', () async {
    await serve((r) async {
      if (r.headers.value('range') != null) {
        r.response.statusCode = 416;
        r.response.headers.set('content-range', 'bytes */5');
        await r.response.close();
      } else {
        await full(r);
      }
    });
    await File('${dest.path}.part').writeAsBytes(List.filled(300, 9));
    await dl().download(u('/a'), dest);
    expect(await dest.readAsBytes(), data);
  });

  test('416 without Content-Range is not trusted as complete', () async {
    await serve((r) async {
      if (r.headers.value('range') != null) {
        r.response.statusCode = 416;
        await r.response.close();
      } else {
        await full(r);
      }
    });
    await File('${dest.path}.part').writeAsBytes(data);
    await dl().download(u('/a'), dest);
    expect(await dest.readAsBytes(), data);
  });

  test('206 with wrong Content-Range start restarts from zero', () async {
    await serve((r) async {
      if (r.headers.value('range') != null) {
        r.response.statusCode = 206;
        r.response.headers.set('content-range', 'bytes 0-99/${data.length}');
        r.response.add(data.sublist(0, 100));
        await r.response.close();
      } else {
        await full(r);
      }
    });
    await File('${dest.path}.part').writeAsBytes(data.sublist(0, 1000));
    await dl().download(u('/a'), dest);
    expect(await dest.readAsBytes(), data);
  });

  test('206 without existing .part is a failure', () async {
    await serve((r) async {
      r.response.statusCode = 206;
      r.response.headers.set('content-range', 'bytes 0-9/10');
      r.response.add(List.filled(10, 1));
      await r.response.close();
    });
    await expectLater(dl().download(u('/a'), dest), throwsA(isA<DownloadException>()));
    expect(dest.existsSync(), isFalse);
  });

  test('0-byte body yields empty file', () async {
    await serve((r) async {
      r.response.contentLength = 0;
      await r.response.close();
    });
    await dl().download(u('/a'), dest);
    expect(await dest.length(), 0);
  });

  test('maxBytes: oversize Content-Length and oversize stream both fail, no files',
      () async {
    await serve((r) async {
      if (r.uri.path == '/chunked') {
        for (var i = 0; i < 10; i++) {
          r.response.add(List.filled(1000, 1));
        }
        await r.response.close();
      } else {
        await full(r);
      }
    });
    await expectLater(dl().download(u('/a'), dest, maxBytes: 1000),
        throwsA(isA<DownloadException>()));
    await expectLater(dl().download(u('/chunked'), dest, maxBytes: 1000),
        throwsA(isA<DownloadException>()));
    expect(dir.listSync(), isEmpty);
  });

  test('connection drop mid-body keeps .part and resume completes', () async {
    var first = true;
    await serve((r) async {
      final range = r.headers.value('range');
      if (range == null) {
        r.response.contentLength = data.length;
        final s = await r.response.detachSocket();
        s.add(data.sublist(0, 30000));
        await s.flush();
        s.destroy();
        first = false;
      } else {
        final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        r.response.statusCode = 206;
        r.response.headers.set('content-range', 'bytes $from-${data.length - 1}/${data.length}');
        r.response.add(data.sublist(from));
        await r.response.close();
      }
    });
    await expectLater(dl().download(u('/a'), dest), throwsA(isA<DownloadException>()));
    expect(first, isFalse);
    expect(File('${dest.path}.part').lengthSync(), greaterThan(0));
    await dl().download(u('/a'), dest);
    expect(await dest.readAsBytes(), data);
  });

  test('cancel before the body begins throws DownloadCancelled', () async {
    await serve((r) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await full(r);
    });
    final c = CancelToken();
    Future<void>.delayed(const Duration(milliseconds: 30), c.cancel);
    await expectLater(dl().download(u('/a'), dest, cancel: c),
        throwsA(isA<DownloadCancelled>()));
    expect(dest.existsSync(), isFalse);
  });

  test('stalled server fails within idle timeout', () async {
    await serve((r) async {
      r.response.contentLength = 1000;
      r.response.add(List.filled(10, 1));
      await r.response.flush();
    });
    final d = Downloader(
        allowInsecureForTesting: true,
        idleTimeout: const Duration(milliseconds: 200));
    await expectLater(d.download(u('/a'), dest), throwsA(isA<DownloadException>()))
        .timeout(const Duration(seconds: 5));
  });
}
