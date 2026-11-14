import 'dart:async';

/// Observe decoder failure while first-frame rendering is still pending.
/// Two consecutive software readings avoid rejecting a transient initial value.
/// A rendered frame alone does not prove that Surface hardware is active.
Future<void> waitForAppSurfaceFrame({
  required Future<void> firstFrame,
  required Future<String> Function() readHardware,
  required bool Function() isCurrent,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final result = Completer<void>();
  var frameRendered = false;
  var softwareSamples = 0;
  final watch = Stopwatch()..start();
  unawaited(firstFrame.then<void>((_) {
    frameRendered = true;
  }, onError: (Object error, StackTrace stack) {
    if (!result.isCompleted) result.completeError(error, stack);
  }));
  unawaited(() async {
    try {
      while (!result.isCompleted && watch.elapsed < timeout) {
        if (!isCurrent()) throw StateError('Playback cancelled');
        final hw = await readHardware().timeout(const Duration(milliseconds: 600),
            onTimeout: () => '?');
        if (result.isCompleted) return;
        if (!isCurrent()) throw StateError('Playback cancelled');
        if (hw == 'mediacodec' && frameRendered) {
          result.complete();
          return;
        }
        softwareSamples = hw == 'no' ? softwareSamples + 1 : 0;
        if (softwareSamples >= 2) throw const AppSurfaceDecoderFailure();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!result.isCompleted) throw TimeoutException('Surface video did not become ready');
    } catch (error, stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    }
  }());
  return result.future;
}

class AppSurfaceDecoderFailure implements Exception {
  const AppSurfaceDecoderFailure();
}
