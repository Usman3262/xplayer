import 'package:player_mobile/features/player/video_screen_mode.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client 21 Oct mobile #5: picture must reach the screen edges without
/// cutting the score/clock. Checked on the screen shapes we ship to.
void main() {
  const phone = Size(2400, 1080); // Infinix 20:9 landscape
  const iphone = Size(2796, 1290); // iPhone 14 Pro Max landscape
  const tablet = Size(2048, 1536); // 4:3 iPad
  const hd = Size(1920, 1080);
  const sd43 = Size(720, 540);
  const scope = Size(1920, 804); // 2.39:1 film

  test('Fit shows the whole picture, centred', () {
    final r = VideoScreenMode.fit.videoRect(phone, hd);
    expect(r.height, 1080);
    expect(r.width, closeTo(1920, 0.01));
    expect(r.left, closeTo(240, 0.01));
    final t = VideoScreenMode.fit.videoRect(tablet, hd);
    expect(t.width, 2048);
    expect(t.top, greaterThan(0));
    final s = VideoScreenMode.fit.videoRect(iphone, scope);
    expect(s.width, closeTo(2796, 0.5) );
  });

  test('Fill and Zoom cover the whole screen on every shape', () {
    for (final box in [phone, iphone, tablet]) {
      for (final v in [hd, sd43, scope]) {
        expect(VideoScreenMode.fill.videoRect(box, v), Offset.zero & box);
        expect(VideoScreenMode.zoom.videoRect(box, v), Offset.zero & box);
      }
    }
    // Fill and Zoom keep the proportions (cut the edges).
    expect(VideoScreenMode.fill.boxFit, BoxFit.cover);
    expect(VideoScreenMode.fill.extraScale, 1.0);
    expect(VideoScreenMode.zoom.boxFit, BoxFit.cover);
    expect(VideoScreenMode.zoom.extraScale, greaterThan(1.0));
    // Only Stretch changes the proportions.
    for (final m in VideoScreenMode.values) {
      if (m != VideoScreenMode.stretch) {
        expect(m.boxFit, isNot(BoxFit.fill), reason: '$m must not stretch');
      }
    }
  });

  test('Stretch (CEO 25 Oct, Strong 8K reference): whole picture on the whole screen, nothing cut', () {
    for (final box in [phone, iphone]) {
      for (final v in [hd, sd43]) {
        expect(VideoScreenMode.stretch.videoRect(box, v), Offset.zero & box);
      }
    }
    // BoxFit.fill maps the full frame onto the full screen: no part is cut.
    expect(VideoScreenMode.stretch.boxFit, BoxFit.fill);
    expect(VideoScreenMode.stretch.extraScale, 1.0);
    expect(VideoScreenMode.stretch.forcedAspect, isNull);
    // Live TV and Sports open in Stretch.
    expect(VideoScreenMode.liveDefault, VideoScreenMode.stretch);
  });

  test('forced ratios ignore the stream shape', () {
    final r = VideoScreenMode.ratio4x3.videoRect(phone, hd);
    expect(r.width / r.height, closeTo(4 / 3, 0.001));
    final w = VideoScreenMode.ratio16x9.videoRect(phone, sd43);
    expect(w.width / w.height, closeTo(16 / 9, 0.001));
  });

  test('button cycle and saved choice', () {
    expect(VideoScreenMode.stretch.next, VideoScreenMode.fit);
    expect(VideoScreenMode.fit.next, VideoScreenMode.fill);
    expect(VideoScreenMode.fill.next, VideoScreenMode.zoom);
    expect(VideoScreenMode.zoom.next, VideoScreenMode.stretch);
    expect(VideoScreenMode.ratio4x3.next, VideoScreenMode.stretch);
    expect(VideoScreenMode.fromName('stretch'), VideoScreenMode.stretch);
    expect(VideoScreenMode.fromName('fill'), VideoScreenMode.fill);
    expect(VideoScreenMode.fromName(null, legacyZoom: true), VideoScreenMode.zoom);
    expect(VideoScreenMode.fromName(null), VideoScreenMode.fit);
  });

  test('unknown video size falls back to the whole box', () {
    expect(VideoScreenMode.fit.videoRect(phone, Size.zero), Offset.zero & phone);
  });
}
