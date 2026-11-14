import 'dart:async';
import 'dart:io';

import 'package:data/src/downloads/download_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Local server: [body] bytes, honours Range unless [ignoreRange].
Future<HttpServer> _serve(
  List<int> body, {
  bool ignoreRange = false,
  int? failStatus,
  Duration chunkDelay = Duration.zero,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final res = req.response;
    if (failStatus != null) {
      res.statusCode = failStatus;
      await res.close();
      return;
    }
    var start = 0;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (!ignoreRange && range != null) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (start >= body.length) {
        res.statusCode = 416;
        await res.close();
        return;
      }
      res.statusCode = 206;
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${body.length - 1}/${body.length}',
      );
    }
    res.contentLength = body.length - start;
    for (var i = start; i < body.length; i += 1024) {
      res.add(body.sublist(i, (i + 1024).clamp(0, body.length)));
      if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
    }
    await res.close();
  });
  return server;
}

void main() {
  late Directory dir;
  final body = List<int>.generate(50 * 1024, (i) => i % 251);

  setUp(() async => dir = await Directory.systemTemp.createTemp('dl'));
  tearDown(() async => dir.delete(recursive: true));

  Uri urlOf(HttpServer s) => Uri.parse('http://127.0.0.1:${s.port}/movie.mp4');

  test('downloads the whole file', () async {
    final s = await _serve(body);
    addTearDown(s.close);
    final f = File('${dir.path}/a.mp4');
    final r = await DownloadEngine().run(
      url: urlOf(s),
      target: f,
      cancel: DownloadCancelToken(),
    );
    expect(r, DownloadStop.completed);
    expect(await f.readAsBytes(), body);
  });

  test('resumes a partial file with Range (206 append)', () async {
    final s = await _serve(body);
    addTearDown(s.close);
    final f = File('${dir.path}/b.mp4')..writeAsBytesSync(body.sublist(0, 20000));
    var restarted = false;
    final r = await DownloadEngine().run(
      url: urlOf(s),
      target: f,
      cancel: DownloadCancelToken(),
      onRestart: () => restarted = true,
    );
    expect(r, DownloadStop.completed);
    expect(restarted, isFalse);
    expect(await f.readAsBytes(), body);
  });

  test('server ignoring Range restarts from 0 and says so', () async {
    final s = await _serve(body, ignoreRange: true);
    addTearDown(s.close);
    final f = File('${dir.path}/c.mp4')..writeAsBytesSync(List.filled(9000, 7));
    var restarted = false;
    await DownloadEngine().run(
      url: urlOf(s),
      target: f,
      cancel: DownloadCancelToken(),
      onRestart: () => restarted = true,
    );
    expect(restarted, isTrue);
    expect(await f.readAsBytes(), body);
  });

  test('cancel stops the transfer and keeps the partial file', () async {
    final s = await _serve(body, chunkDelay: const Duration(milliseconds: 20));
    addTearDown(s.close);
    final f = File('${dir.path}/d.mp4');
    final token = DownloadCancelToken();
    var got = 0;
    final run = DownloadEngine().run(
      url: urlOf(s),
      target: f,
      cancel: token,
      progressEvery: Duration.zero,
      onProgress: (r, _) {
        got = r;
        if (r >= 5000) token.cancel();
      },
    );
    expect(await run, DownloadStop.cancelled);
    expect(got, lessThan(body.length));
    expect(await f.length(), lessThan(body.length));
  });

  test('HTTP 403 needs re-authorization; message has no URL', () async {
    final s = await _serve(body, failStatus: 403);
    addTearDown(s.close);
    try {
      await DownloadEngine().run(
        url: Uri.parse('http://127.0.0.1:${s.port}/movie/user/secret/1.mp4'),
        target: File('${dir.path}/e.mp4'),
        cancel: DownloadCancelToken(),
      );
      fail('expected an exception');
    } on DownloadTransferException catch (e) {
      expect(e.needsReauthorize, isTrue);
      expect(e.message, isNot(contains('secret')));
    }
  });

  test('a complete partial file (416) counts as done', () async {
    final s = await _serve(body);
    addTearDown(s.close);
    final f = File('${dir.path}/f.mp4')..writeAsBytesSync(body);
    final r = await DownloadEngine().run(
      url: urlOf(s),
      target: f,
      cancel: DownloadCancelToken(),
    );
    expect(r, DownloadStop.completed);
  });
}
