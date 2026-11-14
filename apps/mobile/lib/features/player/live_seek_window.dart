import 'dart:convert';

/// The part of a live channel the player still holds in memory, measured
/// from the picture now on screen (client 21 Oct mobile #4: "the seek bar on
/// live for moving forward does not work"). Live IPTV streams have no
/// server-side DVR, so seeking is limited to this buffered window: back to
/// what was already received, forward again up to the live edge.
class LiveSeekWindow {
  const LiveSeekWindow({required this.behind, required this.ahead});

  /// Buffered time before the current picture.
  final Duration behind;

  /// Buffered time after the current picture (the live edge is at its end).
  final Duration ahead;

  static const none = LiveSeekWindow(behind: Duration.zero, ahead: Duration.zero);

  /// Less than this ahead of the picture counts as watching live.
  static const edgeSlack = Duration(seconds: 8);

  /// Smallest window worth showing seek controls for.
  static const minUseful = Duration(seconds: 10);

  Duration get total => behind + ahead;
  bool get seekable => total >= minUseful;
  bool get atEdge => ahead <= edgeSlack;

  /// Position of the picture on the bar (1.0 = live edge).
  double get fraction =>
      total.inMilliseconds <= 0 ? 1.0 : behind.inMilliseconds / total.inMilliseconds;

  /// Player position for bar fraction [f], given the current [position].
  Duration targetFor(double f, Duration position) {
    final start = position - behind;
    return start + Duration(milliseconds: (total.inMilliseconds * f.clamp(0.0, 1.0)).round());
  }

  /// Keep a relative seek inside the buffered window.
  Duration clampTarget(Duration target, Duration position) {
    final lo = position - behind;
    final hi = position + ahead;
    if (target < lo) return lo;
    if (target > hi) return hi;
    return target;
  }

  /// Parse mpv's `demuxer-cache-state` (JSON text). Uses the seekable range
  /// that holds the reader position; falls back to `cache-duration` ahead.
  static LiveSeekWindow parse(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return none;
      double? num_(Object? v) => v is num ? v.toDouble() : null;
      final reader = num_(j['reader-pts']);
      final ranges = (j['seekable-ranges'] is List)
          ? (j['seekable-ranges'] as List).whereType<Map>().toList()
          : const <Map>[];
      Map? range;
      for (final r in ranges) {
        final s = num_(r['start']), e = num_(r['end']);
        if (s == null || e == null) continue;
        if (reader != null && reader >= s && reader <= e) range = r;
      }
      range ??= ranges.isEmpty ? null : ranges.last;
      final start = num_(range?['start']);
      final end = num_(range?['end']);
      if (start == null || end == null || end <= start) return none;
      double ahead, behind;
      if (reader != null && reader >= start && reader <= end) {
        ahead = end - reader;
        behind = reader - start;
      } else {
        ahead = (num_(j['cache-duration']) ?? 0).clamp(0, end - start).toDouble();
        behind = (end - start) - ahead;
      }
      Duration d(double s) => Duration(milliseconds: (s * 1000).round());
      return LiveSeekWindow(behind: d(behind), ahead: d(ahead));
    } catch (_) {
      return none;
    }
  }
}
