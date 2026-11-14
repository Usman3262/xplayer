import 'package:data/src/diag/diag.dart';
import 'package:test/test.dart';

void main() {
  setUp(DiagTrail.clear);

  test('records playback lines in every build mode, scrubbed', () {
    Diag.pb('ERROR code=OPEN_FAILED kind=authorization http=403');
    DiagTrail.add('MPV', 'error stream: Failed to open http://h:80/movie/USER/PASS/1.mkv.');
    DiagTrail.add('MPV', 'error ffmpeg: open /live/USER/PASS/9.ts failed');
    final all = DiagTrail.lines.join('\n');
    expect(all, contains('OPEN_FAILED'));
    for (final leak in ['USER', 'PASS', 'h:80']) {
      expect(all, isNot(contains(leak)));
    }
  });

  test('API lines are not kept', () {
    Diag.api('POST <url> payload={"deviceId":"x"}');
    expect(DiagTrail.lines, isEmpty);
  });

  test('is bounded and finds the latest matching line', () {
    for (var i = 0; i < DiagTrail.maxLines + 20; i++) {
      Diag.pb('ERROR code=X$i');
    }
    expect(DiagTrail.lines.length, DiagTrail.maxLines);
    expect(DiagTrail.lastContaining('ERROR code='),
        'ERROR code=X${DiagTrail.maxLines + 19}');
  });
}
