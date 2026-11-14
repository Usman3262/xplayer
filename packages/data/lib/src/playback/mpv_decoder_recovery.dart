/// Classifies native mpv / MediaCodec messages that indicate a recoverable
/// Android HW-decoder / surface lifecycle failure (Honor, QCOM, etc.).
enum AppMpvDecoderEvidence {
  none,
  nullSurface,
  codecReleased,
  hwDecodeFrame,
}

/// Returns a non-[AppMpvDecoderEvidence.none] value when [message] matches
/// known MediaCodec surface / Released-state failures.
AppMpvDecoderEvidence classifyAppMpvDecoderEvidence(String? message) {
  if (message == null) return AppMpvDecoderEvidence.none;
  final m = message.toLowerCase();
  if (m.trim().isEmpty) return AppMpvDecoderEvidence.none;

  if (m.contains('both surface and native_window are null') ||
      m.contains('surface and native_window are null')) {
    return AppMpvDecoderEvidence.nullSurface;
  }

  if (m.contains('released state') ||
      m.contains('failed to flush codec') ||
      m.contains('failed to dequeue output buffer') ||
      m.contains('status=-542398533') ||
      m.contains('flush() is valid only at executing')) {
    return AppMpvDecoderEvidence.codecReleased;
  }

  if (m.contains('error while decoding frame (hardware decoding)') ||
      (m.contains('h264_mediacodec') && m.contains('failed')) ||
      (m.contains('mediacodec') && m.contains('illegalstateexception'))) {
    return AppMpvDecoderEvidence.hwDecodeFrame;
  }

  return AppMpvDecoderEvidence.none;
}

/// True when evidence means the HW codec / surface path is unsafe to keep
/// reusing without a recreate (or software fallback).
bool appMpvDecoderNeedsFreshPlayer(AppMpvDecoderEvidence kind) =>
    kind == AppMpvDecoderEvidence.nullSurface ||
    kind == AppMpvDecoderEvidence.codecReleased ||
    kind == AppMpvDecoderEvidence.hwDecodeFrame;
