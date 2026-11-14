import 'dart:async';
import 'dart:math';

import '../diag/diag.dart';
import '../remote/api_exception.dart';
import '../remote/app_media_repository.dart';
import '../remote/media_models.dart';

typedef LeaseRenewCallback = Future<void> Function(PlaybackSessionDto lease);

/// Lease + heartbeat independent of widget lifecycle (brief §3 / Phase 3).
class LeaseManager {
  LeaseManager({
    required this.media,
    required this.deviceId,
    this.onRenew,
    this.onLeaseAtRisk,
    this.onLeaseLost,
    this.onDeviceConflict,
  });

  final AppMediaRepository media;
  String deviceId;
  final LeaseRenewCallback? onRenew;
  final void Function()? onLeaseAtRisk;
  final void Function()? onLeaseLost;

  /// Mid-play 409 DEVICE_LIMIT (another device took the lease), or
  /// [PLAYBACK_STOPPED_BY_ADMIN] from Control Panel stop.
  final void Function(String message, {String? code})? onDeviceConflict;

  /// Player stats sent with each heartbeat (Control Panel quality). Optional;
  /// a slow or failing provider never delays or fails the heartbeat.
  Future<Map<String, Object?>?> Function()? statsProvider;

  String? playbackId;
  String? streamId;
  String? contentType;
  String? profileId;
  String? containerExtension;
  int? maxHeight;
  String? tier;
  List<String>? codecs;
  /// What the customer sees (Control Panel activity, client 27 Oct).
  String? title;
  String? categoryName;
  int leaseTtlSec = 60;
  int? heartbeatIntervalSec;
  Timer? _timer;
  int consecutiveFails = 0;
  static const _failThreshold = 3;
  final _rand = Random();
  /// Lease released after [pausedHeartbeatLimit] of pause; Play starts a new
  /// one (same play URL unless the server address changed, Usman 13 Nov).
  bool _pausedLong = false;
  DateTime? _pausedAt;
  Timer? _pauseTimer;

  /// Heartbeats continue while paused, with `paused: true`, for up to 30
  /// minutes (Usman 13 Nov: the server has no heartbeat limit; a paused
  /// session keeps the subscription's single playback slot). Client 12 Nov:
  /// resume after a long pause from the exact point. Was 5 min with no flag.
  static const pausedHeartbeatLimit = Duration(minutes: 30);

  bool get isPaused => _pausedAt != null;
  bool _stopped = false;
  int _generation = 0;
  bool _beatInFlight = false;
  bool _renewInFlight = false;

  bool get isActive => playbackId != null && !_stopped;

  Future<PlaybackSessionDto> start({
    required String contentType,
    required String streamId,
    String? profileId,
    String? containerExtension,
    int? maxHeight,
    String? tier,
    List<String>? codecs,
    bool force = false,
    String? title,
    String? categoryName,
  }) async {
    final generation = ++_generation;
    _timer?.cancel();
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _pausedAt = null;
    _pausedLong = false;
    _stopped = false;
    this.contentType = contentType;
    this.streamId = streamId;
    this.profileId = profileId;
    this.containerExtension = containerExtension;
    this.maxHeight = maxHeight;
    this.tier = tier;
    this.codecs = codecs;
    this.title = title;
    this.categoryName = categoryName;
    final lease = await media.startPlayback(
      deviceId: deviceId,
      contentType: contentType,
      streamId: streamId,
      profileId: profileId,
      containerExtension: containerExtension,
      maxHeight: maxHeight,
      tier: tier,
      codecs: codecs,
      force: force,
      title: title,
      categoryName: categoryName,
    );
    if (_stopped || generation != _generation) {
      try {
        await media.stopPlayback(
          playbackId: lease.playbackId,
          deviceId: deviceId,
        );
      } catch (_) {}
      throw StateError('Playback lease cancelled');
    }
    playbackId = lease.playbackId;
    leaseTtlSec = lease.leaseTtlSec <= 0 ? 60 : lease.leaseTtlSec;
    heartbeatIntervalSec = lease.heartbeatIntervalSec;
    consecutiveFails = 0;
    _scheduleHeartbeat();
    return lease;
  }

