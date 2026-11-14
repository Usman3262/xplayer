import '../diag/diag.dart';

/// Playback lifecycle states (brief §5.2).
enum PlaybackPhase {
  idle,
  resolvingLease,
  openingMedia,
  initialBuffering,
  playing,
  rebuffering,
  seeking,
  leaving,
  error,
  conflict,
}

/// Mutable session state for UI overlays (single owner).
class PlaybackUiState {
  const PlaybackUiState({
    this.phase = PlaybackPhase.idle,
    this.errorMessage,
    this.retryable = true,
    this.leaseAtRisk = false,
    this.warnStutter = false,
  });

  final PlaybackPhase phase;
  final String? errorMessage;
  final bool retryable;
  final bool leaseAtRisk;
  final bool warnStutter;

  bool get isLoading =>
      phase == PlaybackPhase.resolvingLease ||
      phase == PlaybackPhase.openingMedia ||
      phase == PlaybackPhase.initialBuffering;

  bool get showBufferChip => phase == PlaybackPhase.rebuffering;

  bool get showError =>
      phase == PlaybackPhase.error || phase == PlaybackPhase.conflict;

  PlaybackUiState copyWith({
    PlaybackPhase? phase,
    String? errorMessage,
    bool clearError = false,
    bool? retryable,
    bool? leaseAtRisk,
    bool? warnStutter,
  }) {
    return PlaybackUiState(
      phase: phase ?? this.phase,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      retryable: retryable ?? this.retryable,
      leaseAtRisk: leaseAtRisk ?? this.leaseAtRisk,
      warnStutter: warnStutter ?? this.warnStutter,
    );
  }

  void logTransition(String sid, int msSinceTap) {
    Diag.pb('s=$sid state ${phase.name} +$msSinceTap');
  }
}
