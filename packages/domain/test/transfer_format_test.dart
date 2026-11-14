import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('large sizes in GB, smaller in MB', () {
    expect(formatBytes(4080218931), '\u20663.8 GB\u2069');
    expect(formatBytes(1024 * 1024 * 1024), '\u20661.0 GB\u2069');
    expect(formatBytes(734003200), '\u2066700 MB\u2069');
    expect(formatBytes(2048), '\u20662 KB\u2069');
  });

  test('time left from the measured speed', () {
    final r = TransferRate();
    final t0 = DateTime(2026, 10, 17, 12);
    r.update(0, t0);
    expect(r.remaining(1000), isNull);
    r.update(10 * 1024 * 1024, t0.add(const Duration(seconds: 10)));
    // 1 MiB/s: 600 MiB left = 600 s.
    expect(r.remaining(600 * 1024 * 1024), const Duration(seconds: 600));
    r.reset();
    expect(r.bytesPerSecond, isNull);
  });

  test('runtime labels to minutes', () {
    expect(runtimeMinutes('1h 46m'), 106);
    expect(runtimeMinutes('46m'), 46);
    expect(runtimeMinutes('01:46:50'), 106);
    expect(runtimeMinutes(''), isNull);
  });

  test('provider durationSec minutes vs seconds', () {
    // Xtream-style minutes wrongly stored as durationSec → was "2m" on details.
    expect(runtimeMinutesFromDurationSec(120), 120);
    expect(formatRuntimeLabel(120), '2h 0m');
    // Real seconds (90 min film).
    expect(runtimeMinutesFromDurationSec(5400), 90);
    expect(formatRuntimeLabel(90), '1h 30m');
    // Episode as seconds / as minutes.
    expect(runtimeMinutesFromDurationSec(2700), 45);
    expect(runtimeMinutesFromDurationSec(45), 45);
    // Short-form band (~7 min as seconds).
    expect(runtimeMinutesFromDurationSec(420), 7);
    expect(runtimeMinutesFromDurationSec(2), isNull);
    expect(parseDurationToSeconds(120), 7200);
    expect(parseDurationToSeconds('01:30:00'), 5400);
  });

  test('ratings with one decimal', () {
    expect(formatRating(7.498), '7.5');
    expect(formatRating('4.397'), '4.4');
    expect(formatRating(null), isNull);
    expect(formatRating(0), isNull);
  });
}