  void _scheduleHeartbeat() {
    _timer?.cancel();
    if (playbackId == null || _pausedLong || _stopped) return;
    // Prefer server heartbeatIntervalSec when present; else ttl/3.
    final fromServer = heartbeatIntervalSec;
    final base = (fromServer != null && fromServer > 0)
        ? fromServer.clamp(15, 90)
        : (leaseTtlSec / 3).ceil().clamp(15, 45);
    final jitter = _rand.nextInt(5);
    final every = Duration(seconds: base + jitter);
    unawaited(_beat(nextSec: every.inSeconds));
    _timer = Timer.periodic(
      every,
      (_) => unawaited(_beat(nextSec: every.inSeconds)),
    );
  }

  Future<void> _beat({required int nextSec}) async {
    final id = playbackId;
    if (id == null || _stopped || _beatInFlight) return;
    final generation = _generation;
    _beatInFlight = true;
    try {
      final stats = await _readStats();
      if (_stopped || generation != _generation) return;
      final renewed = await media.heartbeatPlayback(
        playbackId: id,
        deviceId: deviceId,
        stats: stats,
        paused: isPaused,
      );
      if (_stopped || generation != _generation) return;
      consecutiveFails = 0;
      if (renewed.leaseTtlSec > 0) leaseTtlSec = renewed.leaseTtlSec;
      if (renewed.heartbeatIntervalSec != null) {
        heartbeatIntervalSec = renewed.heartbeatIntervalSec;
      }
      Diag.pb('heartbeat ok next=${nextSec}s id=$id');
    } on ApiException catch (e) {
      if (_stopped || generation != _generation) return;
      consecutiveFails++;
      Diag.pb(
        'heartbeat FAIL err=$e consecutive=$consecutiveFails status=${e.statusCode}',
      );
      Diag.err('heartbeat', e);
      final code = (e.code ?? '').toUpperCase();
      final msg = e.message.toLowerCase();
      if (e.statusCode == 409) {
        _timer?.cancel();
        // Admin stop must NOT auto-renew (unlike LEASE_EXPIRED).
        if (e.isPlaybackStoppedByAdmin ||
            code == 'PLAYBACK_STOPPED_BY_ADMIN') {
          onDeviceConflict?.call(
            e.message.isNotEmpty
                ? e.message
                : 'Playback stopped by the operator',
            code: 'PLAYBACK_STOPPED_BY_ADMIN',
          );
          return;
        }
        if (code == 'LEASE_EXPIRED' || msg.contains('expired')) {
          await _renew();
          return;
        }
        // DEVICE_LIMIT / "another device is currently active"
        onDeviceConflict?.call(e.message, code: e.code);
        return;
      }
      if (e.statusCode == 404 || e.statusCode == 410) {
        // Stop beating the dead id; a successful renew reschedules.
        _timer?.cancel();
        await _renew();
        return;
      }
      if (consecutiveFails >= _failThreshold) {
        onLeaseAtRisk?.call();
      }
    } catch (e, st) {
      if (_stopped || generation != _generation) return;
      consecutiveFails++;
      Diag.pb('heartbeat FAIL err=$e consecutive=$consecutiveFails');
      Diag.err('heartbeat', e, st);
      if (consecutiveFails >= _failThreshold) {
        onLeaseAtRisk?.call();
      }
    } finally {
      _beatInFlight = false;
    }
  }

  Future<Map<String, Object?>?> _readStats() async {
    final provider = statsProvider;
    if (provider == null) return null;
    try {
      return await provider().timeout(const Duration(seconds: 1));
    } catch (_) {
      return null;
    }
  }

