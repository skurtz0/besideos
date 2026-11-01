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
    expect(dl().download(u('/a'), dest), throwsA(isA<DownloadException>()));
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
    expect(Downloader().download(u('/a'), dest),
        throwsA(isA<DownloadException>()));
  });

  test('follows redirect and rejects redirect to http', () async {
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
    expect(dl().download(u('/bad'), File('${dir.path}/b.iso')),
        throwsA(isA<DownloadException>()));
    // https-only mode: redirect target http is rejected at the first hop too.
    expect(Downloader().download(u('/go'), File('${dir.path}/c.iso')),
        throwsA(isA<DownloadException>()));
  });

  test('completes when .part already full and server says 416', () async {
    await serve((r) async {
      r.response.statusCode = 416;
      await r.response.close();
    });
    await File('${dest.path}.part').writeAsBytes(data);
    await dl().download(u('/a'), dest);
    expect(await dest.readAsBytes(), data);
  });
}
