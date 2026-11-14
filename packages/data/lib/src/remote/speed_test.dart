import 'dart:async';
import 'dart:io';

/// Internet download speed, shown as "87 Mbps" in the connection test
/// (client 20 Oct, 10-point list #10: "clearly display the measured speed").
///
/// Downloads test data over [streams] parallel connections for at most
/// [duration] and counts the bytes received. The provider's stream servers
/// are never used (they count against the customer's line).
class SpeedTestResult {
  const SpeedTestResult({required this.mbps, required this.bytes, required this.elapsed, required this.source});
  final double mbps;
  final int bytes;
  final Duration elapsed;
  final String source;

  /// What the speed is enough for (4K needs about 25 Mbps).
  SpeedClass get quality => mbps >= 25
      ? SpeedClass.uhd
      : mbps >= 8
          ? SpeedClass.hd
          : mbps >= 3
              ? SpeedClass.sd
              : SpeedClass.poor;
}

enum SpeedClass { uhd, hd, sd, poor }

/// Pure maths, unit-tested: bytes over time → megabits per second.
double megabitsPerSecond(int bytes, Duration elapsed) {
  final sec = elapsed.inMicroseconds / 1e6;
  if (sec <= 0) return 0;
  return bytes * 8 / sec / 1e6;
}

class SpeedTest {
  SpeedTest({List<Uri>? sources}) : _sources = sources ?? defaultSources;

  /// Cloudflare's public speed-test endpoint first, then our own APK
  /// download host (range request) if it is blocked.
  static final defaultSources = <Uri>[
    Uri.parse('https://speed.cloudflare.com/__down?bytes=50000000'),
    Uri.parse('https://download.sksj.online/tv.apk'),
  ];

  final List<Uri> _sources;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  /// [onProgress] gets the running Mbps about every 250 ms.
  Future<SpeedTestResult> run({
    Duration duration = const Duration(seconds: 8),
    int streams = 4,
    void Function(double mbps)? onProgress,
  }) async {
    Object? lastError;
    for (final src in _sources) {
      try {
        final r = await _measure(src, duration, streams, onProgress);
        if (r.bytes > 0) return r;
      } catch (e) {
        lastError = e;
      }
      if (_cancelled) break;
    }
    throw lastError ?? const SocketException('Speed test could not download');
  }

  Future<SpeedTestResult> _measure(
    Uri uri,
    Duration duration,
    int streams,
    void Function(double mbps)? onProgress,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    var bytes = 0;
    final sw = Stopwatch();
    final subs = <StreamSubscription<List<int>>>[];
    final done = Completer<void>();
    var open = 0;
    Timer? ticker;
    Timer? stop;

    void finish() {
      if (!done.isCompleted) done.complete();
    }

    try {
      for (var i = 0; i < streams; i++) {
        final req = await client.getUrl(uri);
        // Range keeps the fallback (a large APK) from being fully downloaded.
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-49999999');
        req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        final res = await req.close();
        if (res.statusCode >= 400) {
          await res.drain<void>();
          throw HttpException('HTTP ${res.statusCode}', uri: uri);
        }
        if (!sw.isRunning) {
          sw.start();
          stop = Timer(duration, finish);
          ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
            if (_cancelled) finish();
            onProgress?.call(megabitsPerSecond(bytes, sw.elapsed));
          });
        }
        open++;
        subs.add(res.listen(
          (chunk) => bytes += chunk.length,
          onError: (_) {
            open--;
            if (open <= 0) finish();
          },
          onDone: () {
            open--;
            if (open <= 0) finish();
          },
          cancelOnError: true,
        ));
      }
      await done.future;
      sw.stop();
      return SpeedTestResult(
        mbps: megabitsPerSecond(bytes, sw.elapsed),
        bytes: bytes,
        elapsed: sw.elapsed,
        source: uri.host,
      );
    } finally {
      ticker?.cancel();
      stop?.cancel();
      for (final s in subs) {
        unawaited(s.cancel());
      }
      client.close(force: true);
    }
  }
}
