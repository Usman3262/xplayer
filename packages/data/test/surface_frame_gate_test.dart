import 'dart:async';
import 'package:test/test.dart';
import '../lib/src/playback/surface_frame_gate.dart';

void main() {
  test('software failure ends wait even when first frame never arrives', () async {
    await expectLater(waitForAppSurfaceFrame(
      firstFrame: Completer<void>().future,
      readHardware: () async => 'no', isCurrent: () => true,
    ), throwsA(isA<AppSurfaceDecoderFailure>()));
  });
  test('transient software reading does not reject working hardware', () async {
    var reads = 0;
    await waitForAppSurfaceFrame(firstFrame: Future<void>.value(),
      readHardware: () async => reads++ == 0 ? 'no' : 'mediacodec',
      isCurrent: () => true);
    expect(reads, 2);
  });
  test('hardware without a frame times out', () async {
    await expectLater(waitForAppSurfaceFrame(
      firstFrame: Completer<void>().future,
      readHardware: () async => 'mediacodec', isCurrent: () => true,
      timeout: const Duration(milliseconds: 100),
    ), throwsA(isA<TimeoutException>()));
  });
  test('unknown decoder plus frame is not treated as success', () async {
    await expectLater(waitForAppSurfaceFrame(
      firstFrame: Future<void>.value(), readHardware: () async => '?',
      isCurrent: () => true, timeout: const Duration(milliseconds: 100),
    ), throwsA(isA<TimeoutException>()));
  });
  test('cancelled session stops the gate', () async {
    await expectLater(waitForAppSurfaceFrame(
      firstFrame: Completer<void>().future,
      readHardware: () async => 'mediacodec', isCurrent: () => false,
    ), throwsA(isA<StateError>()));
  });
  test('first frame error propagates', () async {
    await expectLater(waitForAppSurfaceFrame(
      firstFrame: Future<void>.error(StateError('render failed')),
      readHardware: () async => 'mediacodec', isCurrent: () => true,
    ), throwsA(isA<StateError>()));
  });
}
