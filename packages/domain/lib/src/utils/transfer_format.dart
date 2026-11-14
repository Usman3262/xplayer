/// File sizes and download estimates for people, not bytes (client 17 Oct:
/// "3.8 GB instead of 3,800 MB").
/// "129 GB" kept left-to-right inside Arabic text (an LTR isolate):
/// "GB 129 من GB 228" read backwards on the Arabic Downloads page
/// (Android phone, 18 Oct).
String formatBytes(int bytes) => '\u2066${_formatBytes(bytes)}\u2069';

String _formatBytes(int bytes) {
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;
  if (bytes >= gb) {
    final v = bytes / gb;
    return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} GB';
  }
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

/// Smoothed download speed from successive byte counts.
class TransferRate {
  int? _lastBytes;
  DateTime? _lastAt;
  double? _rate;

  /// Bytes per second, once at least one interval was measured.
  double? get bytesPerSecond => _rate;

  void update(int bytes, DateTime at) {
    final lastBytes = _lastBytes;
    final lastAt = _lastAt;
    if (lastBytes != null && lastAt != null) {
      final ms = at.difference(lastAt).inMilliseconds;
      if (ms >= 500 && bytes >= lastBytes) {
        final now = (bytes - lastBytes) * 1000 / ms;
        final prev = _rate;
        _rate = prev == null ? now : prev * 0.7 + now * 0.3;
      } else if (ms < 500) {
        return; // keep the older sample for a longer interval
      }
    }
    _lastBytes = bytes;
    _lastAt = at;
  }

  void reset() {
    _lastBytes = null;
    _lastAt = null;
    _rate = null;
  }

  /// Time left for [remaining] bytes, or null when the speed is unknown.
  Duration? remaining(int remaining) {
    final r = _rate;
    if (r == null || r <= 0 || remaining <= 0) return null;
    return Duration(seconds: (remaining / r).ceil());
  }
}

/// Minutes from a runtime label: "1h 46m", "46m", "01:46:50" or "106".
int? runtimeMinutes(String? label) {
  final t = label?.trim() ?? '';
  if (t.isEmpty) return null;
  final hm = RegExp(r'^(?:(\d+)\s*h)?\s*(?:(\d+)\s*m(?:in)?)?$').firstMatch(t);
  if (hm != null && (hm.group(1) != null || hm.group(2) != null)) {
    return int.parse(hm.group(1) ?? '0') * 60 + int.parse(hm.group(2) ?? '0');
  }
  final clock = RegExp(r'^(\d+):(\d{1,2})(?::(\d{1,2}))?$').firstMatch(t);
  if (clock != null) {
    if (clock.group(3) != null) {
      return int.parse(clock.group(1)!) * 60 + int.parse(clock.group(2)!);
    }
    return int.parse(clock.group(1)!); // mm:ss
  }
  return int.tryParse(t);
}

/// Display minutes from a provider `durationSec` field.
///
/// Catalog / get_vod_info often put **minutes** in `durationSec` (Xtream
/// `duration` is frequently already minutes). Dividing those by 60 yields
/// absurd runtimes ("2m" for a 2-hour film when the field is `120`).
///
/// Rules (catalog metadata only — not player progress clocks):
/// - `>= 600` → real seconds (10+ min) → minutes via ÷60
/// - `5..400` → already minutes (typical feature / episode length)
/// - `401..599` → prefer seconds (short-form ~7–10 min stored correctly)
/// - `1..4` → noise, hide
int? runtimeMinutesFromDurationSec(int? durationSec) {
  if (durationSec == null || durationSec <= 0) return null;
  if (durationSec >= 600) return (durationSec / 60).round();
  if (durationSec >= 5 && durationSec <= 400) return durationSec;
  if (durationSec >= 401) return (durationSec / 60).round();
  return null;
}

/// English runtime label for a minute count ("2h 0m", "45m"), or null.
String? formatRuntimeLabel(int? minutes) {
  if (minutes == null || minutes <= 0) return null;
  if (minutes >= 60) return '${minutes ~/ 60}h ${minutes % 60}m';
  return '${minutes}m';
}

/// Seconds from a provider duration value: number, "106", "1h 46m", "01:46:50".
int? parseDurationToSeconds(Object? raw) {
  if (raw == null) return null;
  if (raw is num) {
    final mins = runtimeMinutesFromDurationSec(raw.round());
    return mins == null ? null : mins * 60;
  }
  final t = '$raw'.trim();
  if (t.isEmpty) return null;
  final asNum = int.tryParse(t) ?? double.tryParse(t)?.round();
  if (asNum != null) {
    final mins = runtimeMinutesFromDurationSec(asNum);
    return mins == null ? null : mins * 60;
  }
  final mins = runtimeMinutes(t);
  return mins == null || mins <= 0 ? null : mins * 60;
}

/// Rating with one decimal ("7.498" -> "7.5"); null when not a number.
String? formatRating(Object? rating) {
  final v = rating is num ? rating.toDouble() : double.tryParse('$rating');
  if (v == null || v <= 0) return null;
  return v.toStringAsFixed(1);
}
