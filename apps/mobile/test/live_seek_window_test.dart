import 'package:player_mobile/features/player/live_seek_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses mpv cache state around the reader position', () {
    final w = LiveSeekWindow.parse(
        '{"seekable-ranges":[{"start":100.0,"end":190.0}],"reader-pts":185.0,'
        '"cache-duration":5.0,"eof-cached":false}');
    expect(w.behind, const Duration(seconds: 85));
    expect(w.ahead, const Duration(seconds: 5));
    expect(w.atEdge, isTrue);
    expect(w.seekable, isTrue);
  });

  test('after rewinding, forward is possible up to the live edge', () {
    final w = LiveSeekWindow.parse(
        '{"seekable-ranges":[{"start":0,"end":120}],"reader-pts":60}');
    expect(w.atEdge, isFalse);
    const pos = Duration(seconds: 500);
    expect(w.clampTarget(pos + const Duration(seconds: 10), pos),
        pos + const Duration(seconds: 10));
    expect(w.clampTarget(pos + const Duration(seconds: 90), pos),
        pos + const Duration(seconds: 60));
    expect(w.targetFor(1.0, pos), pos + const Duration(seconds: 60));
    expect(w.targetFor(0.0, pos), pos - const Duration(seconds: 60));
    expect(w.fraction, 0.5);
  });

  test('no reader pts: cache-duration is the part ahead', () {
    final w = LiveSeekWindow.parse(
        '{"seekable-ranges":[{"start":10,"end":70}],"cache-duration":4}');
    expect(w.ahead, const Duration(seconds: 4));
    expect(w.behind, const Duration(seconds: 56));
  });

  test('garbage or empty is not seekable', () {
    for (final s in ['?', '', '{}', '{"seekable-ranges":[]}', 'null']) {
      expect(LiveSeekWindow.parse(s).seekable, isFalse, reason: s);
    }
  });
}
