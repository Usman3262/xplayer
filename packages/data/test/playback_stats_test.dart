import 'package:data/src/playback/playback_stats.dart';
import 'package:test/test.dart';

void main() {
  var now = DateTime(2026, 10, 23, 12);
  DateTime clock() => now;
  void wait(int ms) => now = now.add(Duration(milliseconds: ms));

  setUp(() => now = DateTime(2026, 10, 23, 12));

  test('nothing attached: no stats', () async {
    expect(await PlaybackStatsCollector(clock: clock).snapshot(), isNull);
  });

  test('first load is not counted, later buffering is (count + time)', () async {
    final s = PlaybackStatsCollector(clock: clock)..attachNative();
    s.reportBuffering(true, playing: false); // opening
    wait(3000);
    s.reportBuffering(false, playing: true); // picture shows
    wait(10000);
    s.reportBuffering(true, playing: true); // rebuffer 1
    wait(1500);
    s.reportBuffering(false, playing: true);
    s.reportBuffering(true, playing: true); // rebuffer 2, still going
    wait(500);
    s.reportNativeSize(1920, 1080);
    final snap = await s.snapshot();
    expect(snap, {
      'engine': 'native',
      'bufferingCount': 2,
      'bufferingMs': 2000,
      'width': 1920,
      'height': 1080,
    });
  });

  test('repeated buffering=true counts once', () async {
    final s = PlaybackStatsCollector(clock: clock)..attachNative();
    s.reportBuffering(false, playing: true);
    s.reportBuffering(true, playing: true);
    s.reportBuffering(true, playing: true);
    wait(200);
    s.reportBuffering(false, playing: true);
    expect((await s.snapshot())!['bufferingCount'], 1);
  });

  test('counts survive a player switch, reset() starts over', () async {
    final s = PlaybackStatsCollector(clock: clock)..attachNative();
    s.reportBuffering(false, playing: true);
    s.reportBuffering(true, playing: true);
    wait(700);
    s.detach(); // engine switch closes the player mid-buffering
    s.attachNative();
    final kept = await s.snapshot();
    expect(kept!['bufferingCount'], 1);
    expect(kept['bufferingMs'], 700);
    expect(kept.containsKey('width'), isFalse, reason: 'size belongs to the old player');
    s.reset();
    final fresh = await s.snapshot();
    expect(fresh!['bufferingCount'], 0);
    expect(fresh['bufferingMs'], 0);
  });

  test('detach: no stats until a player is attached again', () async {
    final s = PlaybackStatsCollector(clock: clock)..attachNative();
    s.detach();
    expect(await s.snapshot(), isNull);
  });
}
