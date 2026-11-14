import 'dart:async';

import '../playback/app_playback_failure.dart';
import 'api_exception.dart';

/// Serializes media-player create/dispose across route instances.
///
/// Flutter's [State.dispose] cannot await async teardown. Without a shared
/// gate, backing out of one player and immediately opening another lets the
/// new [Player]/[VideoPlayerController] start while the previous dispose
/// is still in flight — overlapping audio and duplicate video outputs.
class PlayerLifecycleGate {
  PlayerLifecycleGate._();

  static Future<void> _tail = Future<void>.value();

  /// Runs [work] after every previously enqueued open/dispose has finished.
  static Future<T> enqueue<T>(Future<T> Function() work) {
    final previous = _tail;
    final result = () async {
      await previous;
      return work();
    }();
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Registers teardown that already started (e.g. from [State.dispose]) so
  /// later opens wait for it. It is not queued behind earlier work, so a hung
  /// open cannot delay releasing the previous player's provider connection.
  static void track(Future<void> teardown) {
    final previous = _tail;
    final done = teardown.then((_) {}, onError: (_) {});
    _tail = Future.wait([previous, done]).then((_) {}, onError: (_) {});
  }

  /// Waits for pending opens/teardown, bounded by [timeout]. Used before a
  /// new lease so a previous route's stop reaches the backend first.
  static Future<bool> settle(Duration timeout) async {
    try {
      await _tail.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }
}

/// Strips leading punctuation / BiDi artifacts (e.g. Arabic RTL showing
/// `.No access token…` when the English string ends with `.`).
String sanitizeUserFacingError(String message) {
  var t = message.trim();
  t = t.replaceFirst(
    RegExp(r'^[\.\,\;\:\u00B7\u2022\u2023\u25E6\u2024\uFE52\uFF0E]+\s*'),
    '',
  );
  return t.trim();
}

/// Maps raw player/API failures to safe on-screen copy. Never returns URLs,
/// file paths, or media_kit "Failed to open …" strings.
String userFacingPlaybackError(
  Object error, {
  String fallback = 'Playback failed. Please try again.',
}) {
  // Lease / API 429 during resolvingLease — same UX as stream connection limit.
  if (error is ApiException) {
    final code = (error.code ?? '').toUpperCase();
    // Backend sports entitlement (16 Oct): the package has no sports.
    if (code == 'SPORTS_NOT_ENTITLED') {
      return 'Sports is not included in your package.';
    }
    if (code == 'PLAYBACK_STOPPED_BY_ADMIN') {
      return 'Playback stopped by the operator';
    }
    if (code == 'POP_REQUIRED' ||
        code == 'POP_KEY_MISSING' ||
        code == 'POP_SIG_INVALID' ||
        code == 'POP_CHALLENGE_INVALID') {
      return 'This device could not be verified. Sign in again.';
    }
    if (code == 'DEVICE_REVOKED') {
      return 'This device was removed. Sign in again.';
    }
    if (error.statusCode == 429 ||
        code.contains('RATE') ||
        code.contains('CONNECTION_LIMIT') ||
        code == 'RESOLVING_LEASE_LIMIT') {
      return appFailureMessage(AppFailureKind.connectionLimit);
    }
    // Temporary refresh failure — stay signed in; ask to retry (C1).
    if (code == 'SESSION_REFRESH_RETRY' || error.statusCode == 503) {
      return 'Could not refresh your session right now. Please try again.';
    }

    // Empty / dead session — one clear line (avoids ".No access token…" in RTL).
    final msg = sanitizeUserFacingError(error.message);
    final lowerMsg = msg.toLowerCase();
    if (error.statusCode == 401 ||
        lowerMsg.contains('no access token') ||
        lowerMsg.contains('session expired')) {
      return 'Please sign in again.';
    }
    if (msg.isNotEmpty &&
        msg.length <= 100 &&
        !msg.contains('/') &&
        !msg.contains('\\')) {
      return msg;
    }
  }

  final cleaned = sanitizeUserFacingError(
    error.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
  );
  final lower = cleaned.toLowerCase();

  // Native player exceptions (client 20 Oct TV photo: "PlatformException(
  // VideoError, Video player had error ju: Source error, null, null)").
  // ExoPlayer "Source error" = the stream could not be read from the server.
  if (lower.contains('platformexception') ||
      lower.contains('videoerror') ||
      lower.contains('source error') ||
      lower.contains('exoplaybackexception') ||
      RegExp(r'\b[A-Z][A-Za-z]+(Exception|Error)\(').hasMatch(cleaned)) {
    if (lower.contains('source error') || lower.contains('http')) {
      return appFailureMessage(AppFailureKind.upstream);
    }
    return fallback;
  }

  if (lower.contains('429') ||
      lower.contains('resolvinglease') ||
      lower.contains('resolving lease') ||
      lower.contains('rate limit')) {
    return appFailureMessage(AppFailureKind.connectionLimit);
  }

  if (lower.contains('no access token') ||
      lower.contains('session expired')) {
    return 'Please sign in again.';
  }

  if (lower.contains('failed to open') ||
      lower.contains('http://') ||
      lower.contains('https://') ||
      lower.contains('cf.') ||
      RegExp(r'\.(mkv|mp4|m3u8|ts|avi|mov)(\?|$|/)', caseSensitive: false)
          .hasMatch(cleaned)) {
    return fallback;
  }
  if (cleaned.contains('405')) {
    return 'This title could not be played. Try again or pick another episode.';
  }
  if (cleaned.contains('522') ||
      cleaned.contains('460') ||
      lower.contains('timeout') ||
      lower.contains('sockettimeout')) {
    return fallback;
  }
  if (cleaned.length > 100 || cleaned.contains('/') || cleaned.contains('\\')) {
    return fallback;
  }
  if (cleaned.isEmpty) return fallback;
  return cleaned;
}
