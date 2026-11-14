import 'dart:async';

/// Failure categories used for diagnostics and recovery decisions.
/// Derived from mpv/FFmpeg log text; the text itself is never stored or
/// logged because mpv can include the full authenticated source URL.
enum AppFailureKind {
  /// HTTP 401/403 from the media host.
  authorization,

  /// HTTP 404/410 from the media host.
  notFound,

  /// HTTP 429/458/509, or 456/460 from the Xtream media host: the provider
  /// refused the line. Seen while another device used the same
  /// max_connections=1 line; may also be a provider network/region lock.
  connectionLimit,

  /// HTTP 5xx from the media host.
  upstream,

  /// TCP / DNS / timeout errors before any HTTP status.
  network,

  /// mpv opened the source but could not detect a container.
  container,

  /// A decoder could not be opened or failed (mpv may still fall back).
  decoder,

  /// Video output could not be initialised.
  output,

  /// No first frame / no position progress within the allowed time.
  timeout,

  /// End of file long before the known duration (connection dropped).
  prematureEof,

  /// Source failed to open without a more specific reason.
  openFailed,
}

/// One classified mpv log line. Holds no source text.
class AppMpvLogFailure {
  const AppMpvLogFailure(this.kind, {this.httpStatus, this.fatal = false});

  final AppFailureKind kind;
  final int? httpStatus;

  /// True when mpv has given up on the current source (file load failed).
  final bool fatal;

  @override
  String toString() =>
      'kind=${kind.name}${httpStatus != null ? ' http=$httpStatus' : ''}'
      '${fatal ? ' fatal' : ''}';
}

final _httpStatus = RegExp(
  r'(?:HTTP error|Server returned)\s+(\d)(\d{2}|XX)\b',
  caseSensitive: false,
);

AppFailureKind kindForHttpStatus(int status) {
  if (status == 401 || status == 403) return AppFailureKind.authorization;
  // Xtream answers 405 for a stream path that does not exist (e.g. a series
  // id sent where an episode id belongs): another URL or engine cannot help.
  if (status == 404 || status == 405 || status == 410) {
    return AppFailureKind.notFound;
  }
  if (status == 429 || status == 456 || status == 458 ||
      status == 460 || status == 509) {
    return AppFailureKind.connectionLimit;
  }
  if (status >= 500) return AppFailureKind.upstream;
  return AppFailureKind.openFailed;
}

/// Classifies an mpv log event emitted through media_kit `Player.stream.log`.
/// Returns null for lines that are not failure evidence.
AppMpvLogFailure? classifyMpvLog(String prefix, String level, String text) {
  final lvl = level.toLowerCase();
  if (lvl != 'error' && lvl != 'fatal' && lvl != 'warn') return null;
  final p = prefix.toLowerCase();
  final t = text.toLowerCase();

  // FFmpeg's http protocol logs status failures at warning level.
  final http = _httpStatus.firstMatch(text);
  if (http != null) {
    final tail = http.group(2)!.toUpperCase();
    final status = int.parse(http.group(1)!) * 100 +
        (tail == 'XX' ? 0 : int.parse(tail));
    return AppMpvLogFailure(kindForHttpStatus(status), httpStatus: status);
  }
  if (lvl == 'warn') return null;

  if (t.contains('failed to recognize file format') ||
      t.contains('no video or audio streams selected')) {
    return const AppMpvLogFailure(AppFailureKind.container, fatal: true);
  }
  if (t.contains('failed to open')) {
    return const AppMpvLogFailure(AppFailureKind.openFailed, fatal: true);
  }
  if (t.startsWith('tcp:') ||
      t.contains('connection refused') ||
      t.contains('connection timed out') ||
      t.contains('operation timed out') ||
      t.contains('network is unreachable') ||
      t.contains('failed to resolve hostname') ||
      t.contains('connection reset')) {
    return const AppMpvLogFailure(AppFailureKind.network);
  }
  if (p == 'vd' ||
      p.startsWith('ffmpeg/video') ||
      t.contains('could not open codec') ||
      t.contains('failed to initialize a decoder')) {
    return const AppMpvLogFailure(AppFailureKind.decoder);
  }
  if (p.startsWith('vo')) {
    return const AppMpvLogFailure(AppFailureKind.output);
  }
  return null;
}

/// Typed open/playback failure. [toString] is safe to log and never contains
/// the source URL or raw mpv text.
class AppPlaybackFailure implements Exception {
  const AppPlaybackFailure(this.kind, {this.httpStatus});