  Future<void> _renew() async {
    if (_stopped || _renewInFlight) return;
    final generation = _generation;
    final ct = contentType;
    final sid = streamId;
    if (ct == null || sid == null) {
      onLeaseLost?.call();
      return;
    }
    _renewInFlight = true;
    Diag.pb('lease renew begin stream=$sid');
    try {
      final lease = await media.startPlayback(
        deviceId: deviceId,
        contentType: ct,
        streamId: sid,
        profileId: profileId,
        containerExtension: containerExtension,
        maxHeight: maxHeight,
        tier: tier,
        codecs: codecs,
        title: title,
        categoryName: categoryName,
      );
      if (_stopped || generation != _generation) {
        try {
          await media.stopPlayback(
            playbackId: lease.playbackId,
            deviceId: deviceId,
          );
        } catch (_) {}
        return;
      }
      playbackId = lease.playbackId;
      leaseTtlSec = lease.leaseTtlSec <= 0 ? 60 : lease.leaseTtlSec;
      heartbeatIntervalSec = lease.heartbeatIntervalSec;
      consecutiveFails = 0;
      Diag.pb('lease renew ok id=${lease.playbackId}');
      // urlContinuity guaranteed — do not reopen player unless URL changed.
      final sameUrl =
          lease.urlContinuity == 'guaranteed' || lease.urlContinuity == null;
      if (!sameUrl) {
        await onRenew?.call(lease);
      }
      _scheduleHeartbeat();
    } on ApiException catch (e) {
      if (_stopped || generation != _generation) return;
      _timer?.cancel();
      Diag.err('lease renew failed', e);
      if (e.statusCode == 409) {
        onDeviceConflict?.call(
          e.message,
          code: e.isPlaybackStoppedByAdmin
              ? 'PLAYBACK_STOPPED_BY_ADMIN'
              : e.code,
        );
      } else {
        onLeaseLost?.call();
      }
    } catch (e, st) {
      if (_stopped || generation != _generation) return;
      _timer?.cancel();
      Diag.err('lease renew failed', e, st);
      onLeaseLost?.call();
    } finally {
      _renewInFlight = false;
    }
  }

  /// Pause / play from the player (may be called many times per state).
  /// Paused: heartbeats go on with `paused: true` (sent at once), and after
  /// [stopAfter] the lease is released so the slot is free for other
  /// devices. Play: `paused: false` at once; after a release, a new lease.
  void onPausedChanged(
    bool paused, {
    Duration stopAfter = pausedHeartbeatLimit,
  }) {
    if (_stopped) return;
    if (paused) {
      if (_pausedAt != null || _pausedLong) return;
      _pausedAt = DateTime.now();
      _pauseTimer?.cancel();
      _pauseTimer = Timer(stopAfter, () => unawaited(_releaseAfterLongPause()));
      _beatNow();
      return;
    }
    if (_pausedAt == null && !_pausedLong) return;
    _pausedAt = null;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    if (_pausedLong) {
      _pausedLong = false;
      Diag.pb('play after a long pause: new lease');
      unawaited(_renew());
    } else {
      _beatNow();
    }
  }

  /// Heartbeat now (pause state changed), outside the regular interval.
  void _beatNow() {
    if (playbackId == null || _stopped || _pausedLong) return;
    unawaited(_beat(nextSec: 0));
  }

  /// Paused for [pausedHeartbeatLimit]: stop the server lease (frees the
  /// subscription's playback slot); [onPausedChanged] renews on Play.
  Future<void> _releaseAfterLongPause() async {
    if (_stopped || _pausedAt == null) return;
    _pausedLong = true;
    _timer?.cancel();
    final id = playbackId;
    playbackId = null;
    Diag.pb('lease released after a long pause');
    if (id == null) return;
    try {
      await media.stopPlayback(playbackId: id, deviceId: deviceId);
    } catch (_) {}
  }

  Future<void> stop() async {
    _generation++;
    _stopped = true;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _timer?.cancel();
    _timer = null;
    final id = playbackId;
    playbackId = null;
    if (id == null) return;
    try {
      await media.stopPlayback(playbackId: id, deviceId: deviceId);
      Diag.pb('cleanup stop=ok');
    } catch (e, st) {
      Diag.pb('cleanup stop=fail');
      Diag.err('stop lease', e, st);
    }
  }

  void dispose() {
    _generation++;
    _stopped = true;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _timer?.cancel();
    _timer = null;
  }
}
