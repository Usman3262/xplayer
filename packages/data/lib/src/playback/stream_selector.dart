import '../device/device_capabilities.dart';

enum StreamPlayDecision {
  playAsIs,
  preferLowerVariant,
  warnMayStutter,
  blockNeedsVariant,
}

class StreamSelection {
  const StreamSelection({
    required this.decision,
    required this.maxHeight,
    this.message,
  });

  final StreamPlayDecision decision;
  final int maxHeight;
  final String? message;
}

/// Chooses play policy from tier + known content metadata (brief §4.3 / §8).
/// Until ABR exists, this only caps / warns — it cannot fetch alternate ids.
class StreamSelector {
  const StreamSelector(this.caps);

  final DeviceCapabilities caps;

  StreamSelection select({
    int? contentHeight,
    String? codecHint,
    bool userForcePlay = false,
  }) {
    final cfg = TierMpvConfig.forTier(caps.tier);
    final h = contentHeight ?? 2160;
    final codec = (codecHint ?? 'hevc').toLowerCase();

    if (caps.tier == DeviceTier.low && h > 720 && !userForcePlay) {
      return StreamSelection(
        decision: StreamPlayDecision.warnMayStutter,
        maxHeight: cfg.maxHeight,
        message:
            'This title may stutter on this device. Prefer Data saver when available.',
      );
    }

    if (codec.contains('hevc') || codec.contains('h265')) {
      final hevc = caps.hevc;
      if (hevc != null && !hevc.supports(w: h >= 2160 ? 3840 : 1920, h: h)) {
        if (userForcePlay) {
          return StreamSelection(
            decision: StreamPlayDecision.playAsIs,
            maxHeight: cfg.maxHeight,
          );
        }
        return StreamSelection(
          decision: StreamPlayDecision.warnMayStutter,
          maxHeight: cfg.maxHeight,
          message:
              'Hardware may not decode this stream smoothly. Play anyway?',
        );
      }
    }

    if (h > cfg.maxHeight) {
      return StreamSelection(
        decision: StreamPlayDecision.preferLowerVariant,
        maxHeight: cfg.maxHeight,
        message: 'Capping expectation to ${cfg.maxHeight}p for this device.',
      );
    }

    return StreamSelection(
      decision: StreamPlayDecision.playAsIs,
      maxHeight: cfg.maxHeight,
    );
  }
}