  final AppFailureKind kind;
  final int? httpStatus;

  @override
  String toString() =>
      'AppPlaybackFailure(${kind.name}'
      '${httpStatus != null ? ', http=$httpStatus' : ''})';
}

/// Whether an automatic reopen of the SAME backend-issued URL is justified.
/// Authorization, missing content and decoder problems are not retried: a
/// reopen cannot fix them and would only repeat requests to the provider.
bool isRecoverableFailure(AppFailureKind kind) => switch (kind) {
  AppFailureKind.network ||
  AppFailureKind.upstream ||
  AppFailureKind.connectionLimit ||
  AppFailureKind.prematureEof ||
  AppFailureKind.timeout => true,
  _ => false,
};

/// Delay before an automatic reopen. Connection-limit errors wait longer so
/// the previous provider connection can close first.
Duration recoveryDelayFor(AppFailureKind kind) =>
    kind == AppFailureKind.connectionLimit
        ? const Duration(seconds: 4)
        : const Duration(milliseconds: 1500);

/// Bounded automatic-recovery budget for one playback session.
/// Refills only after [healthyWindow] of uninterrupted playback, so periodic
/// live-stream drops recover while a persistently failing source stops.
class AppRecoveryBudget {
  AppRecoveryBudget({this.maxAttempts = 2, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final DateTime Function() _clock;
  static const healthyWindow = Duration(seconds: 60);

  int _used = 0;
  DateTime? _healthySince;

  int get used => _used;

  bool tryConsume(AppFailureKind kind) {
    if (!isRecoverableFailure(kind) || _used >= maxAttempts) return false;
    _used++;
    _healthySince = null;
    return true;
  }

  /// Call periodically while playback is advancing normally.
  void notePlaying() {
    if (_used == 0) return;
    final now = _clock();
    _healthySince ??= now;
    if (now.difference(_healthySince!) >= healthyWindow) {
      _used = 0;
      _healthySince = null;
    }
  }

  /// Call when playback stalls or buffers, so the healthy window restarts.
  void noteInterrupted() => _healthySince = null;
}

/// Watches classified mpv log lines for one open attempt.
///
/// Before the first frame, a fatal load failure ends the open immediately;
/// an HTTP error status ends it after [httpGrace] (FFmpeg does not reconnect
/// on HTTP status errors unless asked to). After the first frame, failures
/// are forwarded to [onFailureAfterStart] for the screen to decide.
class AppOpenFailureMonitor {
  AppOpenFailureMonitor({
    this.httpGrace = const Duration(milliseconds: 2500),
    this.decoderGrace = const Duration(seconds: 8),
    this.onFailureAfterStart,
    this.onEvidence,
  });

  final Duration httpGrace;

  /// After mpv reports a decoder failure, how long to wait for its own
  /// fallback to show a frame before failing the open (the player then tries
  /// the Android engine instead of sitting through the full first-frame
  /// timeout).
  final Duration decoderGrace;
  final void Function(AppMpvLogFailure failure)? onFailureAfterStart;

  /// Every classified line (sanitized) for diagnostics.
  final void Function(AppMpvLogFailure failure)? onEvidence;

  late final Completer<void> _fatal = Completer<void>()..future.ignore();
  Timer? _graceTimer;
  Timer? _decoderTimer;
  bool _started = false;
  bool _closed = false;
  int? _lastHttpStatus;
  AppFailureKind? _lastKind;

  /// Completes with a [AppPlaybackFailure] error when the open has failed.
  /// Never completes normally.
  Future<void> get fatalBeforeFirstFrame => _fatal.future;

  int? get lastHttpStatus => _lastHttpStatus;
  AppFailureKind? get lastKind => _lastKind;

  void add(String prefix, String level, String text) {
    if (_closed) return;
    final failure = classifyMpvLog(prefix, level, text);
    if (failure == null) return;
    onEvidence?.call(failure);
    final previousKind = _lastKind;
    _lastKind = failure.kind;
    if (failure.httpStatus != null) _lastHttpStatus = failure.httpStatus;
    if (_started) {
      if (failure.fatal || failure.httpStatus != null) {
        onFailureAfterStart?.call(failure);
      }
      return;
    }
    if (failure.fatal) {
      // A generic "failed to open" is more useful with the HTTP status or
      // network error that preceded it.
      final status = _lastHttpStatus;
      var kind = failure.kind;
      if (kind == AppFailureKind.openFailed) {
        if (status != null) {
          kind = kindForHttpStatus(status);
        } else if (previousKind == AppFailureKind.network) {
          kind = AppFailureKind.network;
        }
      }
      _lastKind = kind;
      _fail(kind, status);
    } else if (failure.httpStatus != null) {
      _graceTimer ??= Timer(httpGrace, () {
        _fail(failure.kind, failure.httpStatus);
      });
    } else if (failure.kind == AppFailureKind.decoder) {
      _decoderTimer ??= Timer(decoderGrace, () {
        _fail(AppFailureKind.decoder, null);
      });
    }
  }

  void markFirstFrame() {
    _started = true;
    _cancelTimers();
  }

  void close() {
    _closed = true;
    _cancelTimers();
  }

  void _cancelTimers() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _decoderTimer?.cancel();
    _decoderTimer = null;
  }

  void _fail(AppFailureKind kind, int? status) {
    if (_started || _closed || _fatal.isCompleted) return;
    _cancelTimers();
    _fatal.completeError(AppPlaybackFailure(kind, httpStatus: status));
  }
}

/// True when the player stopped well before the known end of a VOD title.
bool isPrematureEof({
  required Duration position,
  required Duration duration,
  required bool live,
}) {
  if (live) return true;
  // Unknown duration: treat as a real end. Reopening at the true end of a
  // file would only reach EOF again and burn the recovery budget.
  if (duration <= Duration.zero) return false;
  return position < duration - const Duration(seconds: 30);
}

/// On-screen copy for a classified failure. Never includes source details.
String appFailureMessage(AppFailureKind kind) => switch (kind) {
  AppFailureKind.authorization =>
    'The stream server refused this title (access denied). Tap Retry.',
  AppFailureKind.notFound =>
    'This title is not available on the stream server right now.',
  AppFailureKind.connectionLimit =>
    'The stream server refused this line. It may be in use on another device, '
        'or blocked on this network. Close other devices and tap Retry.',
  AppFailureKind.upstream => 'The stream server had a problem. Tap Retry.',
  AppFailureKind.network =>
    'Could not reach the stream server. Check your connection and tap Retry.',
  AppFailureKind.container => 'This video format could not be opened.',
  AppFailureKind.timeout => 'Playback timed out. Tap Retry.',
  AppFailureKind.prematureEof =>
    'Playback stopped. Please check your connection and try again.',
  _ => 'Playback failed. Please try again.',
};

/// Safe description of what media_kit's URI normalization does to [url].
/// media_kit 1.2.6 passes network URLs through `Uri.parse(url).toString()`
/// before mpv opens them, which can change percent-escapes, default ports and
/// case. A byte-exact signed URL can break if this reports `changed`.
/// Never returns any part of the URL itself.
String describePlayUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return 'url=unparseable';
  final normalized = uri.toString();
  final changes = <String>[];
  if (normalized != url) {
    final lowerOriginal = url.toLowerCase();
    if (RegExp(r'^[a-z][a-z0-9+.-]*://[^/]*:(80|443)(/|$)')
        .hasMatch(lowerOriginal)) {
      changes.add('defaultPort');
    }
    if (url.contains('%') || RegExp(r'[ |^`{}<>"\\\[\]]').hasMatch(url)) {
      changes.add('escapes');
    }
    final schemeHost = RegExp(r'^[^:]+://[^/?#]*').firstMatch(url)?.group(0);
    if (schemeHost != null && schemeHost != schemeHost.toLowerCase()) {
      changes.add('case');
    }
    if (changes.isEmpty) changes.add('other');
  }
  // The port is not a secret and is the first thing to check when a host
  // serves plain HTTP on 8080 but the URL says https.
  final port = uri.hasPort ? '${uri.port}' : 'default';
  return 'scheme=${uri.scheme.isEmpty ? '?' : uri.scheme} port=$port '
      'query=${uri.hasQuery ? 'yes' : 'no'} '
      'normalized=${changes.isEmpty ? 'same' : 'changed(${changes.join('+')})'}';
}

/// Startup milestones for one open attempt, logged as one TTFF line.
class AppStartupTimeline {
  AppStartupTimeline() : _watch = Stopwatch()..start();

  final Stopwatch _watch;
  final _marks = <String, int>{};

  void mark(String name) => _marks.putIfAbsent(name, () => _watch.elapsedMilliseconds);

  int? operator [](String name) => _marks[name];

  String get line => _marks.entries.map((e) => '${e.key}=${e.value}ms').join(' ');
}
