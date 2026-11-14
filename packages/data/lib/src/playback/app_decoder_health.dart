/// Deliberately conservative: only sustained UHD HEVC software-decoding loss
/// with buffered data qualifies. A transient warning or hardware fallback alone
/// is not a failure. Samples must be taken while active, at normal speed.
class AppDecoderSample {
  const AppDecoderSample({
    required this.width,
    required this.height,
    required this.hardware,
    required this.codec,
    required this.droppedFrames,
    required this.cacheSeconds,
    required this.position,
  });
  final int width, height, droppedFrames;
  final String hardware, codec;
  final double cacheSeconds;
  final Duration position;
}

class AppDecoderHealth {
  int? _previousDrops;
  Duration? _previousTime;
  Duration? _previousPosition;
  int _badWindows = 0;

  void reset() {
    _previousDrops = null;
    _previousTime = null;
    _previousPosition = null;
    _badWindows = 0;
  }

  bool add(AppDecoderSample? sample, Duration elapsed) {
    if (sample == null ||
        (sample.width < 3840 && sample.height < 2160) ||
        sample.hardware != 'no' ||
        !sample.codec.toLowerCase().contains('hevc') ||
        sample.cacheSeconds < 3) {
      reset();
      return false;
    }
    final previousDrops = _previousDrops;
    final previousTime = _previousTime;
    final previousPosition = _previousPosition;
    _previousDrops = sample.droppedFrames;
    _previousTime = elapsed;
    _previousPosition = sample.position;
    if (previousDrops == null ||
        previousTime == null ||
        previousPosition == null)
      return false;
    final seconds = (elapsed - previousTime).inMilliseconds / 1000;
    final delta = sample.droppedFrames - previousDrops;
    final advance = (sample.position - previousPosition).inMilliseconds / 1000;
    // Reset on counter rollover/seek or a delayed/suspended polling loop.
    if (seconds < 2 ||
        seconds > 5 ||
        delta < 0 ||
        advance < 0 ||
        advance > seconds * 2) {
      _badWindows = 0;
      return false;
    }
    // Dropped frames alone may be normal for video above the display refresh
    // rate. Also require a clock running materially slower than real time.
    _badWindows = delta / seconds >= 6 && advance / seconds < 0.85
        ? _badWindows + 1
        : 0;
    return _badWindows >= 3;
  }
}
