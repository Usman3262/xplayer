import 'dart:async';

import 'package:data/src/diag/diag.dart';
import 'package:data/src/playback/app_playback_failure.dart';
import 'package:data/src/remote/player_lifecycle_gate.dart';
import 'package:test/test.dart';

// Log lines below are representative of mpv/FFmpeg message formats; they are
// not captured from the client's device.
void main() {
  group('classifyMpvLog', () {
    test('HTTP status warnings from FFmpeg are classified by status', () {
      expect(
        classifyMpvLog('ffmpeg', 'warn', 'http: HTTP error 403 Forbidden')!.kind,
        AppFailureKind.authorization,
      );
      expect(
        classifyMpvLog('ffmpeg', 'warn', 'http: HTTP error 404 Not Found')!.httpStatus,
        404,
      );
      expect(
        classifyMpvLog('ffmpeg', 'error', 'http: HTTP error 458 Unknown')!.kind,
        AppFailureKind.connectionLimit,
      );
      for (final busy in [456, 460]) {
        expect(
          classifyMpvLog('ffmpeg', 'warn', 'http: HTTP error $busy <none>')!.kind,
          AppFailureKind.connectionLimit,
        );
      }
      final server = classifyMpvLog(
        'ffmpeg', 'error', 'Server returned 5XX Server Error reply')!;
      expect(server.kind, AppFailureKind.upstream);
      expect(server.httpStatus, 500);
    });

    test('load failures are fatal; tcp errors are network evidence', () {
      final open = classifyMpvLog('stream', 'error', 'Failed to open <src>.')!;
      expect(open.fatal, isTrue);
      expect(open.kind, AppFailureKind.openFailed);
      expect(
        classifyMpvLog('cplayer', 'error', 'Failed to recognize file format.')!.kind,
        AppFailureKind.container,
      );
      final tcp = classifyMpvLog(
        'ffmpeg', 'error', 'tcp: Connection to tcp://h:80 failed: Connection refused')!;
      expect(tcp.kind, AppFailureKind.network);
      expect(tcp.fatal, isFalse);
    });

    test('decoder errors are evidence but never fatal on their own', () {
      final vd = classifyMpvLog('vd', 'error', 'Could not open codec.')!;
      expect(vd.kind, AppFailureKind.decoder);
      expect(vd.fatal, isFalse);
    });

    test('ignores informational lines and plain warnings', () {
      expect(classifyMpvLog('cplayer', 'info', 'Failed to open x'), isNull);
      expect(classifyMpvLog('vo/gpu', 'warn', 'Some warning'), isNull);
      expect(classifyMpvLog('cplayer', 'error', 'unrelated'), isNull);
    });

    test('failure descriptions never contain source text', () {
      const secret = 'http://cf.example/movie/USER/PASS/1.mkv';
      final f = classifyMpvLog('stream', 'error', 'Failed to open $secret.')!;
      expect('$f', isNot(contains('USER')));
      expect(
        '${const AppPlaybackFailure(AppFailureKind.authorization, httpStatus: 403)}',
        'AppPlaybackFailure(authorization, http=403)',
      );
    });
  });

  test('HTTP 405 (wrong stream path) is not found, not retried', () {
    expect(kindForHttpStatus(405), AppFailureKind.notFound);
  });

  group('AppOpenFailureMonitor', () {
    test('provider 456 before a load failure means the line is busy', () async {
      final m = AppOpenFailureMonitor();
      m.add('ffmpeg', 'warn', 'http: HTTP error 456 <none>');
      m.add('stream', 'error', 'Failed to open <src>.');
      await expectLater(
        m.fatalBeforeFirstFrame,
        throwsA(isA<AppPlaybackFailure>()
            .having((e) => e.kind, 'kind', AppFailureKind.connectionLimit)
            .having((e) => e.httpStatus, 'http', 456)),
      );
      expect(appFailureMessage(AppFailureKind.connectionLimit),
          contains('refused this line'));
    });

    test('fatal load failure ends the open with the preceding HTTP status', () async {
      final m = AppOpenFailureMonitor();
      m.add('ffmpeg', 'warn', 'http: HTTP error 404 Not Found');
      m.add('stream', 'error', 'Failed to open <src>.');
      await expectLater(
        m.fatalBeforeFirstFrame,
        throwsA(isA<AppPlaybackFailure>()
            .having((e) => e.kind, 'kind', AppFailureKind.notFound)
            .having((e) => e.httpStatus, 'http', 404)),
      );
    });

    test('fatal load failure after a TCP error is a network failure', () async {
      final m = AppOpenFailureMonitor();
      m.add('ffmpeg', 'error', 'tcp: Connection to tcp://h:80 failed: Connection refused');
      m.add('stream', 'error', 'Failed to open <src>.');
      await expectLater(
        m.fatalBeforeFirstFrame,
        throwsA(isA<AppPlaybackFailure>()
            .having((e) => e.kind, 'kind', AppFailureKind.network)),
      );
      expect(m.lastKind, AppFailureKind.network);
    });

    test('decoder failure with no frame fails after the decoder grace',
        () async {
      final m = AppOpenFailureMonitor(
        decoderGrace: const Duration(milliseconds: 20),
      );
      m.add('vd', 'error', 'Could not open codec.');
      await expectLater(
        m.fatalBeforeFirstFrame,
        throwsA(isA<AppPlaybackFailure>()
            .having((e) => e.kind, 'kind', AppFailureKind.decoder)),
      );
    });

    test('a frame inside the decoder grace keeps playback going', () async {
      final m = AppOpenFailureMonitor(
        decoderGrace: const Duration(milliseconds: 20),
      );
      var failed = false;
      unawaited(m.fatalBeforeFirstFrame.catchError((_) => failed = true));
      m.add('vd', 'error', 'Could not open codec.');
      m.markFirstFrame();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(failed, isFalse);
    });

    test('HTTP status alone fails after the grace period', () async {
      final m = AppOpenFailureMonitor(
        httpGrace: const Duration(milliseconds: 20),
      );
      m.add('ffmpeg', 'warn', 'http: HTTP error 403 Forbidden');
      await expectLater(
        m.fatalBeforeFirstFrame,
        throwsA(isA<AppPlaybackFailure>()
            .having((e) => e.kind, 'kind', AppFailureKind.authorization)),
      );
    });

    test('first frame cancels pending failure and forwards later ones', () async {
      final forwarded = <AppMpvLogFailure>[];
      final m = AppOpenFailureMonitor(
        httpGrace: const Duration(milliseconds: 20),
        onFailureAfterStart: forwarded.add,
      );
      var failed = false;
      unawaited(m.fatalBeforeFirstFrame.catchError((_) => failed = true));
      m.add('ffmpeg', 'warn', 'http: HTTP error 503 Unavailable');
      m.markFirstFrame();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(failed, isFalse);
      m.add('stream', 'error', 'Failed to open <src>.');
      expect(forwarded.single.fatal, isTrue);
    });

    test('closed monitor ignores input and never reports an unhandled error', () async {
      final m = AppOpenFailureMonitor();
      m.close();
      m.add('stream', 'error', 'Failed to open <src>.');
      var done = false;
      unawaited(m.fatalBeforeFirstFrame.whenComplete(() => done = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(done, isFalse);
    });
  });

  group('AppRecoveryBudget', () {
    test('is bounded and only spends on recoverable kinds', () {
      final b = AppRecoveryBudget();
      expect(b.tryConsume(AppFailureKind.authorization), isFalse);
      expect(b.tryConsume(AppFailureKind.notFound), isFalse);
      expect(b.tryConsume(AppFailureKind.decoder), isFalse);
      expect(b.tryConsume(AppFailureKind.network), isTrue);
      expect(b.tryConsume(AppFailureKind.prematureEof), isTrue);
      expect(b.tryConsume(AppFailureKind.network), isFalse);
    });

    test('refills only after a full healthy window', () {
      var now = DateTime(2026);
      final b = AppRecoveryBudget(maxAttempts: 1, clock: () => now);
      expect(b.tryConsume(AppFailureKind.timeout), isTrue);
      b.notePlaying();
      now = now.add(const Duration(seconds: 50));
      b.noteInterrupted();
      b.notePlaying();
      now = now.add(const Duration(seconds: 50));
      b.notePlaying();
      expect(b.tryConsume(AppFailureKind.timeout), isFalse,
          reason: 'stall interrupted the healthy window');
      now = now.add(const Duration(seconds: 11));
      b.notePlaying();
      expect(b.tryConsume(AppFailureKind.timeout), isTrue);
    });
  });

  test('premature EOF: live always, VOD only well before known end', () {
    const min = Duration(minutes: 1);
    expect(isPrematureEof(position: min, duration: Duration.zero, live: true), isTrue);
    expect(isPrematureEof(position: min, duration: min * 90, live: false), isTrue);
    expect(
      isPrematureEof(position: min * 90 - const Duration(seconds: 5), duration: min * 90, live: false),
      isFalse,
    );
    expect(isPrematureEof(position: min, duration: Duration.zero, live: false), isFalse);
  });

  group('URL safety', () {
    test('describePlayUrl reports normalization without URL content', () {
      const plain = 'http://cf.example.xyz:8080/movie/USER/PASS/1.mkv';
      final d = describePlayUrl(plain);
      expect(d, 'scheme=http port=8080 query=no normalized=same');
      final changed = describePlayUrl('http://CF.example.xyz:80/m/us%2Der/1.mkv?t=1|2');
      expect(changed, contains('normalized=changed('));
      expect(changed, contains('defaultPort'));
      expect(changed, contains('escapes'));
      expect(changed, contains('case'));
      for (final leak in ['cf.', 'example', 'USER', 'PASS', 'us%2Der']) {
        expect(d + changed, isNot(contains(leak)));
      }
    });

    test('Diag.scrub removes URLs from logged errors', () {
      expect(
        Diag.scrub('Failed to open http://h:8080/live/USER/PASS/1.ts. retry'),
        'Failed to open <url> retry',
      );
      expect(Diag.scrub('no url here'), 'no url here');
    });
  });

  test('native player exceptions never reach the screen raw (client TV photo)', () {
    final raw = Exception('PlatformException(VideoError, Video player had error ju: Source error, null, null)');
    final m = userFacingPlaybackError(raw);
    expect(m.contains('PlatformException'), isFalse);
    expect(m, appFailureMessage(AppFailureKind.upstream));
    expect(userFacingPlaybackError(Exception('StateError(bad)')).contains('StateError'), isFalse);
  });
}
