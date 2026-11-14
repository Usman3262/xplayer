import 'dart:async';
import 'package:video_player/video_player.dart' as native_video;
import 'native_playback_view.dart';
import 'video_screen_mode.dart';
import 'live_seek_window.dart';
import 'playback_diagnostics_sheet.dart';

import 'package:flutter/foundation.dart';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/screen_awake.dart';
import '../../core/demo_mode.dart';
import '../../core/library_controller.dart';
import '../../core/orientation_policy.dart';
import '../../core/pip.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../core/program_reminders.dart';

/// Lease + playUrl via media_kit (embedded MKV audio/subtitle tracks).
/// Netflix-style overlay: volume lives in the top action row.

/// Default playback speed chosen in Settings → Playback.
const kDefaultPlaybackSpeedKey = 'app_default_playback_speed';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.id,
    this.startSec,
    this.kindHint,
    this.seriesId,
  });
  final String id;
  final int? startSec;

  /// When set (from `?kind=`), skips slow catalog scans and wrong contentType.
  final MediaKind? kindHint;

  /// Parent series id when [id] is an episode stream id.
  final String? seriesId;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  /// Keeps landscape across channel/episode [pushReplacement] (old route
  /// dispose must not reset orientation before the next player mounts).
  static int _activePlayerRoutes = 0;

  Player? _player;
  VideoController? _video;
  final List<StreamSubscription<dynamic>> _subs = [];

  bool showControls = true;
  /// Fit / Stretch / Fill screen / Zoom / 16:9 / 4:3 ([VideoScreenMode]).
  /// Movies / series always open in Fit (a change lasts for that title); Live TV
  /// and Sports always open in Stretch (CEO 25 Oct, the client's Strong 8K
  /// reference: whole picture, whole screen) and a change there lasts for
  /// that channel only.
  VideoScreenMode _screenMode = VideoScreenMode.fit;
  bool _screenModePicked = false;
  /// Mode name shown for a moment after the chrome button changes it.
  String? _screenModeFlash;
  Timer? _screenModeFlashTimer;

  /// Movies and series always open in Fit: the largest picture with its own
  /// proportions, nothing cropped or stretched (client 6 Nov: "the video size
  /// changed"; the last size picked was saved and reused for every title, so
  /// one tap on the size button made every film open cropped or stretched).
  /// The old saved choice is cleared once.
  Future<void> _loadVideoMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(VideoScreenMode.prefKey) ||
        prefs.containsKey(VideoScreenMode.legacyZoomPrefKey)) {
      await prefs.remove(VideoScreenMode.prefKey);
      await prefs.remove(VideoScreenMode.legacyZoomPrefKey);
    }
  }

  void _setScreenMode(VideoScreenMode mode, {bool flash = false}) {
    setState(() {
      _screenMode = mode;
      _screenModePicked = true;
      if (flash) _screenModeFlash = _screenModeLabel(_copy, mode);
    });
    if (flash) {
      _screenModeFlashTimer?.cancel();
      _screenModeFlashTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _screenModeFlash = null);
      });
    }
    // A size change lasts for this title only (movies / series open in Fit,
    // Live TV / Sports in their own default).
  }

  String _screenModeLabel(AppCopy copy, VideoScreenMode m) => switch (m) {
        VideoScreenMode.fit => copy.videoModeFit,
        VideoScreenMode.stretch => copy.videoModeStretchFull,
        VideoScreenMode.fill => copy.videoModeStretch,
        VideoScreenMode.zoom => copy.videoModeZoom,
        VideoScreenMode.ratio16x9 => '16:9',
        VideoScreenMode.ratio4x3 => '4:3',
      };

  String _screenModeHint(AppCopy copy, VideoScreenMode m) => switch (m) {
        VideoScreenMode.fit => copy.videoModeFitHint,
        VideoScreenMode.stretch => copy.videoModeStretchFullHint,
        VideoScreenMode.fill => copy.videoModeStretchHint,
        VideoScreenMode.zoom => copy.videoModeZoomHint,
        _ => copy.videoModeRatioHint,
      };

  IconData _screenModeIcon(VideoScreenMode m) => switch (m) {
        VideoScreenMode.fit => Icons.fit_screen_rounded,
        VideoScreenMode.stretch => Icons.aspect_ratio_rounded,
        VideoScreenMode.fill => Icons.settings_overscan_rounded,
        VideoScreenMode.zoom => Icons.crop_free_rounded,
        _ => Icons.aspect_ratio_rounded,
      };

  Future<void> _pickScreenMode() async {
    final copy = _copy;
    final picked = await showModalBottomSheet<VideoScreenMode>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in VideoScreenMode.values)
              ListTile(
                leading: Icon(_screenModeIcon(m), color: AppColors.cyan),
                title: Text(_screenModeLabel(copy, m)),
                subtitle: Text(_screenModeHint(copy, m)),
                trailing: m == _screenMode
                    ? Icon(Icons.check_rounded, color: AppColors.cyan)
                    : null,
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) _setScreenMode(picked);
  }
  bool _showVolumeSlider = false;
  Timer? _hideControls;
  /// Player lock (client 17 Oct, like Netflix): controls hidden, touches and
  /// swipes ignored; a tap shows the lock button, which unlocks.
  bool _locked = false;
  bool _lockHint = false;
  Timer? _lockHintTimer;
  /// Double-tap seek flash (±10s). Null when idle.
  int? _seekFlashSec;
  DateTime? _lastTapAt;
  Offset? _lastTapPos;
  bool _ready = false;
  native_video.VideoPlayerController? _nativePlayer;
  bool _failed = false;
  bool _decoderLimited = false;
  /// HD copy of a 4K movie this device cannot decode (client 20 Oct).
  MediaItem? _hdAlternative;
  bool _initializing = false;
  bool _userPaused = false;
  bool _seekInFlight = false;
  int _seekEpoch = 0;
  Completer<void>? _openCancelled;
  Timer? _stallWatchdog;
  DateTime _lastPlaybackAdvance = DateTime.now();
  bool _conflict = false;
  bool _forceTakeover = false;
  bool _playing = true;
  bool _buffering = false;

  /// Keys: `stream` | `local` | free-form CDN label from open.
  String _sourceLabelKey = 'stream';
  String? _error;
  double _speed = 1.0;
  double _volume = 1.0;
  double _volumeBeforeMute = 1.0;
  /// Task #143 #15: left-edge vertical drag dims video (no plugin).
  double _brightnessDim = 0.0;
  double? _gestureStartY;
  double? _gestureStartValue;
  bool _gestureVolume = false;
  String? _gestureHud;
  /// 0–1 fill for vertical volume/brightness HUD while dragging.
  double? _gestureHudLevel;
  String _title = AppBrand.name;
  MediaItem? _media;
  String? _playbackId;
  /// Active stream URL for iOS PiP handoff (C8).
  String? _deviceId;
  String _contentType = 'vod';
  Timer? _heartbeat;
  Timer? _hideVolume;
  Timer? _liveTicker;
  Timer? _progressTimer;
  int _openGen = 0;
  Future<void>? _disposeInFlight;
  bool _leaving = false;
  bool _allowPop = false;
  bool _cleanupQueued = false;
  bool _progressSaveInFlight = false;
  int _lastProgressPersistMs = 0;

  /// False until resume seek finishes (or is skipped) so we never overwrite
  /// continue-watching with a near-zero position from the cold start.
  bool _resumeSeekDone = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime? _liveOpenedAt;
  bool _userBehindLive = false;
  /// Buffered part of a live channel around the picture (mpv only); live
  /// seeking stays inside it (client 21 Oct mobile #4).
  LiveSeekWindow _liveWin = LiveSeekWindow.none;
  Timer? _liveWinTimer;
  bool _liveRawLogged = false;
  bool _liveWinLogged = false;
  /// How far the picture is behind live, from the viewer's own seeks. The
  /// buffer cannot tell: after a rewind the player stops reading until it
  /// catches up with its read-ahead limit, so the stream stays behind (seen
  /// on the emulator 21 Oct) and the newest part is not in memory.
  Duration _liveDelay = Duration.zero;
  /// Buffer as mpv reports it (before [_liveDelay] is applied).
  LiveSeekWindow _liveRaw = LiveSeekWindow.none;
  bool _liveExactSeek = false;
  /// A live seek is running; the window is re-measured after it lands.
  bool _liveSeeking = false;
  /// Where pending live seeks are heading, so quick repeated ±10 add up.
  Duration? _liveSeekTarget;
  AppMediaRepository? _mediaRepo;
  LibraryController? _library;
  PlaybackDiagSession? _diag;
  final PlaybackController _pb = PlaybackController();
  LeaseManager? _lease;

  /// Stream quality for the Control Panel, sent with each lease heartbeat.
  final PlaybackStatsCollector _stats = PlaybackStatsCollector();
  final ValueNotifier<Duration> _positionN = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationN = ValueNotifier(Duration.zero);
  int? _resumeStartSec;
  bool _surfaceMounted = false;
  DateTime? _lastPosUi;
  bool _forcePlayDespiteWarn = false;
  String? _pendingStutterWarn;

  List<AudioTrack> _audioTracks = const [];
  List<SubtitleTrack> _subtitleTracks = const [];
  List<VideoTrack> _videoTracks = const [];
  AudioTrack? _audioTrack;
  SubtitleTrack? _subtitleTrack;
  VideoTrack? _videoTrack;
  bool _trackPrefsApplied = false;

  /// Backend-issued URL of the current open. Kept only in memory for bounded
  /// recovery of the same session; never logged.
  String? _activePlayUrl;
  AppOpenFailureMonitor? _failureMonitor;
  AppFailureKind? _lastOpenFailureKind;
  AppFailureKind? _midPlayFailureKind;
  AppRecoveryBudget _recovery = AppRecoveryBudget();
  /// M2 host failover budget across mid-play re-inits (stop+start for new host).
  int _hostFailoverBudget = 2;
  bool _recovering = false;
  AppDecoderMode _decoderMode = AppDecoderMode.auto;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
  /// How close to the reported end counts as "caught up" after a DVR scrub.
  static const _liveEdgeTolerance = Duration(seconds: 20);

  /// Flat season playlist for prev/next (real catalog ids are numeric).
  List<Episode> _episodePlaylist = const [];
  int _episodeIndex = -1;

  /// Settings → Autoplay: the next episode starts a few seconds after the
  /// current one ends (the setting existed but nothing used it).
  static const _autoNextDelay = Duration(seconds: 5);
  Timer? _autoNext;
  bool _nativeEnded = false;
  String? _resolvedSeriesId;

  bool get _isEpisode =>
      _episodeIndex >= 0 && _episodePlaylist.isNotEmpty;

  bool get _isLivePlayback =>
      _contentType == 'live' ||
      _media?.isLive == true ||
      widget.kindHint == MediaKind.live ||
      widget.kindHint == MediaKind.sports;

  /// Live is at the edge unless the user scrubbed back in a seekable window.
  /// Do not infer "behind" from demux lag (position often trails duration).
  bool get _atLiveEdge {
    if (!_isLivePlayback) return false;
    if (_liveWin.seekable) return _liveWin.atEdge;
    if (!_userBehindLive) return true;
    if (_duration.inMilliseconds <= 0) return false;
    return _position >= _duration - _liveEdgeTolerance;
  }

  bool get _liveSeekable => _isLivePlayback && _liveWin.seekable;

  /// Refresh [_liveWin] once a second while live controls are on screen.
  Future<void> _pollLiveWindow() async {
    final player = _player;
    if (!_isLivePlayback || player == null || !_ready || _leaving) return;
    if (_liveSeeking) return;
    if (!showControls && !_userBehindLive) return;
    final raw = await appMpvGet(player, 'demuxer-cache-state');
    if (!_liveRawLogged) {
      _liveRawLogged = true;
      _diag?.pb('LIVE_CACHE_STATE ${raw.length > 300 ? raw.substring(0, 300) : raw}');
    }
    if (raw == '?' || !mounted || !identical(_player, player)) return;
    _liveRaw = LiveSeekWindow.parse(raw);
    // Bar: what is buffered behind the picture, then the distance to live.
    final w = LiveSeekWindow(behind: _liveRaw.behind, ahead: _liveDelay);
    if (!_liveWinLogged) {
      _liveWinLogged = true;
      _diag?.pb('LIVE_WINDOW behind=${w.behind.inSeconds}s '
          'buffered=${_liveRaw.ahead.inSeconds}s');
    }
    if (w.behind.inSeconds != _liveWin.behind.inSeconds ||
        w.ahead.inSeconds != _liveWin.ahead.inSeconds) {
      setState(() => _liveWin = w);
    }
  }

  void _syncLiveEdgeFromClock() {
    if (!_isLivePlayback || !_userBehindLive) return;
    // mpv's duration on a live stream is only an estimate; the buffered
    // window decides when the picture is back at live.
    if (_liveWin.seekable || _liveSeeking) return;
    if (_duration.inMilliseconds <= 0) return;
    if (_position >= _duration - _liveEdgeTolerance) {
      _diag?.pb('LIVE_EDGE by clock pos=${_position.inSeconds}s '
          'dur=${_duration.inSeconds}s');
      _userBehindLive = false;
    }
  }

  bool get _subsOn =>
      _subtitleTrack != null &&
      _subtitleTrack!.id != 'no' &&
      _subtitleTrack!.id != 'auto';

  static const _httpHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
  };

  @override
  void initState() {
    super.initState();
    unawaited(_loadVideoMode());
    unawaited(_loadDefaultSpeed());
    // The player keeps the screen on: no screensaver or sleep while
    // watching (client 17 Oct: screensaver after 10 min without remote
    // input; Android's native player does not hold the screen itself).
    // Counted keep-awake: survives route replacement (see ScreenAwake).
    // media_kit Video must use wakelock: false or it clears the lock on pause.
    ScreenAwake.acquire(this);
    WidgetsBinding.instance.addObserver(this);
    _liveWinTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => unawaited(_pollLiveWindow()));
    _mediaRepo = ref.read(mediaRepositoryProvider);
    _library = ref.read(libraryProvider.notifier);
    _pb.addListener(() {
      if (mounted) setState(() {});
    });
    unawaited(DeviceCapabilitiesStore.instance.ensureLoaded());
    _activePlayerRoutes++;
    // Opens in landscape (client 17 Oct #9); the rotate button switches to
    // portrait and back.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _enterImmersive();
    // Client 23 Oct #6: Android brought the status bar back (rotation,
    // dialogs, a swipe, coming back to the app) and it stayed. Hide it again.
    SystemChrome.setSystemUIChangeCallback((visible) async {
      if (visible) _reHideSystemBars();
    });
    _armControlsHide();
    AppPip.inPip.addListener(_onPipChanged);
    // iPhone PiP window buttons drive our player.
    AppPip.onIosSetPlaying = _onIosPipSetPlaying;
    AppPip.onIosSkip =
        (ms) => unawaited(_seekBy(Duration(milliseconds: ms)));
    // Background sound (client 23 Oct #7): Android silenced the player in the
    // background without a foreground media service. Started here (Android 12+
    // does not allow starting it from the background), stopped on close.
    _playbackService(true);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enterImmersive();
    if (state == AppLifecycleState.resumed) {
      ScreenAwake.ensure();
    }
    // Background playback (client 17 Oct): leaving the app or locking the
    // phone keeps the sound playing. On iPhone the picture is switched off
    // while in the background: iOS closes the hardware video decoder there
    // ("invalid session -12903") and mpv then fell back to software decoding,
    // which froze 1080p / 4K on return. The picture comes back on return.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _inBackground = true;
      unawaited(_persistProgress(force: true));
      final player = _player;
      // iPhone PiP (client 12 Nov): a playing film keeps its picture for
      // the PiP window (software frames, AppPip.swift). When PiP did
      // not start (switched off in iOS Settings, paused, …) the picture
      // goes off as before.
      if (_nativePlayer == null &&
          player != null &&
          !_videoOffInBackground &&
          !_pictureKeptForPip &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          AppPip.iosArmed &&
          player.state.playing) {
        _pictureKeptForPip = true;
        _iosBackgroundAudio(player, true);
        _diag?.pb('LIFECYCLE background; picture kept for PiP');
        Future<void>.delayed(const Duration(milliseconds: 2500), () {
          if (!mounted || !_inBackground || AppPip.inPip.value) return;
          if (!identical(_player, player)) return;
          _diag?.pb('PIP not shown; picture off in background');
          _pictureOffForBackground(player);
        });
      } else if (_nativePlayer == null &&
          player != null &&
          !_videoOffInBackground &&
          !_pictureKeptForPip) {
        _pictureOffForBackground(player);
      } else if (!_videoOffInBackground) {
        _diag?.pb('LIFECYCLE background; playback continues');
      }
    } else if (state == AppLifecycleState.resumed) {
      _inBackground = false;
      final player = _player;
      if (_videoOffInBackground && player != null) {
        _videoOffInBackground = false;
        _pictureKeptForPip = false;
        _pictureSwitchedAt = DateTime.now();
        _iosBackgroundAudio(player, false);
        unawaited(_restorePictureAfterBackground(player));
      } else if (_pictureKeptForPip && player != null) {
        _pictureKeptForPip = false;
        _iosBackgroundAudio(player, false);
        // The picture stayed on; only the decoder is checked (iOS may have
        // closed the hardware decoder while away).
        unawaited(_restorePictureAfterBackground(player, setVideo: false));
      }
      // A stream that really stopped while away is reopened now, not in the
      // background (iPhone, 12 Nov log: a reopen there waited until return).
      final deferred = _recoverOnResume;
      _recoverOnResume = null;
      if (deferred != null && player != null && mounted) {
        _diag?.pb('RECOVERY on return kind=${deferred.name}');
        unawaited(_recoverOrFail(player, deferred, 'afterBackground'));
      }
      if (mounted) setState(() {});
    }
  }

  bool _videoOffInBackground = false;

  /// iPhone: the picture stayed on in the background for the PiP window.
  bool _pictureKeptForPip = false;

  /// Picture off while away; the sound continues.
  /// Android too (17 Oct phone test): the video surface is destroyed in the
  /// background, the hardware decoder lost it and the player froze on one
  /// frame with no sound, and Play did not recover it.
  void _pictureOffForBackground(Player player) {
    if (_videoOffInBackground) return;
    _videoOffInBackground = true;
    _pictureSwitchedAt = DateTime.now();
    unawaited(appMpvSet(player, 'vid', 'no'));
    if (!_pictureKeptForPip) _iosBackgroundAudio(player, true);
    _pictureKeptForPip = false;
    _diag?.pb('LIFECYCLE background; sound continues, picture off');
  }

  /// iPhone (client 24 Oct, log of a real test): when the stream buffered in
  /// the background, mpv paused the sound, iOS saw no audio and suspended
  /// the app within 2 s, so it never came back. While away the audio device
  /// keeps running (silence) through a buffer instead of pausing, so iOS
  /// keeps the app alive.
  void _iosBackgroundAudio(Player player, bool away) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    if (away) {
      unawaited(appMpvSet(player, 'audio-stream-silence', 'yes'));
      unawaited(appMpvSet(player, 'cache-pause', 'no'));
    } else {
      unawaited(appMpvSet(player, 'cache-pause', 'yes'));
      unawaited(appMpvSet(player, 'audio-stream-silence', 'no'));
    }
  }

  /// App is in the background (paused / hidden).
  bool _inBackground = false;

  /// When the picture was last switched off (leaving) or on (returning).
  /// mpv can report "end of file" right after the switch although the
  /// stream is fine (iPhone, 12 Nov log), so that EOF is checked first.
  DateTime? _pictureSwitchedAt;

  /// iPhone: a real stream stop seen in the background; recovery runs when
  /// the app returns.
  AppFailureKind? _recoverOnResume;

  /// Position kept for a host failover restart (12 Nov log: the restart
  /// began at the first resume point, 13 s, instead of the latest, 32 s).
  int? _failoverResumeSec;

  bool get _nearPictureSwitch {
    final at = _pictureSwitchedAt;
    return at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 5);
  }

  /// iPhone EOF while away or right after the picture switch: confirm the
  /// stream really stopped before reopening it, and never reopen in the
  /// background (it only completed after the app returned).
  Future<void> _checkEofNearPictureSwitch(
    Player player,
    AppFailureKind kind,
  ) async {
    final before = player.state.position;
    bool current() =>
        mounted && !_leaving && !_failed && identical(_player, player);
    bool advanced(Duration from) =>
        player.state.position - from >= const Duration(milliseconds: 800);
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    if (!current()) return;
    if (advanced(before)) {
      _diag?.pb('EOF ignored after picture switch; playback continues '
          'pos=${player.state.position.inSeconds}s');
      return;
    }
    // Paused by the viewer: a still clock is expected. Never start it here;
    // Play after returning runs the normal stall / end checks.
    if (_userPaused) {
      _diag?.pb('EOF after picture switch while paused; nothing to do');
      return;
    }
    if (!_inBackground) {
      unawaited(_recoverOrFail(player, kind, 'eof'));
      return;
    }
    // Still away: restart reading at the same point on the same player
    // (no new open), keeping the picture off.
    final pos = player.state.position;
    _diag?.pb('EOF in background; resume reading pos=${pos.inSeconds}s');
    try {
      await player.seek(pos);
      await player.play();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 3000));
    if (!current()) return;
    if (advanced(pos)) {
      _diag?.pb('EOF in background; sound continues');
      return;
    }
    _diag?.pb('EOF in background; recovery waits for return');
    _recoverOnResume = kind;
  }

  Future<void> _restorePictureAfterBackground(
    Player player, {
    bool setVideo = true,
  }) async {
    if (setVideo) await appMpvSet(player, 'vid', 'auto');
    // The video chain restarts with a new hardware session; if mpv still
    // chose software decoding, ask for the hardware decoder again.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted || _leaving || !identical(_player, player)) return;
    var now = await appMpvGet(player, 'hwdec-current');
    // '?' = not readable yet (picture not playing); only a confirmed
    // software decoder is reset.
    if (now == 'no') {
      await resetAppHardwareDecoder(
        player,
        _decoderMode.mpvValueFor(
          android: defaultTargetPlatform == TargetPlatform.android,
        ),
      );
      now = await appMpvGet(player, 'hwdec-current');
    }
    _diag?.pb('LIFECYCLE resumed; picture back hwdec=$now');
  }

  Future<void> _init() async {
    if (_initializing || _leaving || !mounted) return;
    _initializing = true;
    try {
      await _disposePlayer();
      await _stopLease();
      if (!mounted || _leaving) return;
      setState(() {
        _ready = false;
        _failed = false;
        _decoderLimited = false;
        _hdAlternative = null;
        _conflict = false;
        _error = null;
        _buffering = false;
        _userPaused = false;
      });
      await _initializePlayback();
      if (_failed) {
        await _disposePlayer();
        await _stopLease();
      }
    } catch (e, st) {
      _diag?.pb('ERROR code=INIT_FAILED type=${e.runtimeType}');
      Diag.err('playback init failed', e, st);
      if (mounted && !_leaving) {
        setState(() {
          _ready = false;
          _failed = true;
          _error = 'Playback unavailable. Please try again.';
        });
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> _initializePlayback() async {
    final session = ref.read(sessionProvider);
    // Store-review demo: same player, openly licensed streams, no backend.
    if (!session.isLoggedIn && ref.read(demoModeProvider)) {
      final ok = await _openDemoPlayback();
      if (!mounted) return;
      if (!ok && !_failed) {
        setState(() {
          _failed = true;
          _error ??= 'Playback unavailable';
        });
      }
      return;
    }
    if (!session.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _error = 'Sign in to play';
      });
      return;
    }
    // Client 18 Oct #16: no internet → say so in seconds, not a long hang.
    // The quick TCP probe is only a hint (client 20 Oct, IMG_5013: the TCL
    // TV said "no internet" while online — one 4 s connect to the API host
    // can fail on a slow DNS / broken IPv6 path). Playback is still tried;
    // "no internet" is shown only when the real request has no answer.
    // Only a hint for the diagnostics log, so it no longer delays the start
    // (client 5 Nov: "opening videos is slow across all sections"; every
    // play waited for this DNS + TCP probe, up to 4 s, before the request).
    unawaited(appServerReachable().then((up) {
      if (!up) Diag.pb('PLAY probe: server not reached in 4 s; playback tried anyway');
    }));
    if (!mounted || _leaving) return;
    final ok = await _openRemotePlayback();
    if (!mounted) return;
    if (!ok && !_failed) {
      setState(() {
        _failed = true;
        _error ??= 'Playback unavailable';
      });
    }
  }

  /// Title + category as shown in this player, sent with the lease so the
  /// Control Panel shows exactly what the customer watches (client 27 Oct).
  Future<(String?, String?)> _panelLabel() async {
    final m = _media;
    if (m == null) return (null, null);
    final sub = (m.subtitle ?? '').trim();
    final isSeries = m.kind == MediaKind.series ||
        (m.seriesId != null && m.seriesId!.isNotEmpty);
    final name =
        cleanDisplayName(m.title, keepQuality: _isLivePlayback).trim();
    final title = isSeries && sub.isNotEmpty ? '$name · $sub' : name;
    String? category;
    final catId = (m.categoryId ?? '').trim();
    if (catId.isNotEmpty) {
      try {
        final kind = _isLivePlayback
            ? MediaKind.live
            : (isSeries ? MediaKind.series : MediaKind.movie);
        final cats =
            await ref.read(catalogRepositoryProvider).getCategories(kind);
        category = cats
            .where((c) => c.id == catId)
            .map((c) => cleanDisplayName(c.name).trim())
            .firstWhere((n) => n.isNotEmpty, orElse: () => '');
      } catch (_) {}
    }
    return (
      title.isEmpty ? null : title,
      (category == null || category.isEmpty) ? null : category,
    );
  }

  Future<bool> _openRemotePlayback() async {
    try {
      final media = ref.read(mediaRepositoryProvider);
      final auth = ref.read(authRepositoryProvider);
      final session = ref.read(sessionProvider);
      final catalog = ref.read(catalogRepositoryProvider);

      // Usman: contentType is live | vod | series. Prefer cached catalog row
      // (has containerExtension) even when ?kind= is set.
      final hint = widget.kindHint;
      var seriesKey = (widget.seriesId != null && widget.seriesId!.isNotEmpty)
          ? widget.seriesId!
          : null;
      // Continue Watching often has episode streamId + kind=series but no
      // seriesId. Recover parent from a prior series-detail index when possible.
      seriesKey ??= catalog.knownSeriesIdForEpisode(widget.id);
      // Episode taps pass seriesId. Looking up the episode id via getById
      // calls GET /catalog/series/{episodeId} and comes back "Untitled".
      final lookupId =
          seriesKey ?? (hint == MediaKind.series ? null : widget.id);
      var item = lookupId == null
          ? null
          : await catalog.getById(
              lookupId,
              kind: seriesKey != null ? MediaKind.series : hint,
            );
      // The catalog can miss (e.g. right after a language switch): the
      // user's own Continue Watching / My List copy has the real title.
      item ??= lookupId == null ? null : _library?.findKnown(lookupId);
      var playingEpisode =
          seriesKey != null && seriesKey != widget.id ||
          (item != null &&
              item.kind == MediaKind.series &&
              item.id != widget.id);
      // Continue Watching: kind=series + episode stream id, no parent yet.
      if (!playingEpisode &&
          hint == MediaKind.series &&
          seriesKey == null &&
          item == null) {
        playingEpisode = true;
      }
      if (playingEpisode) {
        final sid = seriesKey;
        Episode? ep;
        if (sid != null) {
          ep = await _episodeInSeries(catalog, sid, widget.id);
          // The season list is for the next-episode strip only: it loads beside
          // the start instead of before it (client 5 Nov: slow playback start).
          unawaited(_loadEpisodePlaylist(catalog, sid, widget.id).catchError((_) {}));
        }
        item = MediaItem(
          id: widget.id,
          title: ep?.title ?? item?.title ?? AppBrand.name,
          kind: MediaKind.series,
          posterUrl: item?.posterUrl ?? ep?.stillUrl,
          backdropUrl: item?.backdropUrl ?? item?.posterUrl,
          synopsis: ep?.synopsis ?? item?.synopsis,
          containerExtension:
              ep?.containerExtension ??
              item?.containerExtension ??
              catalog.knownContainerExtension(widget.id),
          seriesId: sid,
        );
      } else if (item == null && hint != null && hint != MediaKind.series) {
        item = MediaItem(
          id: widget.id,
          title: AppBrand.name,
          kind: hint,
          isLive: hint == MediaKind.live || hint == MediaKind.sports,
          containerExtension: catalog.knownContainerExtension(widget.id),
        );
      }
      _media = item;
      _title = cleanDisplayName(
        item?.title ?? AppBrand.name,
        keepQuality: _isLivePlayback,
      );
      if (mounted) setState(() {});

      final deviceId = await auth.ensurePlaybackDeviceId();
      if (!mounted || _leaving) return false;
      _deviceId = deviceId;
      _diag = PlaybackDiagSession();
      _pb.beginSession(_diag!.sid);
      _diag!.pb('PLAY start content=${widget.id}');
      _lease = LeaseManager(
        media: media,
        deviceId: deviceId,
        onLeaseAtRisk: () {
          if (!mounted || _leaving) return;
          _pb.setLeaseAtRisk(true);
          if (mounted) setState(() {});
        },
        onLeaseLost: () {
          if (!mounted || _leaving) return;
          // The backend no longer authorizes this stream: stop the player and
          // release its provider connection instead of playing behind an error.
          _diag?.pb('LEASE_LOST stopping player');
          _silenceAndInvalidate();
          unawaited(_disposePlayer());
          unawaited(_stopLease());
          _pb.setError('Playback lease lost. Tap Retry.', retryable: true);
          if (mounted) {
            setState(() {
              _ready = false;
              _failed = true;
              _error = 'Playback lease lost. Tap Retry.';
            });
          }
        },
        onDeviceConflict: (msg, {code}) {
          if (!mounted || _leaving) return;
          Diag.err('device conflict mid-play: $msg code=$code');
          // A paused mpv keeps reading ahead and holds the provider connection,
          // which can break the device that now owns the stream.
          _silenceAndInvalidate();
          unawaited(_disposePlayer());
          unawaited(_stopLease());
          if (mounted) {
            final admin = code == 'PLAYBACK_STOPPED_BY_ADMIN';
            setState(() {
              _failed = true;
              // Admin stop: no "Watch here" / manage-devices lease UI.
              _conflict = !admin;
              _error = admin
                  ? _copy.playbackStoppedByOperatorTitle
                  : msg;
              _ready = false;
            });
          }
        },
        onRenew: (lease) async {
          if (!mounted || _leaving) return;
          // urlContinuity guaranteed — LeaseManager skips reopen when same URL.
          final pos = _player?.state.position.inSeconds ?? 0;
          _resumeStartSec = pos > 5 ? pos : _resumeStartSec;
          await _openNetwork(_preferredUrl(lease), label: 'APP');
        },
      );
      _stats.reset();
      _lease!.statsProvider = _stats.snapshot;

      // Exact contentType — do not probe other types (one-stream lease).
      var contentType = AppMediaRepository.contentTypeFromKind(
        item?.kind ?? hint ?? MediaKind.movie,
      );
      var streamId = widget.id;
      String? container = item?.containerExtension;

      if (playingEpisode || hint == MediaKind.series) {
        contentType = 'series';
        streamId = widget.id;
        container = item?.containerExtension ?? container;
      } else if (item?.kind == MediaKind.series) {
        contentType = 'series';
        final eps = await catalog.getEpisodes(item!.id, season: 1);
        if (eps.isEmpty) {
          throw Exception('No episodes available to play');
        }
        streamId = eps.first.id;
        container = eps.first.containerExtension ?? container;
        _title = cleanDisplayName(eps.first.title);
        _media = MediaItem(
          id: streamId,
          title: _title,
          kind: MediaKind.series,
          posterUrl: item.posterUrl,
          backdropUrl: item.backdropUrl,
          synopsis: eps.first.synopsis ?? item.synopsis,
          containerExtension: container,
          seriesId: item.id,
        );
      } else if (item == null && hint == null) {
        // Unknown id: prefer vod. Guessing series yields /series/ CDN paths → 405.
        contentType = 'vod';
        streamId = widget.id;
      }

      _contentType = contentType;
      // Live TV / Sports: Stretch (CEO 25 Oct) unless the customer changed it
      // on this channel.
      if (_isLivePlayback && !_screenModePicked && _screenMode != VideoScreenMode.liveDefault) {
        setState(() => _screenMode = VideoScreenMode.liveDefault);
      }

      container = await resolvePlaybackContainer(
        catalog: catalog,
        contentType: contentType,
        streamId: streamId,
        known: container,
        seriesId: seriesKey ?? item?.seriesId ?? _media?.seriesId,
        findEpisode: (sid, eid) => _episodeInSeries(catalog, sid, eid),
      );

      Future<PlaybackSessionDto> start(String id) async {
        _lease!.deviceId = id;
        final caps = DeviceCapabilitiesStore.instance.current;
        final tierCfg = DeviceCapabilitiesStore.instance.mpv;
        final qualityPref = ref.read(sessionProvider).playbackQuality;
        final maxH = playbackMaxHeightFor(
          qualityPref: qualityPref,
          tier: caps?.tier ?? tierCfg.tier,
        );
        final codecs = caps == null
            ? const ['hevc', 'avc']
            : playbackCodecPreference(qualityPref: qualityPref, caps: caps);
        if (caps != null) {
          final sel = StreamSelector(caps).select(
            contentHeight: maxH >= 2160 ? 2160 : maxH,
            codecHint: codecs.first,
            userForcePlay: _forcePlayDespiteWarn,
          );
          if (sel.decision == StreamPlayDecision.warnMayStutter &&
              !_forcePlayDespiteWarn) {
            // Continue but surface banner after open; user can Retry force.
            _pendingStutterWarn = sel.message;
          }
        }
        final panelLabel = await _panelLabel();
        return mapPlaybackConflict(
          () => _lease!.start(
            contentType: contentType,
            streamId: streamId,
            profileId: session.activeProfileId,
            containerExtension: contentType == 'live' ? null : container,
            maxHeight: maxH,
            tier: (caps?.tier ?? tierCfg.tier).name,
            codecs: codecs,
            force: _forceTakeover,
            title: panelLabel.$1,
            categoryName: panelLabel.$2,
          ),
        );
      }

      // A previous player route may still be releasing its player and lease
      // (Back, then play the next episode; or a replaced route). One-stream
      // enforcement needs that stop first. Bounded so start never hangs.
      // An active download holds the provider connection: pause it first.
      final pausedDownload = await PlaybackArbiter.beforePlayback();
      if (pausedDownload != null && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            // Floating: in landscape full screen the bottom edge cut the
            // second line off.
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
            content: Text(_copy.downloadPausedForPlayback(pausedDownload)),
          ),
        );
      }
      if (!await PlayerLifecycleGate.settle(const Duration(seconds: 6))) {
        _diag?.pb('previous playback teardown still pending at lease start');
      }
      if (!mounted || _leaving) return false;
      _recovery = AppRecoveryBudget();

      Future<PlaybackSessionDto> acquireLease(String id) async {
        try {
          // 20 s, was 8: normal replies take 1.5–4 s, but a slow backend reply
          // after 8 s made the app give up while the lease was still created.
          return await start(id).timeout(const Duration(seconds: 20));
        } on ApiException catch (e) {
          if (!AppAuthRepository.isDeviceGoneError(e)) rethrow;
          final fresh = await auth.forceReregisterDevice();
          _deviceId = fresh;
          return await start(fresh).timeout(const Duration(seconds: 20));
        } on PlaybackConflictException catch (e) {
          // M2: 409 may be stale after CP stop / TTL — re-check Redis lease.
          try {
            final status = await media.playbackLeaseStatus();
            if (!status.isActive) {
              _diag?.pb(
                'CONFLICT stale Inactive label=${status.label}; retry start',
              );
              await Future<void>.delayed(const Duration(milliseconds: 350));
              return await start(_deviceId ?? id)
                  .timeout(const Duration(seconds: 20));
            }
          } catch (_) {}
          rethrow;
        }
      }

      PlaybackSessionDto lease = await acquireLease(deviceId);

      if (!mounted || _leaving) {
        await _stopLease();
        return false;
      }
      _playbackId = lease.playbackId;
      if (_isLivePlayback) {
        _liveOpenedAt = DateTime.now();
        _userBehindLive = false;
        _resumeStartSec = null;
        _liveTicker?.cancel();
        _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted || !_isLivePlayback) return;
          _syncLiveEdgeFromClock();
          setState(() {});
        });
      }

      final host = Uri.tryParse(lease.playUrl)?.host ?? '?';
      _diag?.pb(
        'lease ok ttl=${lease.leaseTtlSec} host=$host '
        '${describePlayUrl(lease.playUrl)} '
        'dur=${_diag!.msSinceTap()}ms type=$contentType stream=$streamId',
      );

      // Never resume into live — that parks the player behind the live edge.
      if (_isLivePlayback) {
        _resumeStartSec = null;
      } else {
        // Resolve resume offset before open (Media.start — brief §1.2).
        // A failover restart keeps the latest position of this session.
        var resumeSec = _failoverResumeSec ?? widget.startSec;
        _failoverResumeSec = null;
        if (resumeSec == null || resumeSec <= 0) {
          resumeSec = ref.read(libraryProvider).resumePositionSecFor(widget.id);
        }
        if (resumeSec != null && resumeSec > 5) {
          _resumeStartSec = resumeSec;
        }
      }

      _providerAuthUrl = lease.providerAuthUrl;
      await _loginProviderFromDevice();
      _pb.setPhase(PlaybackPhase.openingMedia);
      // This device already needed the Android engine after an mpv decoder
      // failure this session: start there (each failed mpv try cost ~30 s).
      final nativeFirst = _sessionNativeAfterDecoder;
      if (nativeFirst) _diag?.pb('ENGINE native-first (session)');
      var opened = await _openNetwork(
        lease.playUrl,
        label: 'APP',
        forceNative: nativeFirst,
      );
      if (!opened && nativeFirst && mounted && !_leaving) {
        _sessionNativeAfterDecoder = false;
        _diag?.pb('ENGINE native-first failed; trying mpv');
        opened = await _openNetwork(lease.playUrl, label: 'APP');
      }
      if (!opened &&
          _lastOpenFailureKind == AppFailureKind.connectionLimit) {
        opened = await _waitForFreeLine(lease.playUrl);
      }
      final openFailure = _lastOpenFailureKind;
      // Retry once for transient network/server failures. Not for timeouts
      // (another 20s wait) or authorization/missing content/decoder errors.
      if (!opened &&
          mounted &&
          !_leaving &&
          openFailure != null &&
          openFailure != AppFailureKind.timeout &&
          // Busy line was already retried for up to 90 s above.
          openFailure != AppFailureKind.connectionLimit &&
          (_lease?.isActive ?? false) &&
          _recovery.tryConsume(openFailure)) {
        final delay = recoveryDelayFor(openFailure);
        _diag?.pb(
          'RECOVERY open retry kind=${openFailure.name} '
          'delayMs=${delay.inMilliseconds}',
        );
        _pb.setPhase(PlaybackPhase.openingMedia);
        await Future<void>.delayed(delay);
        if (mounted && !_leaving) {
          opened = await _openNetwork(lease.playUrl, label: 'APP');
        }
      }
      // Backend-approved alternates (same lease, other scheme): some networks
      // reset TLS to the media host, others block plain HTTP.
      for (final (i, alt) in lease.alternatePlayUrls.indexed) {
        if (opened || !mounted || _leaving) break;
        if (!(_lease?.isActive ?? false)) break;
        if (!_alternateMayHelp(_lastOpenFailureKind)) break;
        _diag?.pb(
          'ALTERNATE ${i + 1}/${lease.alternatePlayUrls.length} '
          'after kind=${_lastOpenFailureKind?.name} ${describePlayUrl(alt)}',
        );
        _pb.setPhase(PlaybackPhase.openingMedia);
        opened = await _openNetwork(alt, label: 'APP');
        _diag?.pb('ALTERNATE result=${opened ? 'ok' : 'failed'}');
        if (opened) _preferredScheme = Uri.tryParse(alt)?.scheme;
      }
      if (opened && _preferredScheme == null) {
        _preferredScheme = Uri.tryParse(lease.playUrl)?.scheme;
      }
      final fallbackKind = _lastOpenFailureKind;
      if (!opened &&
          mounted &&
          !_leaving &&
          (_lease?.isActive ?? false) &&
          // Already tried the Android engine first this open.
          !nativeFirst &&
          await _shouldTryNativeFallback(fallbackKind)) {
        _diag?.pb('FALLBACK engine=native after kind=${fallbackKind!.name}');
        _pb.setPhase(PlaybackPhase.openingMedia);
        if (mounted && !_leaving) {
          opened = await _openNetwork(
            lease.playUrl,
            label: 'APP',
            forceNative: true,
          );
        }
        _diag?.pb('FALLBACK engine=native result=${opened ? 'ok' : 'failed'}');
        if (opened && fallbackKind == AppFailureKind.decoder) {
          _sessionNativeAfterDecoder = true;
        }
      }
      _diag?.pb(
        'open() done success=$opened +${_diag!.msSinceTap()}ms host=$host',
      );
      // M2 host failover: stop + start again so backend can issue a new host.
      for (var hop = 1; !opened && hop <= 2 && mounted && !_leaving; hop++) {
        _diag?.pb('HOST_FAILOVER stop+start attempt=$hop/2');
        await _persistProgress(force: true);
        // Soft-stop: keep LeaseManager so acquireLease can start again.
        _playbackId = null;
        await _lease?.stop();
        await Future<void>.delayed(Duration(milliseconds: 400 * hop));
        if (!mounted || _leaving) break;
        try {
          lease = await acquireLease(_deviceId ?? deviceId);
        } on PlaybackConflictException {
          break;
        }
        if (!mounted || _leaving) break;
        _playbackId = lease.playbackId;
        _providerAuthUrl = lease.providerAuthUrl;
        await _loginProviderFromDevice();
        _pb.setPhase(PlaybackPhase.openingMedia);
        final hopHost = Uri.tryParse(lease.playUrl)?.host ?? '?';
        _diag?.pb(
          'HOST_FAILOVER new lease host=$hopHost '
          '${describePlayUrl(lease.playUrl)}',
        );
        opened = await _openNetwork(lease.playUrl, label: 'APP');
        for (final (i, alt) in lease.alternatePlayUrls.indexed) {
          if (opened || !mounted || _leaving) break;
          if (!_alternateMayHelp(_lastOpenFailureKind)) break;
          _diag?.pb(
            'HOST_FAILOVER ALTERNATE ${i + 1} ${describePlayUrl(alt)}',
          );
          opened = await _openNetwork(alt, label: 'APP');
        }
      }
      if (!opened) {
        await _stopLease();
        if (mounted) {
          setState(() {
            _failed = true;
            _error ??= 'Playback failed. Please try again.';
          });
        }
      }
      unawaited(_sendPlaybackReport(opened ? 'open_ok' : 'open_failed'));
      return opened;
    } on PlaybackConflictException catch (e) {
      _diag?.pb('ERROR code=CONFLICT phase=resolvingLease');
      Diag.err('playback conflict', e);
      String? holderName;
      try {
        final repo = ref.read(mediaRepositoryProvider);
        final active = await repo.playbackActive();
        if (active.active) {
          holderName = active.deviceName ?? active.deviceId;
        }
      } catch (_) {
        holderName = e.holderDeviceId;
      }
      if (mounted) {
        final copy = _copy;
        final heldMsg = holderName != null && holderName.isNotEmpty
            ? copy.playbackHeldByDevice(holderName)
            : null;
        setState(() {
          _failed = true;
          _conflict = true;
          _forceTakeover = false;
          _error = heldMsg ??
              userFacingPlaybackError(e, fallback: e.message);
        });
      }
      return false;
    } on ApiException catch (e) {
      _diag?.pb('ERROR code=API phase=resolvingLease status=${e.statusCode}');
      // A timed-out lease request may still succeed on the server. Stop the
      // lease manager so a late reply is released at once (it checks
      // _stopped). Before, the late lease kept heartbeating and held the
      // single-connection line: the next Play got CONFLICT "another device".
      await _stopLease();
      Diag.err('playback api', e);
      // Internet fine, server down: say so, not "No internet" (client 5 Nov).
      final internetOk = e.isNetwork && await deviceHasInternet();
      if (mounted) {
        final admin = e.isPlaybackStoppedByAdmin;
        setState(() {
          _failed = true;
          _conflict = false;
          _error = admin
              ? _copy.playbackStoppedByOperatorTitle
              : e.isNetwork
                  ? (internetOk ? _copy.serverUnavailablePlay : _copy.noInternetPlay)
                  : userFacingPlaybackError(e, fallback: e.message);
        });
      }
      unawaited(_sendPlaybackReport('open_failed'));
      return false;
    } catch (e, st) {
      _diag?.pb('ERROR code=REMOTE phase=resolvingLease');
      // A timed-out lease request may still succeed on the server. Stop the
      // lease manager so a late reply is released at once (it checks
      // _stopped). Before, the late lease kept heartbeating and held the
      // single-connection line: the next Play got CONFLICT "another device".
      await _stopLease();
      Diag.err('playback remote failed', e, st);
      if (mounted) {
        setState(() {
          _failed = true;
          _error = userFacingPlaybackError(e);
        });
      }
      unawaited(_sendPlaybackReport('open_failed'));
      return false;
    }
  }

  /// Demo playback: the title, episode or channel comes from the demo
  /// catalog and its own https stream ([DemoContent.hosts] only) opens in
  /// the normal player. No lease, device id, heartbeat, provider login,
  /// progress upload or playback report: [_lease], [_playbackId] and
  /// [_deviceId] stay null, which already turns those off.
  Future<bool> _openDemoPlayback() async {
    try {
      final catalog = ref.read(catalogRepositoryProvider);
      final hint = widget.kindHint;
      final seriesKey = (widget.seriesId != null && widget.seriesId!.isNotEmpty)
          ? widget.seriesId
          : catalog.knownSeriesIdForEpisode(widget.id);
      MediaItem? item;
      String? url;

      Future<void> useEpisode(MediaItem? series, String sid, Episode ep) async {
        await _loadEpisodePlaylist(catalog, sid, ep.id);
        url = ep.streamUrl;
        item = MediaItem(
          id: ep.id,
          title: ep.title,
          kind: MediaKind.series,
          posterUrl: ep.stillUrl ?? series?.posterUrl,
          backdropUrl: series?.backdropUrl ?? ep.stillUrl,
          synopsis: ep.synopsis ?? series?.synopsis,
          containerExtension: ep.containerExtension,
          seriesId: sid,
        );
      }

      if (seriesKey != null) {
        final series = await catalog.getById(seriesKey, kind: MediaKind.series);
        final ep = await _episodeInSeries(catalog, seriesKey, widget.id);
        if (ep != null) await useEpisode(series, seriesKey, ep);
      } else {
        final found = await catalog.getById(widget.id, kind: hint);
        if (found != null && found.kind == MediaKind.series) {
          final eps = await catalog.getEpisodes(found.id, season: 1);
          if (eps.isNotEmpty) await useEpisode(found, found.id, eps.first);
        } else {
          item = found;
          url = found?.streamUrl;
        }
      }

      final m = item;
      _media = m;
      _contentType = m == null
          ? 'vod'
          : (m.isLive || m.kind == MediaKind.live)
              ? 'live'
              : m.kind == MediaKind.series
                  ? 'series'
                  : 'vod';
      _title = cleanDisplayName(
        m?.title ?? AppBrand.name,
        keepQuality: _isLivePlayback,
      );
      if (mounted) setState(() {});

      final playUrl = url;
      if (m == null || playUrl == null || !DemoContent.isAllowedUrl(playUrl)) {
        if (mounted) {
          setState(() {
            _failed = true;
            _error = 'Playback unavailable';
          });
        }
        return false;
      }

      _diag = PlaybackDiagSession();
      _pb.beginSession(_diag!.sid);
      _diag!.pb('PLAY start demo content=${widget.id}');
      _recovery = AppRecoveryBudget();
      // Demo films open in Fit like every movie (client 6 Nov: movies at the
      // largest size with their own proportions, never cropped; Fill cut the
      // sides of the 2.35:1 films).
      if (_isLivePlayback) {
        _liveOpenedAt = DateTime.now();
        _userBehindLive = false;
        _resumeStartSec = null;
        _liveTicker?.cancel();
        _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted || !_isLivePlayback) return;
          _syncLiveEdgeFromClock();
          setState(() {});
        });
      } else {
        var resumeSec = widget.startSec;
        if (resumeSec == null || resumeSec <= 0) {
          resumeSec = ref.read(libraryProvider).resumePositionSecFor(widget.id);
        }
        if (resumeSec != null && resumeSec > 5) _resumeStartSec = resumeSec;
      }

      _pb.setPhase(PlaybackPhase.openingMedia);
      final opened = await _openNetwork(playUrl, label: 'APP');
      if (!opened && mounted) {
        setState(() {
          _failed = true;
          _error ??= 'Playback failed. Please try again.';
        });
      }
      return opened;
    } catch (e, st) {
      Diag.err('demo playback failed', e, st);
      if (mounted) {
        setState(() {
          _failed = true;
          _error = userFacingPlaybackError(e);
        });
      }
      return false;
    }
  }

  Future<void> _stopLease() async {
    final lease = _lease;
    _lease = null;
    _playbackId = null;
    await lease?.stop();
    lease?.dispose();
  }

  Future<void> _disposePlayer() {
    final existing = _disposeInFlight;
    if (existing != null) return existing;
    _stats.detach();
    _stallWatchdog?.cancel();
    _stallWatchdog = null;
    _pb.stopWatchdog();
    _seekEpoch++;
    _seekInFlight = false;
    final cancelled = _openCancelled;
    _openCancelled = null;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
    _diag?.stopPerf();
    _failureMonitor?.close();
    _failureMonitor = null;
    final subs = List<StreamSubscription<dynamic>>.of(_subs);
    _subs.clear();
    final native = _nativePlayer;
    _nativePlayer = null;
    final p = _player;
    final video = _video;
    final disposeId = identityHashCode(p ?? video ?? this);
    _player = null;
    _video = null;
    _diag?.pb(
      'dispose start id=$disposeId '
      'player=${p == null ? 'null' : identityHashCode(p)} '
      'video=${video == null ? 'null' : identityHashCode(video)}',
    );
    // Every step is time-limited. A decoder that never produced a frame
    // could block mpv dispose forever: the Retry screen never appeared and
    // every later open (Retry, next channel, other titles) queued behind it.
    Future<void> bounded(String stage, Future<void>? step, int ms) async {
      if (step == null) return;
      try {
        await step.timeout(Duration(milliseconds: ms));
      } on TimeoutException {
        _diag?.pb('DISPOSE_TIMEOUT stage=$stage id=$disposeId ms=$ms');
      } catch (_) {}
    }

    final future = () async {
      for (final s in subs) {
        await bounded('subscription', s.cancel(), 1000);
      }
      await bounded('native', native?.dispose(), 4000);
      if (p != null) {
        // Stop network/decoding first so dispose has less to unwind.
        await bounded('stop', p.stop(), 1000);
        await bounded('player', p.dispose(), 3000);
      }
      _diag?.pb('dispose done id=$disposeId');
    }();
    late final Future<void> completion;
    completion = future.whenComplete(() {
      if (identical(_disposeInFlight, completion)) _disposeInFlight = null;
    });
    _disposeInFlight = completion;
    return completion;
  }

  /// Runs [action] only after prior opens/disposes (this route and others) finish.
  Future<bool> _enqueueOpen(Future<bool> Function(int gen) action) {
    final gen = ++_openGen;
    return PlayerLifecycleGate.enqueue(() async {
      if (!mounted || gen != _openGen) return false;
      return action(gen);
    });
  }

  /// Stops audio immediately and invalidates in-flight opens (back / dispose).
  void _silenceAndInvalidate() {
    _openGen++;
    final cancelled = _openCancelled;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
    final p = _player;
    try {
      p?.pause();
      _nativePlayer?.pause();
    } catch (_) {}
  }

  /// Instant leave: pop first, cleanup off-path (brief §1.4).
  bool _confirmOpen = false;

  /// Back / the back arrow during playback asks first, as on TV (17 Oct):
  /// "Stop watching?" Cancel / Exit. A failed or still-opening player
  /// leaves at once.
  Future<void> _requestLeave() async {
    if (_leaving || _confirmOpen) return;
    if (!_ready || _failed) {
      await _leavePlayer();
      return;
    }
    _confirmOpen = true;
    final copy = _copy;
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141A26),
        title: Text(copy.playerExitTitle),
        content: Text(copy.playerExitMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(copy.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.cyan,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.logout_rounded),
            label: Text(copy.playerExitConfirm),
          ),
        ],
      ),
    );
    _confirmOpen = false;
    if (exit == true && mounted) await _leavePlayer();
  }

  /// [thenOpen]: a route opened after the player has closed (Device
  /// Management from the "another device is playing" screen).
  Future<void> _leavePlayer({String? thenOpen}) async {
    if (_leaving) return;
    unawaited(AppPip.setAuto(false));
    setState(() => _leaving = true);
    _hideControls?.cancel();
    // Rotate back to portrait BEFORE the route closes (iPhone, 17 Oct): the
    // orientation was released and the page popped in the same frame, so
    // the screen underneath was drawn sideways mid-rotation. The player
    // (black while leaving) turns first; the pop follows once upright.
    final wasLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _silenceAndInvalidate();
    // Position saved in the background (it waited for the server and the
    // exit felt stuck); the player is closed right away.
    unawaited(
      _persistProgress(force: true, refreshRemote: true).catchError((_) {}),
    );
    await _disposePlayer();
    PlayerLifecycleGate.track(_stopLease());
    if (!mounted) return;
    if (wasLandscape) {
      // Up to ~0.6 s for the rotation to finish.
      for (var i = 0; i < 12; i++) {
        if (!mounted) return;
        if (MediaQuery.orientationOf(context) == Orientation.portrait) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      // The size flips before iOS finishes its turn animation; the page
      // below was shown half-turned (17 Oct recording). Let it settle.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // PopScope canPop must be true before an imperative pop succeeds.
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = GoRouter.of(context);
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
      if (thenOpen != null) router.push(thenOpen);
    });
  }

  /// Concurrent-lease "Manage devices" (C7): do not await dispose (felt frozen),
  /// restore portrait, and open devices with a back stack.
  /// [go('/settings/devices')] alone left nowhere to [pop] — Back did nothing.
  Future<void> _leaveToManageDevices() async {
    if (_leaving) return;
    unawaited(AppPip.setAuto(false));
    setState(() => _leaving = true);
    _hideControls?.cancel();
    final wasLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _silenceAndInvalidate();
    unawaited(
      _persistProgress(force: true, refreshRemote: true).catchError((_) {}),
    );
    final disposing = _disposePlayer();
    PlayerLifecycleGate.track(disposing);
    PlayerLifecycleGate.track(_stopLease());
    if (wasLandscape) {
      for (var i = 0; i < 12; i++) {
        if (!mounted) return;
        if (MediaQuery.orientationOf(context) == Orientation.portrait) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Settings underneath so Devices back button can pop.
      context.go('/settings');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.push('/settings/devices');
      });
    });
  }

  Future<void> _waitUntilReady(
    Player player, {
    bool requireSurfaceDecoder = false,
    Future<void>? failure,
  }) async {
    final video = _video;
    if (video == null) throw StateError('Video output unavailable');
    final ready = requireSurfaceDecoder
        ? waitForAppSurfaceFrame(
            firstFrame: video.waitUntilFirstFrameRendered,
            readHardware: () => appMpvGet(player, 'hwdec-current'),
            isCurrent: () => mounted && !_leaving && identical(_player, player),
          )
        : video.waitUntilFirstFrameRendered;
    // A classified load failure (HTTP status, refused connection, unknown
    // format) ends the wait instead of holding the spinner until timeout.
    await _awaitOpenStep(
      failure == null ? ready : Future.any<void>([ready, failure]),
      timeout: _firstFrameHardLimit,
    );
    if (!mounted || _leaving || !identical(_player, player)) {
      throw StateError('Playback cancelled');
    }
  }

  static const _firstFrameLimit = Duration(seconds: 20);
  static const _firstFrameHardLimit = Duration(seconds: 50);

  /// First-frame timeout that keeps waiting while video is still arriving
  /// (iPhone 17 Oct, Extraction 2 4K: the provider's first bytes came after
  /// 24 s, the fixed 20 s timeout closed the open two seconds before the
  /// picture and the retry cost another 8 s). After 20 s without a frame it
  /// waits on in 5 s steps as long as the buffer grew, up to 50 s.
  Future<void> _waitWhileLoading(Player player, Future<void> ready) async {
    var done = false;
    Object? error;
    StackTrace? trace;
    unawaited(ready.then((_) => done = true, onError: (Object e, StackTrace st) {
      error = e;
      trace = st;
      done = true;
    }));
    final start = DateTime.now();
    var deadline = start.add(_firstFrameLimit);
    var lastBuffer = player.state.buffer;
    var extended = false;
    while (!done) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (done) break;
      final now = DateTime.now();
      if (now.isBefore(deadline)) continue;
      final buffer = player.state.buffer;
      final growing = buffer > lastBuffer;
      lastBuffer = buffer;
      if (!growing || now.difference(start) >= _firstFrameHardLimit) {
        throw TimeoutException('first frame', now.difference(start));
      }
      if (!extended) {
        extended = true;
        _diag?.pb('first frame wait extended: data still arriving '
            'buffer=${buffer.inSeconds}s');
      }
      deadline = now.add(const Duration(seconds: 5));
    }
    if (error != null) Error.throwWithStackTrace(error!, trace!);
  }

  Future<void> _awaitOpenStep(
    Future<void> operation, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final cancelled = _openCancelled;
    await Future.any<void>([
      operation,
      if (cancelled != null)
        cancelled.future.then<void>(
          (_) => throw StateError('Playback cancelled'),
        ),
    ]).timeout(timeout);
  }

  void _startStallWatchdog(Player player) {
    _stallWatchdog?.cancel();
    _lastPlaybackAdvance = DateTime.now();
    var previous = player.state.position;
    var ticks = 0;
    _stallWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _leaving || !identical(_player, player)) return;
      if (++ticks % 30 == 0) {
        unawaited(appNetworkLine(player).then((line) {
          if (identical(_player, player)) _diag?.pb(line);
        }));
      }
      final current = player.state.position;
      if (player.state.buffering) {
        _recovery.noteInterrupted();
      } else if (player.state.playing && current != previous) {
        _recovery.notePlaying();
      }
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!_ready ||
          _seekInFlight ||
          _failed ||
          _userPaused ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
          (!player.state.playing && !player.state.buffering) ||
          player.state.completed ||
          current != previous) {
        previous = current;
        _lastPlaybackAdvance = DateTime.now();
        return;
      }
      if (DateTime.now().difference(_lastPlaybackAdvance) >=
          const Duration(seconds: 25)) {
        _stallWatchdog?.cancel();
        unawaited(
          _recoverOrFail(
            player,
            _midPlayFailureKind ?? AppFailureKind.timeout,
            'stall',
          ),
        );
      }
    });
  }

  Future<void> _failActivePlayback(
    Player player, {
    bool decoderLimited = false,
    AppFailureKind? kind,
  }) async {
    if (!mounted || _leaving || _failed || !identical(_player, player)) return;
    _initializing = true;
    _pb.stopWatchdog();
    _stallWatchdog?.cancel();
    _silenceAndInvalidate();
    setState(() {
      _ready = false;
      _failed = true;
      _playing = false;
      _buffering = false;
      _decoderLimited = decoderLimited;
      _error = decoderLimited
          ? _copy.decoderLimited
          : (kind != null
                ? appFailureMessage(kind)
                : 'Playback stopped. Please check your connection and try again.');
    });
    _diag?.pb('PLAYBACK_FAILED kind=${kind?.name ?? (decoderLimited ? 'decoderLimited' : 'stall')}');
    final media = _media;
    if (decoderLimited && media != null) {
      unawaited(findHdAlternative(ref.read(catalogRepositoryProvider), media).then((alt) {
        if (mounted && alt != null) setState(() => _hdAlternative = alt);
        _diag?.pb('HD_ALTERNATIVE ${alt == null ? 'none' : 'found id=${alt.id}'}');
      }));
    }
    unawaited(_sendPlaybackReport('mid_failure'));
    _pb.setError(_error ?? _copy.decoderLimited);
    try {
      await _disposePlayer();
    } catch (_) {
      // The failure UI remains available even if native teardown fails.
    } finally {
      await _stopLease();
      _initializing = false;
    }
  }

  void _monitorDecoderHealth(Player player) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final health = AppDecoderHealth();
    final watch = Stopwatch()..start();
    var lastEpoch = _seekEpoch;
    var reading = false;
    bool eligible() =>
        mounted &&
        !_leaving &&
        !_failed &&
        _ready &&
        !_seekInFlight &&
        !_userPaused &&
        _speed == 1.0 &&
        identical(_player, player) &&
        player.state.playing &&
        !player.state.buffering &&
        !player.state.completed &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed);
    _subs.add(
      Stream<int>.periodic(const Duration(seconds: 3), (i) => i).listen((
        _,
      ) async {
        if (reading) return;
        if (!eligible()) {
          health.reset();
          return;
        }
        final epoch = _seekEpoch;
        if (lastEpoch != epoch) {
          health.reset();
          lastEpoch = epoch;
        }
        reading = true;
        try {
          final sample = await readAppDecoderSample(player);
          if (!eligible() || epoch != _seekEpoch) {
            health.reset();
            return;
          }
          if (health.add(sample, watch.elapsed)) {
            debugPrint('[Playback] sustained UHD software decoder overload');
            // Do not await teardown inside the subscription it cancels.
            unawaited(_failActivePlayback(player, decoderLimited: true));
          }
        } finally {
          reading = false;
        }
      }),
    );
  }

  void _wirePlayer(Player player) {
    _monitorDecoderHealth(player);
    if (const bool.fromEnvironment('APP_PLAYBACK_DIAGNOSTICS')) {
      var reading = false;
      _subs.add(
        Stream<int>.periodic(const Duration(seconds: 5), (i) => i).listen((
          _,
        ) async {
          if (reading || !mounted || !identical(_player, player)) return;
          reading = true;
          try {
            await logAppPlaybackDiagnostics(player);
          } finally {
            reading = false;
          }
        }),
      );
    }
    _subs.add(
      player.stream.playing.listen((playing) {
        if (!mounted || !identical(_player, player)) return;
        _lease?.onPausedChanged(!playing);
        _pushIosPipState();
        if (mounted) setState(() => _playing = playing);
      }),
    );
    _subs.add(
      player.stream.buffering.listen((b) {
        if (!mounted || !identical(_player, player)) return;
        _diag?.onBuffering(b);
        // Server speed against the file's bitrate at every pause and resume:
        // shows whether an interruption is the source or the app.
        unawaited(appNetworkLine(player).then((line) {
          if (identical(_player, player)) {
            _diag?.pb('$line at ${b ? 'pause' : 'resume'}');
          }
        }));
        if (b) {
          _pb.setPhase(PlaybackPhase.rebuffering);
        } else if (_ready) {
          _pb.setPhase(PlaybackPhase.playing);
        }
        if (mounted) setState(() => _buffering = b);
      }),
    );
    _subs.add(
      player.stream.position.listen((pos) {
        if (!mounted || !identical(_player, player)) return;
        _position = pos;
        _syncLiveEdgeFromClock();
        final now = DateTime.now();
        // Throttle scrubber rebuilds to ~4 Hz (brief §6.1).
        if (_lastPosUi == null ||
            now.difference(_lastPosUi!) >= const Duration(milliseconds: 250)) {
          _lastPosUi = now;
          _positionN.value = pos;
          if (mounted && showControls) setState(() {});
        }
      }),
    );
    _subs.add(
      player.stream.duration.listen((dur) {
        if (!mounted || !identical(_player, player)) return;
        _duration = dur;
        _durationN.value = dur;
        _syncLiveEdgeFromClock();
      }),
    );
    _subs.add(
      player.stream.tracks.listen((_) {
        if (!mounted) return;
        _syncTracksFromPlayer(player);
      }),
    );
    _subs.add(
      player.stream.track.listen((_) {
        if (!mounted) return;
        _syncTracksFromPlayer(player, applyPrefs: false);
      }),
    );
  }

  void _syncTracksFromPlayer(Player player, {bool applyPrefs = true}) {
    final snap = appSnapshotTracks(player);
    setState(() {
      _audioTracks = snap.audios;
      _subtitleTracks = snap.subtitles;
      _videoTracks = snap.videos;
      _audioTrack = snap.audio;
      _subtitleTrack = snap.subtitle;
      _videoTrack = snap.video;
    });
    if (applyPrefs) {
      unawaited(_applyTrackPrefsIfNeeded(player));
    }
  }

  Future<void> _applyTrackPrefsIfNeeded(Player player) async {
    if (_trackPrefsApplied || !mounted) return;
    if (_audioTracks.isEmpty && _subtitleTracks.isEmpty) return;
    _trackPrefsApplied = true;
    final pref = ref.read(sessionProvider).audioPref;
    final wantAudio = appPreferAudio(_audioTracks, pref);
    if (wantAudio != null && wantAudio.id != player.state.track.audio.id) {
      await player.setAudioTrack(wantAudio);
    }
    // Prefer demuxer-marked default subtitle only (do not force a language on).
    final defSub = _subtitleTracks.cast<SubtitleTrack?>().firstWhere(
      (t) => t!.isDefault == true,
      orElse: () => null,
    );
    if (defSub != null &&
        player.state.track.subtitle.id != defSub.id &&
        player.state.track.subtitle.id != 'no') {
      await player.setSubtitleTrack(defSub);
    }
    if (mounted) _syncTracksFromPlayer(player, applyPrefs: false);
  }

  void _ensureProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || !_playing || !_ready) return;
      _persistProgress();
    });
  }

  /// Sends one scrubbed report of this attempt to the backend so support can
  /// see which title was tried, when, how long it took and why it failed,
  /// without access to the device. Best effort: never blocks or throws.
  /// Scheme that opened last time in this player (http/https), so a renewed
  /// lease reopens on the URL that works on this network.
  String? _preferredScheme;

  String _preferredUrl(PlaybackSessionDto lease) {
    final want = _preferredScheme;
    if (want == null) return lease.playUrl;
    for (final u in [lease.playUrl, ...lease.alternatePlayUrls]) {
      if (Uri.tryParse(u)?.scheme == want) return u;
    }
    return lease.playUrl;
  }

  /// Another scheme can get past TLS resets, protocol blocks (e.g. HTTP 456)
  /// and refused connections; not a missing title or a full connection slot.
  /// Set when mpv could not decode on this device but the Android engine
  /// could. Lasts until the app restarts.
  static bool _sessionNativeAfterDecoder = false;

  static bool _alternateMayHelp(AppFailureKind? kind) => switch (kind) {
        null => false,
        AppFailureKind.notFound => false,
        AppFailureKind.connectionLimit => false,
        // Another URL for the same stream cannot fix a decoder problem; go
        // straight to the Android engine fallback.
        AppFailureKind.decoder => false,
        _ => true,
      };

  String? _providerAuthUrl;

  /// Log into the provider from this phone before streaming, like a
  /// standard Xtream player. The backend logs in from its own server IP;
  /// some providers only accept a stream from an IP that logged in itself.
  Future<void> _loginProviderFromDevice() async {
    final url = _providerAuthUrl;
    if (url == null || url.isEmpty) {
      _diag?.pb('PROVIDER_LOGIN skipped (backend sent no providerAuthUrl)');
      return;
    }
    final r = await loginProviderFromDevice(url, headers: _httpHeaders);
    _diag?.pb('PROVIDER_LOGIN $r');
  }

  /// Shown on the loading screen while waiting for a busy line.
  String? _waitingLabel;
  Timer? _waitingTicker;

  /// The provider keeps a closed connection counted for a while (seen on a
  /// max_connections=1 line: HTTP 456 right after another app or the
  /// previous title stopped). Keep the loading screen up and retry until
  /// the line is free, for up to ~90 s, instead of failing at once.
  Future<bool> _waitForFreeLine(String url) async {
    const delays = [5, 10, 15, 15, 15, 15, 15];
    final total = delays.reduce((a, b) => a + b);
    final started = DateTime.now();
    void tick() {
      if (!mounted) return;
      final left = total - DateTime.now().difference(started).inSeconds;
      setState(() {
        _waitingLabel = 'Line in use by another app or device.\n'
            'Waiting for it to free up (${left < 0 ? 0 : left} s)';
      });
    }

    _waitingTicker?.cancel();
    _waitingTicker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    tick();
    try {
      for (final (i, d) in delays.indexed) {
        _diag?.pb('LINE_BUSY wait attempt=${i + 1}/${delays.length} delay=${d}s');
        for (var s = 0; s < d; s++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (!mounted || _leaving || !(_lease?.isActive ?? false)) return false;
        }
        await _loginProviderFromDevice();
        _pb.setPhase(PlaybackPhase.openingMedia);
        final ok = await _openNetwork(url, label: 'APP');
        if (ok) {
          _diag?.pb('LINE_BUSY cleared after ${DateTime.now().difference(started).inSeconds}s');
          return true;
        }
        if (_lastOpenFailureKind != AppFailureKind.connectionLimit) {
          return false;
        }
      }
      _diag?.pb('LINE_BUSY still busy after ${total}s');
      return false;
    } finally {
      _waitingTicker?.cancel();
      _waitingTicker = null;
      if (mounted) setState(() => _waitingLabel = null);
    }
  }

  static String? _clip(String? v, int max) =>
      v == null || v.length <= max ? v : v.substring(0, max);

  Future<void> _sendPlaybackReport(String event) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      final failed = event != 'open_ok';
      final lines = DiagTrail.lines;
      final tail = failed || lines.length <= 60
          ? lines
          : lines.sublist(lines.length - 60);
      var device = deviceSummary();
      if (device.length > 600) device = device.substring(0, 600);
      final body = <String, Object?>{
        'deviceId': deviceId,
        'event': event,
        'contentType': _contentType,
        'streamId': widget.id,
        'code': failed ? _clip(playbackErrorCode(), 300) : null,
        'message': failed ? _clip(_error, 300) : null,
        'engine': _nativePlayer != null ? 'native' : 'mpv',
        'elapsedMs': _diag?.msSinceTap(),
        'app': await appVersionLabel(),
        'device': device,
        'lines': tail,
      };
      await ref
          .read(mediaRepositoryProvider)
          .reportPlayback(body)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Reporting must never affect playback.
    }
  }

  Future<bool> _openNetwork(
    String url, {
    String label = 'Network',
    bool forceNative = false,
  }) {
    return _enqueueOpen((gen) => _openNetworkNow(
          url,
          label: label,
          gen: gen,
          forceNative: forceNative,
        ));
  }

  /// One open on the Android ExoPlayer engine after the MPV open failed, for
  /// failures another engine can plausibly get past (decoder, container,
  /// open/network errors, timeouts). Never for server answers that would be
  /// the same on any engine (401/403, 404, connection limit, 5xx).
  Future<bool> _shouldTryNativeFallback(AppFailureKind? kind) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    if (kind == null) return false;
    switch (kind) {
      case AppFailureKind.authorization:
      case AppFailureKind.notFound:
      case AppFailureKind.connectionLimit:
      case AppFailureKind.upstream:
        return false;
      default:
        break;
    }
    // Already on the native engine: nothing to fall back to.
    return !await AppDecoderPreferences.nativeEngine(tv: false);
  }

  Future<bool> _openNetworkNow(
    String url, {
    required String label,
    required int gen,
    bool forceNative = false,
  }) async {
    if (!mounted || gen != _openGen) return false;
    _openCancelled = Completer<void>();
    _stallWatchdog?.cancel();
    _pb.stopWatchdog();
    _seekEpoch++;
    _seekInFlight = false;
    _ready = false;
    _progressTimer?.cancel();
    _progressTimer = null;
    _trackPrefsApplied = false;
    _audioTracks = const [];
    _subtitleTracks = const [];
    _videoTracks = const [];
    _audioTrack = null;
    _subtitleTrack = null;
    _videoTrack = null;
    String? openError;
    AppOpenFailureMonitor? monitor;
    final timeline = AppStartupTimeline();
    _activePlayUrl = url;
    _lastOpenFailureKind = null;
    _midPlayFailureKind = null;
    final openStarted = DateTime.now();
    int msSinceOpen() => DateTime.now().difference(openStarted).inMilliseconds;
    _diag ??= PlaybackDiagSession();
    try {
      final nativeSelected = defaultTargetPlatform == TargetPlatform.android &&
          (forceNative ||
              await AppDecoderPreferences.nativeEngine(tv: false));
      if (!mounted || gen != _openGen) return false;
      if (nativeSelected) return await _openNativeNetwork(url, gen: gen);
      final decoderMode = await AppDecoderPreferences.load(tv: false);
      _decoderMode = decoderMode;
      if (!mounted || gen != _openGen) return false;
      // Reuse single player instance per session (brief §1.3).
      var player = _player;
      var video = _video;
      if (player == null || video == null) {
        final tier = DeviceCapabilitiesStore.instance.mpv;
        player = Player(configuration: appPlayerConfiguration(tier: tier));
        video = VideoController(
          player,
          configuration: VideoControllerConfiguration(
            vo: decoderMode.videoOutputFor(
              android: defaultTargetPlatform == TargetPlatform.android),
            hwdec: decoderMode.mpvValueFor(
              android: defaultTargetPlatform == TargetPlatform.android),
            androidAttachSurfaceAfterVideoParameters: false,
          ),
        );
        _player = player;
        _video = video;
        _stats.attachMpv(player);
        _surfaceMounted = true;
        if (mounted) setState(() {});
      }
      for (final s in List<StreamSubscription<dynamic>>.of(_subs)) {
        await s.cancel();
      }
      _subs.clear();

      _diag!.pb(
        'open reuse player=${identityHashCode(player)} '
        'video=${identityHashCode(video)} gen=$gen label=$label',
      );
      final openedPlayer = player;
      final failureMonitor = AppOpenFailureMonitor(
        onEvidence: (f) => _diag?.pb('MPV_FAILURE_EVIDENCE $f'),
        onFailureAfterStart: (f) => _onFailureAfterStart(openedPlayer, f),
      );
      monitor = failureMonitor;
      _failureMonitor?.close();
      _failureMonitor = failureMonitor;
      _subs.add(
        player.stream.log.listen((l) {
          // Configured at warn level: only warnings/errors reach here.
          DiagTrail.add('MPV', '${l.level} ${l.prefix}: ${l.text.trim()}');
          failureMonitor.add(l.prefix, l.level, l.text);
        }),
      );
      _subs.add(
        player.stream.error.listen((e) {
          if (e.trim().isNotEmpty) {
            openError = e;
            DiagTrail.add('MPV-ERROR', e.trim());
          }
        }),
      );
      _subs.add(
        player.stream.completed.listen((done) {
          if (done) _onPlaybackCompleted(openedPlayer);
        }),
      );
      _wirePlayer(player);
      // Make controller setup explicit so tuning is not timed against it.
      await _awaitOpenStep(video.platform.future.then((_) {}));
      timeline.mark('videoController');
      if (!mounted || gen != _openGen) return false;
      final tier = DeviceCapabilitiesStore.instance.mpv;
      await applyAppMpvTuning(
        player,
        tier: tier,
        sessionId: _diag!.sid,
        resumeStartSec: _resumeStartSec,
        decoderMode: decoderMode,
      );
      if (_isLivePlayback && tier.tier != DeviceTier.low) {
        // Live rewind window: ~1.5 min (mid) / ~3 min (high) at 5 Mbit/s.
        await appMpvSet(
          player,
          'demuxer-max-back-bytes',
          '${tier.tier == DeviceTier.high ? 128 * 1024 * 1024 : 64 * 1024 * 1024}',
        );
      }

      // Let Video surface attach before open (avoids decoder create→recreate).
      await _awaitOpenStep(WidgetsBinding.instance.endOfFrame);
      if (!mounted || gen != _openGen) return false;

      final start = (_resumeStartSec != null && _resumeStartSec! > 5)
          ? Duration(seconds: _resumeStartSec!)
          : null;
      _pb.setPhase(PlaybackPhase.openingMedia);
      await _awaitOpenStep(
        player.open(
          Media(url, httpHeaders: _httpHeaders, start: start),
          play: false,
        ),
      );
      timeline.mark('openCommand');
      _diag!.pb(
        'Media.open done +${msSinceOpen()}ms start=${start?.inSeconds ?? 0}',
      );
      if (!mounted || gen != _openGen) return false;
      await player.setVolume(_volume * 100);
      await player.setRate(_speed);
      _pb.setPhase(PlaybackPhase.initialBuffering);
      if (!mounted || gen != _openGen) return false;
      _syncTracksFromPlayer(player);
      // Prefetch demuxer cache + first frame before audible play so audio
      // does not run ahead of video on cold open.
      await waitForAppPlaybackBuffer(
        player,
        minDemuxerCache: const Duration(milliseconds: 1800),
      );
      if (!mounted || gen != _openGen) return false;
      await player.play();
      if (!mounted || gen != _openGen) return false;
      // No mpv playlist looping. Episode prev/next uses catalog playlist
      // state; EOF is handled by _onPlaybackCompleted with bounded recovery.
      await player.setPlaylistMode(PlaylistMode.none);
      await _waitWhileLoading(
        player,
        _waitUntilReady(player,
          requireSurfaceDecoder:
              decoderMode == AppDecoderMode.androidSurface,
          failure: failureMonitor.fatalBeforeFirstFrame,
        ),
      );
      failureMonitor.markFirstFrame();
      timeline.mark('videoParams');
      // The resume point opened at a keyframe (fast start); seeks the user
      // makes from here on land on the exact second again.
      unawaited(appMpvSet(player, 'hr-seek', 'default'));
      if (!mounted || gen != _openGen) return false;
      _diag!.pb(
        'VIDEO_OUTPUT_READY +${_diag!.msSinceTap()} '
        'openMs=+${msSinceOpen()}ms '
        'w=${player.state.width} dur=${player.state.duration.inSeconds}s',
      );
      _pb.setPhase(PlaybackPhase.playing);
      unawaited(_enablePip(player.state.width, player.state.height));
      if (!mounted || gen != _openGen) return false;
      if (openError != null &&
          openError!.trim().isNotEmpty &&
          (player.state.width ?? 0) <= 0 &&
          !player.state.playing) {
        // Raw mpv text can contain the source URL; keep only the category.
        throw AppPlaybackFailure(
          failureMonitor.lastKind ?? AppFailureKind.openFailed,
          httpStatus: failureMonitor.lastHttpStatus,
        );
      }
      setState(() {
        _ready = true;
        _playing = true;
        _failed = false;
        _decoderLimited = false;
        _hdAlternative = null;
        _sourceLabelKey = label;
        _error = null;
        _position = player!.state.position;
        _duration = player.state.duration;
        _resumeSeekDone = false;
      });
      _positionN.value = player.state.position;
      _durationN.value = player.state.duration;
      _ensureProgressTimer();
      unawaited(logAppDecoderDetails(player,
        isCurrent: () => mounted && gen == _openGen && identical(_player, player)));
      _diag!.startPerf(player);
      _startStallWatchdog(player);
      _reportStartup(player, timeline, gen);
      // Fallback seek only if Media.start was not honored (brief §1.2).
      if (start != null) {
        unawaited(_verifyResumeStart(start));
      } else {
        unawaited(_seekToSavedProgress());
      }
      return true;
    } on AppSurfaceDecoderFailure {
      _diag?.pb('ERROR code=SURFACE_DECODER_FAILED');
      // End audio and release the failed native output before exposing Retry.
      if (!mounted || gen != _openGen) return false;
      await _disposePlayer();
      if (!mounted || gen != _openGen) return false;
      try {
        await AppDecoderPreferences.save(AppDecoderMode.auto, tv: false);
      } catch (_) {
        _diag?.pb('Surface failure: could not save Auto preference');
      }
      if (mounted && gen == _openGen) {
        setState(() {
          _ready = false;
          _playing = false;
          _failed = true;
          _buffering = false;
          _error = 'Hardware video failed. Select Auto in playback settings and retry.';
        });
        _pb.setError(_error!);
      }
      return false;
    } on AppPlaybackFailure catch (e) {
      if (gen == _openGen) await _disposePlayer();
      _lastOpenFailureKind = e.kind;
      _diag?.pb(
        'ERROR code=OPEN_FAILED kind=${e.kind.name} '
        'http=${e.httpStatus ?? '-'} +${msSinceOpen()}ms ${timeline.line}',
      );
      if (mounted && gen == _openGen) {
        _error = appFailureMessage(e.kind);
        _pb.setError(_error!);
      }
      // Pin the refusal to a server: gateway or the media server it
      // redirects to. Host/port/status only.
      if (e.httpStatus != null || e.kind == AppFailureKind.openFailed) {
        try {
          final hops = await probeMediaRedirectChain(url, headers: _httpHeaders);
          _diag?.pb('MEDIA_TRACE ${hops.isEmpty ? 'none' : hops.join(' -> ')}');
        } catch (_) {
          _diag?.pb('MEDIA_TRACE failed');
        }
      }
      return false;
    } on TimeoutException catch (e) {
      if (gen == _openGen) await _disposePlayer();
      _lastOpenFailureKind = monitor?.lastKind ?? AppFailureKind.timeout;
      _diag?.pb(
        'ERROR code=OPEN_TIMEOUT phase=openingMedia '
        'evidence=${monitor?.lastKind?.name ?? 'none'} ${timeline.line}',
      );
      Diag.err('network timeout', e);
      if (mounted && gen == _openGen) {
        _pb.setError('Playback timed out. Tap Retry.');
        _error = userFacingPlaybackError(e);
      }
      return false;
    } catch (e, st) {
      if (gen == _openGen) await _disposePlayer();
      _lastOpenFailureKind = monitor?.lastKind ?? AppFailureKind.openFailed;
      _diag?.pb(
        'ERROR code=OPEN_FAILED phase=openingMedia '
        'evidence=${monitor?.lastKind?.name ?? 'none'} ${timeline.line}',
      );
      Diag.err('network failed', e, st);
      if (mounted && gen == _openGen) {
        _pb.setError(userFacingPlaybackError(e));
        _error = userFacingPlaybackError(e);
      }
      return false;
    }
  }

  void _onFailureAfterStart(Player player, AppMpvLogFailure failure) {
    if (!mounted || _leaving || _failed || !identical(_player, player)) return;
    final status = failure.httpStatus;
    final kind = status != null ? kindForHttpStatus(status) : failure.kind;
    _midPlayFailureKind = kind;
    // A failed reload means mpv gave up on the source. Otherwise EOF or the
    // stall watchdog follows and uses this classification.
    if (failure.fatal) unawaited(_recoverOrFail(player, kind, 'reloadFailed'));
  }

  void _onPlaybackCompleted(Player player) {
    if (!mounted ||
        _leaving ||
        _failed ||
        !_ready ||
        !identical(_player, player)) {
      return;
    }
    final pos = player.state.position;
    final dur = player.state.duration;
    if (isPrematureEof(position: pos, duration: dur, live: _isLivePlayback)) {
      final kind = _midPlayFailureKind ?? AppFailureKind.prematureEof;
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          (_inBackground || _nearPictureSwitch)) {
        unawaited(_checkEofNearPictureSwitch(player, kind));
        return;
      }
      unawaited(_recoverOrFail(player, kind, 'eof'));
      return;
    }
    _diag?.pb('PLAYBACK_COMPLETED pos=${pos.inSeconds}s dur=${dur.inSeconds}s');
    unawaited(_persistProgress(force: true));
    _armAutoNext();
  }

  bool get _hasNextEpisode =>
      _isEpisode && _episodeIndex + 1 < _episodePlaylist.length;

  void _armAutoNext() {
    _autoNext?.cancel();
    if (!_hasNextEpisode || !ref.read(sessionProvider).autoplay) return;
    final copy = _copy;
    _autoNext = Timer(_autoNextDelay, () {
      if (!mounted || _leaving) return;
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      _nextEpisode();
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        duration: _autoNextDelay,
        content: Text(copy.nextEpisodeIn(_autoNextDelay.inSeconds)),
        action: SnackBarAction(
          label: copy.cancel,
          onPressed: () {
            _autoNext?.cancel();
            _autoNext = null;
          },
        ),
      ),
    );
  }

  /// Bounded recovery: reopens the same backend-issued URL on the existing
  /// player while the lease is active, at most [AppRecoveryBudget.maxAttempts]
  /// times until playback has been healthy again. Otherwise shows Retry.
  Future<void> _recoverOrFail(
    Player player,
    AppFailureKind kind,
    String reason,
  ) async {
    if (!mounted ||
        _leaving ||
        _failed ||
        _recovering ||
        !identical(_player, player)) {
      return;
    }
    // iPhone: no reopen while the app is away; it never completes there
    // (12 Nov log: 28 s, then a timeout). Recover when the app returns.
    if (defaultTargetPlatform == TargetPlatform.iOS && _inBackground) {
      _recoverOnResume = kind;
      _diag?.pb('RECOVERY waits for return kind=${kind.name} reason=$reason');
      return;
    }
    final url = _activePlayUrl;
    final lease = _lease;
    final authorized = lease == null ? _playbackId == null : lease.isActive;
    if (url == null || !authorized || !_recovery.tryConsume(kind)) {
      _diag?.pb(
        'RECOVERY skipped kind=${kind.name} reason=$reason '
        'used=${_recovery.used} authorized=$authorized',
      );
      await _failActivePlayback(player, kind: kind);
      return;
    }
    _recovering = true;
    final pos = player.state.position;
    if (_isLivePlayback) {
      _resumeStartSec = null;
    } else if (pos.inSeconds > 5) {
      _resumeStartSec = pos.inSeconds;
    }
    final delay = recoveryDelayFor(kind);
    _diag?.pb(
      'RECOVERY attempt=${_recovery.used}/${_recovery.maxAttempts} '
      'kind=${kind.name} reason=$reason pos=${pos.inSeconds}s '
      'delayMs=${delay.inMilliseconds}',
    );
    _stallWatchdog?.cancel();
    _midPlayFailureKind = null;
    setState(() {
      _ready = false;
      _buffering = true;
    });
    _pb.setPhase(PlaybackPhase.rebuffering);
    try {
      await Future<void>.delayed(delay);
      if (!mounted || _leaving || _failed || !identical(_player, player)) {
        return;
      }
      final ok = await _openNetwork(url, label: _sourceLabelKey);
      if (ok) {
        _diag?.pb('RECOVERY ok attempt=${_recovery.used}');
      } else if (mounted && !_leaving && !_failed) {
        final failedKind = _lastOpenFailureKind ?? kind;
        if (_hostFailoverBudget > 0) {
          _hostFailoverBudget--;
          _diag?.pb(
            'RECOVERY same-url failed; HOST_FAILOVER via re-init '
            'left=$_hostFailoverBudget kind=${failedKind.name}',
          );
          await _persistProgress(force: true);
          _failoverResumeSec = _isLivePlayback ? null : _resumeStartSec;
          await _stopLease();
          _recovering = false;
          if (mounted && !_leaving) unawaited(_init());
          return;
        }
        _diag?.pb('RECOVERY failed kind=${failedKind.name}');
        setState(() {
          _ready = false;
          _failed = true;
          _playing = false;
          _buffering = false;
          _error = appFailureMessage(failedKind);
        });
        _pb.setError(_error!);
        await _stopLease();
      }
    } finally {
      _recovering = false;
    }
  }

  /// Startup timeline (time to first frame) and a video-output check, which
  /// distinguishes "video params known" from frames actually advancing.
  void _reportStartup(Player player, AppStartupTimeline timeline, int gen) {
    final diag = _diag;
    if (diag == null) return;
    final readyPos = player.state.position;
    bool current() =>
        mounted && !_leaving && gen == _openGen && identical(_player, player);
    unawaited(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (current() && DateTime.now().isBefore(deadline)) {
        if (player.state.playing &&
            !player.state.buffering &&
            player.state.position - readyPos >=
                const Duration(milliseconds: 300)) {
          timeline.mark('firstAdvance');
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!current()) return;
      diag.pb(
        'TTFF ${timeline.line} sinceTap=${diag.msSinceTap()}ms'
        '${timeline['firstAdvance'] == null ? ' firstAdvance=none' : ''}',
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!current()) return;
      await logAppVideoOutputCheck(
        player,
        sessionId: diag.sid,
        positionAtReady: readyPos,
        isCurrent: current,
      );
    }());
  }

  Future<bool> _openNativeNetwork(String url, {required int gen}) async {
    if (_nativePlayer != null || _player != null) await _disposePlayer();
    if (!mounted || gen != _openGen) return false;
    _resumeSeekDone = false;
    final controller = native_video.VideoPlayerController.networkUrl(
      Uri.parse(url), httpHeaders: _httpHeaders,
      // Without this the plugin pauses ExoPlayer whenever the app leaves the
      // screen, so the sound stopped in the background on channels that had
      // fallen back to this engine (client 21 Oct mobile #6).
      videoPlayerOptions:
          native_video.VideoPlayerOptions(allowBackgroundPlayback: true),
    );
    _nativePlayer = controller;
    _stats.attachNative();
    _diag?.pb('NATIVE_ENGINE_OPEN');
    await controller.initialize().timeout(const Duration(seconds: 30));
    if (!mounted || gen != _openGen || !identical(_nativePlayer, controller)) return false;
    if (controller.value.size.width <= 0 || controller.value.size.height <= 0) {
      throw StateError('Android player could not initialize video');
    }
    if (!mounted || gen != _openGen) return false;
    final start = _resumeStartSec;
    if (start != null && start > 5) await controller.seekTo(Duration(seconds: start));
    if (!mounted || gen != _openGen) return false;
    await controller.setVolume(_volume);
    await controller.setPlaybackSpeed(_speed);
    controller.addListener(() {
      if (!mounted || gen != _openGen || !identical(_nativePlayer, controller)) {
        return;
      }
      final value = controller.value;
      _stats
        ..reportBuffering(value.isBuffering, playing: value.isPlaying)
        ..reportNativeSize(value.size.width.round(), value.size.height.round());
      if (value.hasError && !_failed) {
        _diag?.pb(
          'ERROR code=NATIVE_ENGINE_FAILED ${value.errorDescription ?? ''}',
        );
        setState(() {
          _failed = true;
          _ready = false;
          _error = 'Android playback failed. Try the default player.';
        });
        unawaited(_disposePlayer());
        unawaited(_stopLease());
        return;
      }
      final playingChanged = value.isPlaying != _playing;
      final bufferingChanged = value.isBuffering != _buffering;
      _position = value.position;
      _duration = value.duration;
      _playing = value.isPlaying;
      _buffering = value.isBuffering;
      _lease?.onPausedChanged(!value.isPlaying);
      _syncLiveEdgeFromClock();
      if (!value.isBuffering &&
          value.isPlaying &&
          value.position > Duration(seconds: start ?? 0)) {
        _resumeSeekDone = true;
      }
      // Android native engine: no completed stream, so detect the end here.
      final dur = value.duration;
      if (!_nativeEnded &&
          !_isLivePlayback &&
          dur > Duration.zero &&
          value.position >= dur - const Duration(milliseconds: 400) &&
          !value.isPlaying) {
        _nativeEnded = true;
        _diag?.pb('PLAYBACK_COMPLETED pos=${value.position.inSeconds}s '
            'dur=${dur.inSeconds}s engine=native');
        unawaited(_persistProgress(force: true));
        _armAutoNext();
      } else if (value.isPlaying) {
        _nativeEnded = false;
      }
      final now = DateTime.now();
      if (playingChanged ||
          bufferingChanged ||
          _lastPosUi == null ||
          now.difference(_lastPosUi!) >= const Duration(milliseconds: 250)) {
        _lastPosUi = now;
        if (mounted && (showControls || playingChanged || bufferingChanged)) {
          setState(() {});
        }
      }
    });
    await controller.play();
    if (!mounted || gen != _openGen) return false;
    setState(() {
      _ready = true;
      _failed = false;
      _error = null;
      _playing = true;
      _surfaceMounted = true;
    });
    _pb.setPhase(PlaybackPhase.playing);
    _ensureProgressTimer();
    unawaited(() async {
      if (!mounted || gen != _openGen || !identical(_nativePlayer, controller)) return;
      try {
        final caps = await const MethodChannel('app/device').invokeMethod<Object>(
          'getDecoderDiagnostics', {
            'width': controller.value.size.width.toInt(),
            'height': controller.value.size.height.toInt(),
            'fps': 30.0,
          }).timeout(const Duration(seconds: 3));
        if (!mounted || gen != _openGen || !identical(_nativePlayer, controller)) return;
        _diag?.pb('NATIVE_ADVERTISED_HEVC_CAPS assumedFps=30 $caps');
      } catch (_) { _diag?.pb('NATIVE_ADVERTISED_HEVC_CAPS unavailable'); }
    }());
    _diag?.pb('NATIVE_ENGINE_INITIALIZED size=${controller.value.size.width}x${controller.value.size.height}');
    unawaited(_enablePip(
      controller.value.size.width.toInt(),
      controller.value.size.height.toInt(),
    ));
    return true;
  }

  Future<void> _verifyResumeStart(Duration expected) async {
    final player = _player;
    if (player == null || !mounted || _leaving) return;
    final epoch = _seekEpoch;
    final confirmed = await confirmAppPlaybackPosition(
      player,
      expected,
      isCurrent: () =>
          mounted &&
          !_leaving &&
          identical(_player, player) &&
          epoch == _seekEpoch,
      timeout: const Duration(seconds: 12),
    );
    if (!mounted ||
        _leaving ||
        !identical(_player, player) ||
        epoch != _seekEpoch)
      return;
    if (confirmed) {
      _resumeSeekDone = true;
      return;
    }
    // A stationary clock near the target or an active buffer is not evidence
    // that Media.start was ignored. Re-seeking here restarts demux/decoding.
    final distance = (player.state.position - expected).inMilliseconds.abs();
    if (player.state.buffering || distance <= 5000 || _failed) {
      _diag?.pb('resume pending; duplicate seek suppressed');
      final settled = await confirmAppPlaybackPosition(
        player,
        expected,
        isCurrent: () => mounted && !_leaving && !_failed &&
            identical(_player, player) && epoch == _seekEpoch,
        timeout: const Duration(seconds: 15),
      );
      if (mounted && !_leaving && identical(_player, player) &&
          epoch == _seekEpoch && settled) _resumeSeekDone = true;
      return;
    }
    final sought = await _seekSafely(expected);
    if (!mounted || _leaving || !identical(_player, player)) return;
    _resumeSeekDone = sought;
    if (!sought && !_failed)
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(_copy.resumeUnconfirmed)));
  }

  Future<void> _seekToSavedProgress() async {
    final player = _player;
    if (player == null || _isLivePlayback) {
      _resumeSeekDone = true;
      return;
    }

    final resumeEpoch = _seekEpoch;
    final resumeStarted = DateTime.now();
    int msResume() => DateTime.now().difference(resumeStarted).inMilliseconds;

    var targetSec = widget.startSec;
    if (targetSec == null || targetSec <= 0) {
      targetSec = ref.read(libraryProvider).resumePositionSecFor(widget.id);
    }
    final hasAbsolute = targetSec != null && targetSec > 5;

    // Progressive MKV often reports duration=0 until demux catches up.
    // Absolute resume does not need duration; only wait briefly to near-end clamp.
    var dur = player.state.duration;
    if (dur.inMilliseconds <= 0) {
      try {
        dur = await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(Duration(seconds: hasAbsolute ? 2 : 4));
        debugPrint(
          '[Playback] time-to-duration-known +${msResume()}ms '
          'dur=${dur.inSeconds}s',
        );
      } catch (_) {
        debugPrint(
          '[Playback] duration still unknown +${msResume()}ms '
          '(hasAbsolute=$hasAbsolute)',
        );
        if (!hasAbsolute) {
          if (!mounted ||
              !identical(player, _player) ||
              resumeEpoch != _seekEpoch)
            return;
          _resumeSeekDone = true;
          return;
        }
      }
    } else {
      debugPrint(
        '[Playback] time-to-duration-known +${msResume()}ms '
        'dur=${dur.inSeconds}s (immediate)',
      );
    }

    if (!mounted ||
        _leaving ||
        !identical(player, _player) ||
        resumeEpoch != _seekEpoch)
      return;

    if (!hasAbsolute) {
      final p = ref.read(libraryProvider).progressFor(widget.id);
      if (p > 0.05 && p < 0.95 && dur.inSeconds > 0) {
        targetSec = (dur.inSeconds * p).round();
      }
    }

    if (targetSec == null || targetSec <= 5) {
      _resumeSeekDone = true;
      return;
    }
    if (dur.inSeconds > 0 && targetSec >= dur.inSeconds - 5) {
      _resumeSeekDone = true;
      return;
    }

    if (!mounted || !identical(player, _player) || _leaving) return;
    final confirmed = await _seekSafely(Duration(seconds: targetSec));
    if (!mounted || !identical(player, _player) || _leaving) return;
    // Preserve the old bookmark if the requested position was not confirmed.
    _resumeSeekDone = confirmed;
    if (!confirmed && !_failed && !_leaving) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(_copy.resumeUnconfirmed)));
    }
    debugPrint(
      '[Playback] resume confirmed=$confirmed '
      'target=${targetSec}s actual=${player.state.position.inSeconds}s',
    );
  }

  Future<bool> _seekSafely(Duration target) async {
    if (_leaving || _failed || _seekInFlight) return false;
    final native = _nativePlayer;
    if (native != null) {
      final epoch = ++_seekEpoch;
      _seekInFlight = true;
      _lastPlaybackAdvance = DateTime.now();
      try {
        await native.seekTo(target);
        if (mounted &&
            epoch == _seekEpoch &&
            identical(_nativePlayer, native)) {
          setState(() => _position = native.value.position);
          _resumeSeekDone = true;
        }
        return true;
      } catch (_) {
        debugPrint('[Playback] native seek failed');
        return false;
      } finally {
        if (epoch == _seekEpoch) {
          _seekInFlight = false;
          _lastPlaybackAdvance = DateTime.now();
        }
      }
    }
    final player = _player;
    if (player == null) return false;
    final epoch = ++_seekEpoch;
    _seekInFlight = true;
    _lastPlaybackAdvance = DateTime.now();
    try {
      final confirmed = await seekAppPlayback(
        player,
        target,
        isCurrent: () =>
            mounted &&
            !_leaving &&
            epoch == _seekEpoch &&
            identical(_player, player),
      );
      if (mounted && epoch == _seekEpoch && identical(_player, player)) {
        setState(() => _position = player.state.position);
        if (confirmed) _resumeSeekDone = true;
      }
      return confirmed;
    } catch (_) {
      debugPrint('[Playback] seek command failed');
      return false;
    } finally {
      if (epoch == _seekEpoch) {
        _seekInFlight = false;
        _lastPlaybackAdvance = DateTime.now();
      }
    }
  }

  Future<List<int>> _seasonsOf(CatalogRepository catalog, String seriesId) async {
    final nums = await catalog.getSeasonNumbers(seriesId);
    return nums.isEmpty ? const [1] : nums;
  }

  Future<Episode?> _episodeInSeries(
    CatalogRepository catalog,
    String seriesId,
    String episodeId,
  ) async {
    // Provider season numbers, not 1..count: a series may have [1, 3].
    for (final season in await _seasonsOf(catalog, seriesId)) {
      final eps = await catalog.getEpisodes(seriesId, season: season);
      for (final ep in eps) {
        if (ep.id == episodeId) return ep;
      }
    }
    return null;
  }

  Future<void> _loadEpisodePlaylist(
    CatalogRepository catalog,
    String seriesId,
    String episodeId,
  ) async {
    final all = <Episode>[];
    for (final season in await _seasonsOf(catalog, seriesId)) {
      all.addAll(await catalog.getEpisodes(seriesId, season: season));
    }
    if (!mounted) return;
    final idx = all.indexWhere((e) => e.id == episodeId);
    setState(() {
      _episodePlaylist = all;
      _episodeIndex = idx;
      _resolvedSeriesId = seriesId;
    });
  }

  /// What Continue Watching saves: an episode keeps its own still when the
  /// provider has one (client 20 Oct I5), else the series poster.
  MediaItem _progressItem(MediaItem m) {
    if (m.kind != MediaKind.series) return m;
    String? still;
    for (final e in _episodePlaylist) {
      if (e.id == m.id) {
        still = e.stillUrl;
        break;
      }
    }
    if (still == null || still.isEmpty) return m;
    return MediaItem(
      id: m.id,
      title: m.title,
      kind: m.kind,
      posterUrl: still,
      backdropUrl: m.backdropUrl,
      synopsis: m.synopsis,
      containerExtension: m.containerExtension,
      seriesId: m.seriesId,
    );
  }

  Future<void> _persistProgress({
    bool force = false,
    bool refreshRemote = false,
  }) async {
    // Never write a cold-start position over a known resume point.
    if (!_resumeSeekDone) return;
    // Live must not pollute Continue Watching.
    if (_isLivePlayback) return;
    if (_progressSaveInFlight) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && !refreshRemote && now - _lastProgressPersistMs < 20000) {
      return;
    }
    final player = _player;
    final item = _media;
    final lib = _library;
    if ((player == null && _nativePlayer == null) || !_ready || item == null || lib == null) return;
    final durMs = (_nativePlayer?.value.duration ?? player!.state.duration).inMilliseconds;
    if (durMs <= 0) return;
    final posMs = (_nativePlayer?.value.position ?? player!.state.position).inMilliseconds;
    final p = posMs / durMs;
    _lastProgressPersistMs = now;
    _progressSaveInFlight = true;
    try {
      await lib.setProgress(
        item.id,
        p,
        item: _progressItem(item),
        positionSec: (posMs / 1000).round(),
        durationSec: (durMs / 1000).round(),
        refreshRemote: false,
      );
    } catch (_) {
    } finally {
      _progressSaveInFlight = false;
    }
  }

  Future<void> _togglePlay() async {
    final native = _nativePlayer;
    if (native != null) {
      if (native.value.isPlaying) {
        _userPaused = true;
        await native.pause();
        setState(() => _playing = false);
        await _persistProgress(force: true);
      } else {
        _userPaused = false;
        _lastPlaybackAdvance = DateTime.now();
        await native.play();
        setState(() => _playing = true);
      }
      return;
    }
    final player = _player;
    if (player == null) return;
    if (player.state.playing) {
      _userPaused = true;
      await player.pause();
      setState(() => _playing = false);
      await _persistProgress(force: true);
    } else {
      _userPaused = false;
      _lastPlaybackAdvance = DateTime.now();
      await player.play();
      setState(() => _playing = true);
    }
  }

  Future<void> _seekBy(Duration delta) async {
    if (!_ready) return;
    if (_isLivePlayback && !_liveSeekable) {
      // Live with less than 10 s received so far: nothing to move into yet.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(_copy.liveSeekNotReady),
        ),
      );
      return;
    }
    final native = _nativePlayer;
    final player = _player;
    if (native == null && player == null) return;
    final now = native?.value.position ?? player!.state.position;
    final next = now + delta;
    final dur = native?.value.duration ?? player!.state.duration;
    if (_liveSeekable && player != null) {
      final from = _liveSeekTarget ?? now;
      // Back: as far as the buffer goes. Forward: up to live, and only what
      // has been received; past that, GO LIVE reconnects.
      final lo = now - _liveRaw.behind;
      final room = _liveRaw.ahead - const Duration(seconds: 2);
      var hi = now + (room > Duration.zero ? room : Duration.zero);
      final live = from + _liveDelay;
      if (live < hi) hi = live;
      var target = from + delta;
      if (target < lo) target = lo;
      if (target > hi) {
        if (delta > Duration.zero && _liveDelay > Duration.zero &&
            target >= live) {
          await _reconnectLive();
          return;
        }
        target = hi;
      }
      final moved = target - from;
      if (moved == Duration.zero) return;
      final delay = _liveDelay - moved;
      _diag?.pb('LIVE_SEEK ${now.inSeconds}s -> ${target.inSeconds}s '
          'behindLive=${delay.inSeconds}s buffered=${_liveRaw.ahead.inSeconds}s');
      setState(() {
        _liveSeeking = true;
        _liveSeekTarget = target;
        _liveDelay = delay > Duration.zero ? delay : Duration.zero;
        _liveWin = LiveSeekWindow(
          behind: _liveWin.behind + moved,
          ahead: _liveDelay,
        );
        _userBehindLive = !_liveWin.atEdge;
      });
      try {
        if (!_liveExactSeek) {
          // Keyframe seeks landed up to 15 s early on live (emulator 21 Oct:
          // asked 26 s, got 11.6 s); decode to the exact second instead.
          _liveExactSeek = true;
          await appMpvSet(player, 'hr-seek', 'yes');
        }
        // Plain seek: live needs no resume confirmation, and a 2 s confirm
        // swallowed quick repeated taps.
        await player.seek(target).timeout(const Duration(seconds: 6));
      } catch (_) {
        _diag?.pb('LIVE_SEEK failed');
      }
      if (!mounted) return;
      if (_liveSeekTarget == target) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (!mounted || _liveSeekTarget != target) return;
        setState(() {
          _liveSeeking = false;
          _liveSeekTarget = null;
          _position = player.state.position;
        });
      }
      return;
    }
    final clamped = next < Duration.zero
        ? Duration.zero
        : (dur > Duration.zero && next > dur ? dur : next);
    await _seekSafely(clamped);
    if (!_isLivePlayback || !mounted) return;
    setState(() {
      _userBehindLive =
          dur > Duration.zero && clamped < dur - _liveEdgeTolerance;
    });
  }

  Future<void> _loadDefaultSpeed() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getDouble(kDefaultPlaybackSpeedKey);
      if (v != null && v != 1.0 && mounted) await _setSpeed(v);
    } catch (_) {}
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await _nativePlayer?.setPlaybackSpeed(speed);
    await _player?.setRate(speed);
  }

  Future<void> _setVolume(double v) async {
    final next = v.clamp(0.0, 1.0);
    setState(() {
      _volume = next;
      if (next > 0) _volumeBeforeMute = next;
    });
    await _nativePlayer?.setVolume(next);
    await _player?.setVolume(next * 100);
    _scheduleHideVolume();
  }

  Future<void> _toggleMute() async {
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      await _setVolume(0);
    } else {
      await _setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 1);
    }
  }

  void _openVolumeSlider() {
    setState(() => _showVolumeSlider = !_showVolumeSlider);
    if (_showVolumeSlider) _scheduleHideVolume();
  }

  void _scheduleHideVolume() {
    _hideVolume?.cancel();
    _hideVolume = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showVolumeSlider = false);
    });
  }

  void _armControlsHide() {
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 4), () {
      if (!mounted || _leaving) return;
      _enterImmersive();
      setState(() {
        showControls = false;
        _showVolumeSlider = false;
      });
    });
  }

  static const _deviceChannel = MethodChannel('app/device');

  void _playbackService(bool on) {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    unawaited(() async {
      try {
        await _deviceChannel.invokeMethod<bool>(
          on ? 'playbackServiceStart' : 'playbackServiceStop',
          on ? {'title': ''} : null,
        );
      } catch (_) {}
    }());
  }

  /// Full screen: no status bar (time, Wi-Fi, signal, battery) or navigation bar.
  void _enterImmersive() {
    if (_leaving) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Timer? _reHide;
  void _reHideSystemBars() {
    _reHide?.cancel();
    _reHide = Timer(const Duration(seconds: 2), () {
      if (mounted && !_leaving) _enterImmersive();
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Rotation / window change: Android may show the bars again.
    _reHideSystemBars();
  }

  /// Small window: video only, no controls (they cannot be used there).
  void _onPipChanged() {
    if (!mounted) return;
    _hideControls?.cancel();
    setState(() {
      showControls = false;
      _showVolumeSlider = false;
    });
    // iPhone PiP shows this same player (client 12 Nov), so the sound stays
    // on. PiP closed with its X while away: the picture goes off and the
    // sound continues, as before PiP.
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    final player = _player;
    if (AppPip.inPip.value) {
      _diag?.pb('PIP shown (iPhone)');
      _pushIosPipState();
    } else if (_inBackground && _pictureKeptForPip && player != null) {
      _diag?.pb('PIP closed while away; picture off');
      _pictureOffForBackground(player);
    }
  }

  /// iPhone PiP: our mpv player's picture goes into the system PiP window
  /// when the app is left (AppPip.swift). One connection, every format.
  /// The old handoff to a second, native player (Oct–Nov) opened a second
  /// connection on a one-connection line and could not play TS / MKV.
  Future<void> _enablePip(int? width, int? height) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final player = _player;
      if (player == null || _nativePlayer != null) {
        await AppPip.setAuto(false);
        return;
      }
      int? handle;
      try {
        handle = await player.handle;
      } catch (_) {}
      if (!mounted || _leaving || !identical(_player, player)) return;
      await AppPip.setAuto(true, mpvHandle: handle);
      _diag?.pb('PIP ${AppPip.iosArmed ? 'ready' : 'not available'} '
          '(iPhone)');
      _pushIosPipState();
      _iosPipStateTimer?.cancel();
      _iosPipStateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) _pushIosPipState();
      });
      return;
    }
    await AppPip.setAuto(
      true,
      width: width ?? 16,
      height: height ?? 9,
    );
  }

  Timer? _iosPipStateTimer;

  /// iPhone PiP window: play / pause button and time bar.
  void _pushIosPipState() {
    if (defaultTargetPlatform != TargetPlatform.iOS || !AppPip.iosArmed) {
      return;
    }
    final player = _player;
    if (player == null) return;
    unawaited(AppPip.iosState(
      playing: player.state.playing,
      position: player.state.position,
      duration: player.state.duration,
      live: _isLivePlayback,
    ));
  }

  /// iPhone PiP button (client 5 Nov): same player, shown in the PiP window.
  bool get _canIosPip =>
      defaultTargetPlatform == TargetPlatform.iOS &&
      _ready &&
      AppPip.iosArmed;

  Future<void> _startIosPip() async {
    _diag?.pb('PIP button (iPhone)');
    final ok = await AppPip.startIos();
    if (ok || !mounted) return;
    _diag?.pb('PIP could not start');
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(_copy.pipUnavailable)),
    );
  }

  /// Play / Pause pressed in the iPhone PiP window.
  void _onIosPipSetPlaying(bool play) {
    final player = _player;
    if (!mounted || player == null) return;
    if (player.state.playing == play) {
      _pushIosPipState();
      return;
    }
    _diag?.pb('PIP window ${play ? 'play' : 'pause'}');
    unawaited(_togglePlay().then((_) => _pushIosPipState()));
  }

  void _lock() {
    _hideControls?.cancel();
    setState(() {
      _locked = true;
      showControls = false;
      _showVolumeSlider = false;
    });
    _flashLockHint();
  }

  void _unlock() {
    _lockHintTimer?.cancel();
    setState(() {
      _locked = false;
      _lockHint = false;
    });
    _showControlsNow();
  }

  void _flashLockHint() {
    _lockHintTimer?.cancel();
    setState(() => _lockHint = true);
    _lockHintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _lockHint = false);
    });
  }

  /// Always reveals chrome immediately (never delays behind double-tap arena).
  void _showControlsNow() {
    if (!mounted || _locked) return;
    setState(() => showControls = true);
    _armControlsHide();
  }

  /// Manual double-tap: first tap shows controls now; quick second tap seeks.
  /// Avoids GestureDetector onDoubleTap (which delays onTap ~300ms).
  /// Control bars (client 24 Oct: Live TV buttons hard to tap). A press on
  /// a button also reached this tap-down, which hid the controls before the
  /// button's own tap landed; presses inside the bars are left to them.
  final _chromeTopKey = GlobalKey();
  final _chromeCenterKey = GlobalKey();
  final _chromeBottomKey = GlobalKey();

  bool _onChrome(Offset global) {
    if (!showControls) return false;
    for (final k in [_chromeTopKey, _chromeCenterKey, _chromeBottomKey]) {
      final box = k.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final rect = (box.localToGlobal(Offset.zero) & box.size).inflate(8);
      if (rect.contains(global)) return true;
    }
    return false;
  }

  /// Client 25 Oct (iPhone 17): "back does not work in full screen". In
  /// landscape the back arrow sits inside the safe area (~60 pt from the
  /// edge, beside the Dynamic Island); a tap in that strip reached the video
  /// and hid the controls instead. The strip beside the top bar now counts
  /// as the back button (right side in Arabic, where the bar is mirrored).
  bool _inBackInset(Offset global) {
    if (!showControls) return false;
    final box = _chromeTopKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    final r = box.localToGlobal(Offset.zero) & box.size;
    if (global.dy > r.bottom + 8) return false;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return rtl ? global.dx > r.right : global.dx < r.left;
  }

  /// Set on tap-down in [_inBackInset]; the leave dialog opens on tap-up.
  /// Opening it on tap-down let the same finger's tap-up land on the
  /// dialog's barrier and close it at once.
  bool _backTapPending = false;

  void _onPlayerTapUp(TapUpDetails _) {
    if (!_backTapPending) return;
    _backTapPending = false;
    unawaited(_requestLeave());
  }

  void _onPlayerTapDown(TapDownDetails d) {
    _backTapPending = false;
    if (_leaving) return;
    if (_inBackInset(d.globalPosition)) {
      _backTapPending = true;
      return;
    }
    if (_onChrome(d.globalPosition)) {
      _armControlsHide();
      return;
    }
    final now = DateTime.now();
    final lastAt = _lastTapAt;
    final lastPos = _lastTapPos;
    _lastTapAt = now;
    _lastTapPos = d.localPosition;

    // Live TV / Sports: no double-tap seek (client 23 Oct round 3 #1).
    final isDouble = !_isLivePlayback &&
        _ready &&
        lastAt != null &&
        lastPos != null &&
        now.difference(lastAt) < const Duration(milliseconds: 320) &&
        (d.localPosition - lastPos).distance < 96;

    if (isDouble) {
      _lastTapAt = null;
      unawaited(_seekFromTapPosition(d.localPosition));
      return;
    }
    // Tap toggles chrome (hide when visible) so controls are not stuck on.
    if (showControls) {
      _hideControls?.cancel();
      setState(() => showControls = false);
    } else {
      _showControlsNow();
    }
  }

  Future<void> _seekFromTapPosition(Offset local) async {
    // Physical left half = rewind always (YouTube-style), even in Arabic RTL.
    // Forcing this fixes reversed Arabic seek when Row auto-mirrors.
    final w = MediaQuery.sizeOf(context).width;
    final rewind = local.dx < w * 0.5;
    final delta = Duration(seconds: rewind ? -10 : 10);
    setState(() => _seekFlashSec = rewind ? -10 : 10);
    await _seekBy(delta);
    _showControlsNow();
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekFlashSec = null);
    });
  }

  /// Where the picture is drawn inside [box] (letterboxed, or the whole box
  /// when the video fills the screen).
  Rect _videoRect(Size box) {
    final native = _nativePlayer?.value.size;
    final w = native?.width ?? (_player?.state.width ?? 0).toDouble();
    final h = native?.height ?? (_player?.state.height ?? 0).toDouble();
    return _screenMode.videoRect(box, Size(w, h));
  }

  void _toggleOrientation() {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setPreferredOrientations(
      landscape
          ? const [DeviceOrientation.portraitUp]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
  }

  void _goEpisode(int delta) {
    if (!_isEpisode) return;
    final next = _episodeIndex + delta;
    if (next < 0 || next >= _episodePlaylist.length) return;
    final ep = _episodePlaylist[next];
    final series = _resolvedSeriesId ?? widget.seriesId ?? '';
    final q = series.isNotEmpty
        ? '?kind=series&seriesId=$series'
        : '?kind=series';
    context.pushReplacement('/player/${ep.id}$q');
  }

  /// The playing episode's season as a list; tap plays that episode
  /// through the normal lease path.
  Future<void> _showEpisodes() async {
    if (!_isEpisode) return;
    final current = _episodePlaylist[_episodeIndex];
    final copy = _copy;
    final entries = <int>[
      for (var i = 0; i < _episodePlaylist.length; i++)
        if (_episodePlaylist[i].season == current.season) i,
    ];
    await _showPlayerSheet<void>(
      keepVideoVisible: true,
      body: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              '${copy.seasonTab(current.season)}  ·  '
              '${copy.episodesCount(entries.length)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          for (final i in entries)
            ListTile(
              selected: i == _episodeIndex,
              selectedColor: AppColors.cyan,
              leading: SizedBox(
                width: 96,
                height: 54,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RemoteImage(
                      url: (_episodePlaylist[i].stillUrl ?? '').isNotEmpty
                          ? _episodePlaylist[i].stillUrl
                          : (_media?.backdropUrl ?? _media?.posterUrl),
                      fallbackUrl: _media?.backdropUrl ?? _media?.posterUrl,
                      borderRadius: BorderRadius.circular(8),
                      memCacheWidth: 192,
                    ),
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'E${_episodePlaylist[i].number}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              title: Text(
                _episodePlaylist[i].title.trim().isEmpty
                    ? 'S${_episodePlaylist[i].season} · E${_episodePlaylist[i].number}'
                    : _episodePlaylist[i].title.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: i == _episodeIndex
                  ? Text(copy.playerNowPlaying)
                  : (_episodePlaylist[i].durationLabel.isEmpty
                      ? null
                      : Text(_episodePlaylist[i].durationLabel)),
              onTap: () {
                Navigator.of(ctx).pop();
                if (i != _episodeIndex) _goEpisode(i - _episodeIndex);
              },
            ),
        ],
      ),
    );
  }

  void _nextEpisode() => _goEpisode(1);

  void _prevEpisode() => _goEpisode(-1);

  AppCopy get _copy => AppCopy.ofLanguage(ref.read(sessionProvider).language);

  String _localizedSource(AppCopy copy) {
    switch (_sourceLabelKey) {
      case 'stream':
        return copy.streamSource;
      case 'local':
        return copy.localSampleSource;
      default:
        return _sourceLabelKey;
    }
  }

  String _trackLabel(AudioTrack t) {
    final parts = appAudioParts(t);
    if (parts.isEmpty) return _copy.audioTrackFallback(t.id);
    return parts;
  }

  String _subLabel(SubtitleTrack t) {
    if (t.id == 'no') return _copy.off;
    final parts = appSubtitleParts(t);
    if (parts.isEmpty) return _copy.trackFallback(t.id);
    return parts;
  }

  String _videoLabel(VideoTrack t) {
    if (t.id == 'auto') return _copy.qualityAuto;
    if (t.id == 'no') return _copy.off;
    final parts = appVideoParts(t);
    if (parts.isEmpty) return _copy.videoTrackFallback(t.id);
    return parts;
  }

  String _qualitySubtitle(AppCopy copy) {
    final cur = _videoTrack;
    if (cur != null &&
        appIsSelectableTrackId(cur.id) &&
        appVideoParts(cur).isNotEmpty) {
      return '${_videoLabel(cur)} · ${_localizedSource(copy)}';
    }
    if (_videoTracks.isNotEmpty) {
      final best = _videoTracks.first;
      final parts = appVideoParts(best);
      if (parts.isNotEmpty) {
        return '${copy.qualityAuto} · $parts · ${_localizedSource(copy)}';
      }
    }
    return copy.qualityLine(copy.qualityAuto, _localizedSource(copy));
  }

  /// Landscape-safe sheet: capped height + scroll (avoids bottom overflow).
  /// [keepVideoVisible]: in portrait the sheet stays below the picture
  /// (centred 16:9) with a light scrim, so the video does not look blank
  /// while the episode list is open.
  Future<T?> _showPlayerSheet<T>({
    required Widget Function(BuildContext) body,
    bool keepVideoVisible = false,
  }) {
    final size = MediaQuery.sizeOf(context);
    final portrait = size.height > size.width;
    var maxH = size.height * 0.72;
    if (keepVideoVisible && portrait) {
      final videoBottom = size.height / 2 + size.width * 9 / 16 / 2;
      maxH = (size.height - videoBottom - 8).clamp(220.0, size.height * 0.72);
    }
    return showModalBottomSheet<T>(
      context: context,
      barrierColor: keepVideoVisible ? Colors.black26 : null,
      backgroundColor: const Color(0xFF141414),
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: maxH),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(child: body(ctx)),
        ),
      ),
    );
  }

  Future<void> _pickSubtitles() async {
    final player = _player;
    if (player != null) _syncTracksFromPlayer(player, applyPrefs: false);
    final copy = _copy;
    await _showPlayerSheet<void>(
      body: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              copy.subtitles,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          ListTile(
            title: Text(copy.off),
            trailing: !_subsOn
                ? Icon(Icons.check, color: AppColors.cyan)
                : null,
            onTap: () async {
              await _player?.setSubtitleTrack(SubtitleTrack.no());
              setState(() => _subtitleTrack = SubtitleTrack.no());
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          for (final t in _subtitleTracks)
            ListTile(
              title: Text(_subLabel(t)),
              trailing: t.id == _subtitleTrack?.id
                  ? Icon(Icons.check, color: AppColors.cyan)
                  : null,
              onTap: () async {
                await _player?.setSubtitleTrack(t);
                setState(() => _subtitleTrack = t);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          if (_subtitleTracks.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                copy.noEmbeddedSubtitles,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _openSettings() async {
    final player = _player;
    if (player != null) _syncTracksFromPlayer(player, applyPrefs: false);
    final copy = _copy;
    await _showPlayerSheet<void>(
      body: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                copy.settings,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.speed_rounded,
                color: AppColors.cyan,
              ),
              title: Text(copy.playbackSpeed),
              subtitle: Text('${_speed}x'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickSpeed();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.high_quality_rounded,
                color: AppColors.cyan,
              ),
              title: Text(copy.quality),
              subtitle: Text(_qualitySubtitle(copy)),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickQuality();
              },
            ),
            ListTile(
              leading: Icon(
                _screenModeIcon(_screenMode),
                color: AppColors.cyan,
              ),
              title: Text(copy.videoScreenMode),
              subtitle: Text(_screenModeLabel(copy, _screenMode)),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickScreenMode();
                _showControlsNow();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.audiotrack_rounded,
                color: AppColors.cyan,
              ),
              title: Text(copy.audio),
              subtitle: Text(
                _audioTracks.isEmpty
                    ? copy.audioAuto
                    : _trackLabel(_audioTrack ?? _audioTracks.first),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAudio();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.closed_caption_rounded,
                color: AppColors.cyan,
              ),
              title: Text(copy.subtitles),
              subtitle: Text(
                !_subsOn
                    ? copy.off
                    : _subLabel(_subtitleTrack ?? SubtitleTrack.no()),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickSubtitles();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSpeed() async {
    await _showPlayerSheet<void>(
      body: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in _speeds)
            ListTile(
              title: Text('${s}x'),
              trailing: s == _speed
                  ? Icon(Icons.check, color: AppColors.cyan)
                  : null,
              onTap: () async {
                await _setSpeed(s);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickAudio() async {
    final player = _player;
    if (player != null) _syncTracksFromPlayer(player, applyPrefs: false);
    final copy = _copy;
    await _showPlayerSheet<void>(
      body: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              copy.audio,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          for (final t in _audioTracks)
            ListTile(
              title: Text(_trackLabel(t)),
              trailing: t.id == _audioTrack?.id
                  ? Icon(Icons.check, color: AppColors.cyan)
                  : null,
              onTap: () async {
                await _player?.setAudioTrack(t);
                setState(() => _audioTrack = t);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          if (_audioTracks.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                copy.noEmbeddedAudio,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _pickQuality() async {
    final player = _player;
    if (player != null) _syncTracksFromPlayer(player, applyPrefs: false);
    final copy = _copy;
    await _showPlayerSheet<void>(
      body: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              copy.quality,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          ListTile(
            title: Text(copy.qualityAuto),
            subtitle: Text(_localizedSource(copy)),
            trailing:
                (_videoTrack == null ||
                    _videoTrack!.id == 'auto' ||
                    !appIsSelectableTrackId(_videoTrack!.id))
                ? Icon(Icons.check, color: AppColors.cyan)
                : null,
            onTap: () async {
              await _player?.setVideoTrack(VideoTrack.auto());
              setState(() => _videoTrack = VideoTrack.auto());
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          for (final t in _videoTracks)
            ListTile(
              title: Text(_videoLabel(t)),
              trailing: t.id == _videoTrack?.id
                  ? Icon(Icons.check, color: AppColors.cyan)
                  : null,
              onTap: () async {
                await _player?.setVideoTrack(t);
                setState(() => _videoTrack = t);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          if (_videoTracks.length <= 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                copy.noAlternateQuality,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  void deactivate() {
    // Sheets and dialogs deactivate this route. Do not save or stop the
    // lease here — progress is saved on a 20s timer, on pause, and on dispose.
    super.deactivate();
  }

  @override
  void dispose() {
    ScreenAwake.release(this);
    // Client 18 Oct #2: a download paused for this playback continues.
    PlaybackArbiter.afterPlayback();
    _autoNext?.cancel();
    _waitingTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _silenceAndInvalidate();
    _progressTimer?.cancel();
    _progressTimer = null;
    _liveTicker?.cancel();
    _liveTicker = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _hideVolume?.cancel();
    _hideVolume = null;
    _hideControls?.cancel();
    _hideControls = null;
    _reHide?.cancel();
    _playbackService(false);
    SystemChrome.setSystemUIChangeCallback(null);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    final player = _player;
    final media = _media;
    final lib = _library;
    // Leave path already enqueued progress — do not double PUT.
    if (!_leaving &&
        !_cleanupQueued &&
        !_isLivePlayback &&
        _resumeSeekDone &&
        player != null &&
        _ready &&
        media != null &&
        lib != null) {
      final durMs = player.state.duration.inMilliseconds;
      if (durMs > 0) {
        final posMs = player.state.position.inMilliseconds;
        lib.setProgress(
          media.id,
          posMs / durMs,
          item: _progressItem(media),
          positionSec: (posMs / 1000).round(),
          durationSec: (durMs / 1000).round(),
          refreshRemote: false,
        );
      }
    }
    final id = _playbackId;
    final deviceId = _deviceId;
    final repo = _mediaRepo;
    final lease = _lease;
    _playbackId = null;
    _lease = null;
    if (!_cleanupQueued) {
      _cleanupQueued = true;
      // Release the player (and its provider connection) immediately, then
      // the lease. Both are tracked in the lifecycle gate so a replacing route
      // (Next episode) cannot open or start a lease while they are pending.
      final disposing = _disposePlayer();
      Future<void> stopRemote() async {
        if (lease != null) {
          await lease.stop();
          lease.dispose();
        } else if (id != null && deviceId != null && repo != null) {
          await repo.stopPlayback(playbackId: id, deviceId: deviceId);
        }
      }

      PlayerLifecycleGate.track(() async {
        try {
          await disposing;
        } catch (_) {}
        try {
          await stopRemote().timeout(const Duration(seconds: 5));
        } catch (_) {
          ProgressSyncQueue.instance.enqueue(
            stopRemote,
            label: 'disposeLeaseStop',
          );
        }
      }());
    }
    _stallWatchdog?.cancel();
    _lockHintTimer?.cancel();
    _screenModeFlashTimer?.cancel();
    _liveWinTimer?.cancel();
    _iosPipStateTimer?.cancel();
    unawaited(AppPip.setAuto(false));
    AppPip.inPip.removeListener(_onPipChanged);
    AppPip.onIosSetPlaying = null;
    AppPip.onIosSkip = null;
    for (final subscription in _subs) {
      unawaited(subscription.cancel());
    }
    _subs.clear();
    _pb.dispose();
    _positionN.dispose();
    _durationN.dispose();
    _activePlayerRoutes = (_activePlayerRoutes - 1).clamp(0, 64);
    if (_activePlayerRoutes == 0) applyAppOrientations();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  /// Live elapsed since open (updates every second via ticker).
  String _fmtLiveElapsed() {
    final start = _liveOpenedAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(start);
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    if (h > 0)
      return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  Future<void> _goLive() async {
    if (_liveSeekable) {
      if (_liveDelay <= _liveRaw.ahead - const Duration(seconds: 2)) {
        await _seekBy(_liveDelay);
      } else {
        await _reconnectLive();
      }
      if (mounted) setState(() => _userBehindLive = false);
      return;
    }
    final native = _nativePlayer;
    final p = _player;
    final dur = native?.value.duration ?? p?.state.duration ?? Duration.zero;
    if (dur > Duration.zero) {
      await _seekSafely(dur);
    }
    if (mounted) setState(() => _userBehindLive = false);
  }

  /// Back to live when the newest part was never downloaded (the player
  /// paused reading while behind): start the channel again, as on open.
  /// (Re-opening the URL on the same player lost the video output on the
  /// emulator, 21 Oct.)
  Future<void> _reconnectLive() async {
    _diag?.pb('LIVE_RECONNECT behindLive=${_liveDelay.inSeconds}s');
    setState(() {
      _liveSeeking = false;
      _liveSeekTarget = null;
      _liveDelay = Duration.zero;
      _liveRaw = LiveSeekWindow.none;
      _liveWin = LiveSeekWindow.none;
      _userBehindLive = false;
      _liveWinLogged = false;
    });
    await _init();
  }

  Future<void> _showPlayerInfo() async {
    final m = _media;
    final kind = m?.kind.name ?? widget.kindHint?.name ?? _contentType;
    final badges = m?.badges ?? const <String>[];
    final seriesId = widget.seriesId ?? m?.seriesId;
    final isLive = _isLivePlayback;
    final isSeries = kind == 'series' || seriesId != null;
    final episodeLine = (m?.subtitle ?? '').trim();
    final catId = (m?.categoryId ?? '').trim();
    var categoryName = '';
    if (isLive && catId.isNotEmpty) {
      try {
        final cats =
            await ref.read(catalogRepositoryProvider).getCategories(MediaKind.live);
        categoryName = cats
            .where((c) => c.id == catId)
            .map((c) => c.name)
            .firstWhere((n) => n.trim().isNotEmpty, orElse: () => '');
      } catch (_) {}
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111622),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isLive
                    ? 'Live channel'
                    : (isSeries ? 'Series' : 'Movie'),
                style: TextStyle(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              if (isLive) ...[
                Text(_copy.playbackLiveNoSeek,
                    style: const TextStyle(color: Color(0xFF94A3B8))),
                if (categoryName.isNotEmpty)
                  Text(_copy.infoCategory(categoryName),
                      style: const TextStyle(color: Color(0xFF94A3B8))),
              ],
              if (isSeries && episodeLine.isNotEmpty)
                Text(_copy.infoEpisode(episodeLine),
                    style: const TextStyle(color: Color(0xFF94A3B8))),
              // Playback log at any time (also while it is still loading):
              // it was only reachable from the error screen.
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  unawaited(showPlaybackDiagnostics(
                    context,
                    userMessage: _error,
                    contentId: widget.id,
                  ));
                },
                icon: const Icon(Icons.receipt_long_rounded),
                label: Text(_copy.playbackDetails),
              ),
              if (m?.year != null)
                Text(_copy.infoYear('${m!.year}'),
                    style: const TextStyle(color: Color(0xFF94A3B8))),
              if (m?.durationLabel != null)
                Text(_copy.infoDuration(m!.durationLabel!),
                    style: const TextStyle(color: Color(0xFF94A3B8))),
              if (badges.isNotEmpty)
                Text(_copy.infoQuality(badges.map(badgeText).join(' · ')),
                    style: const TextStyle(color: Color(0xFF94A3B8))),
              if (m?.synopsis != null && m!.synopsis!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(m.synopsis!, style: const TextStyle(height: 1.35)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Next / previous channel within the current channel's package.
  Future<void> _zapLiveChannel(int delta) async {
    try {
      final cat = _media?.categoryId ?? _listPackageId;
      if (cat == null || cat.isEmpty) return;
      final list = await _channelsOf(cat);
      if (list.length < 2 || !mounted) return;
      final idx = list.indexWhere((c) => c.id == widget.id);
      final base = idx < 0 ? 0 : idx;
      final i = (base + delta) % list.length;
      _playChannel(list[i < 0 ? list.length + i : i]);
    } catch (_) {}
  }

  /// Packages for the in-player list: Sports packages when the channel is a
  /// sports channel, otherwise the Live TV ones (client 18 Oct #7: the list
  /// showed only the Alwan package, from the Home preload of 40 channels).
  Future<List<CatalogCategory>> _playerPackages() async {
    final repo = ref.read(catalogRepositoryProvider);
    final cats = await repo.getCategories(MediaKind.live);
    final current = _media?.categoryId ?? _listPackageId;
    final currentCat = cats.where((c) => c.id == current).firstOrNull;
    final sports = currentCat != null
        ? RemoteCatalogRepository.isSportsCategory(currentCat)
        : widget.kindHint == MediaKind.sports;
    return [
      for (final c in cats)
        if (RemoteCatalogRepository.isSportsCategory(c) == sports) c,
    ];
  }

  String? _listPackageId;
  final Map<String, List<MediaItem>> _packageChannels = {};

  /// Every channel of one package (all pages).
  Future<List<MediaItem>> _channelsOf(String categoryId) async {
    final cached = _packageChannels[categoryId];
    if (cached != null) return cached;
    final repo = ref.read(catalogRepositoryProvider);
    final out = <MediaItem>[];
    String? cursor;
    for (var i = 0; i < 10; i++) {
      final page = await repo.browse(
        kind: MediaKind.live,
        categoryId: categoryId,
        cursor: cursor,
        limit: 100,
      );
      out.addAll(
        page.items.where((m) => !isProviderAdOrHeaderChannel(m.title)),
      );
      if (!page.hasMore) break;
      cursor = page.nextCursor;
    }
    return _packageChannels[categoryId] = out;
  }

  void _playChannel(MediaItem ch) {
    if (ch.id == widget.id) return;
    final label = cleanDisplayName(ch.title, keepQuality: true);
    final title = label.isEmpty ? ch.id : label;
    final kind = widget.kindHint == MediaKind.sports ? 'sports' : 'live';
    context.pushReplacement(
      '/player/${ch.id}?kind=$kind&title=${Uri.encodeQueryComponent(title)}',
    );
  }

  Future<void> _showLiveChannelList() async {
    List<CatalogCategory> packages;
    try {
      packages = await _playerPackages();
    } catch (_) {
      packages = const [];
    }
    if (!mounted || packages.isEmpty) return;
    var selected = packages
            .where((c) => c.id == (_media?.categoryId ?? _listPackageId))
            .firstOrNull ??
        packages.first;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B0F18),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: final EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      const NeonGlowIcon(Icons.live_tv_rounded, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _copy.channelList,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Packages: tap one to see its channels.
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: packages.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final c = packages[i];
                      return CategoryChip(
                        label: c.name,
                        selected: c.id == selected.id,
                        onTap: () => setSheet(() => selected = c),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder<List<MediaItem>>(
                    key: ValueKey(selected.id),
                    future: _channelsOf(selected.id),
                    builder: (_, snap) {
                      if (snap.hasError) {
                        return Center(
                          child: TextButton.icon(
                            onPressed: () => setSheet(() {}),
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(_copy.retry),
                          ),
                        );
                      }
                      final list = snap.data;
                      if (list == null) {
                        return Center(child: AppLoader.inline(size: 28));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final ch = list[i];
                          final on = ch.id == widget.id;
                          final label =
                              cleanDisplayName(ch.title, keepQuality: true);
                          return Material(
                            color: on
                                ? AppColors.cyan.withValues(alpha: 0.14)
                                : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              dense: true,
                              leading: SizedBox(
                                width: 52,
                                height: 36,
                                child: RemoteImage(
                                  url: ch.posterUrl,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              title: Text(
                                '${i + 1}  ${label.isEmpty ? ch.id : label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: on ? AppColors.cyan : Colors.white,
                                ),
                              ),
                              // Favourite without leaving the player (client
                              // 21 Oct). Adds to the server Favourites (shared
                              // with the TV); a channel in My List counts too.
                              trailing: Consumer(
                                builder: (context, ref, _) {
                                  final lib = ref.watch(libraryProvider);
                                  final inList = lib.myList.any((e) => e.id == ch.id);
                                  final fav = lib.isFavoriteChannel(ch.id);
                                  final liked = fav && !inList ||
                                      lib.ratingFor(ch.id) == 1;
                                  return IconButton(
                                    tooltip: fav ? _copy.favorited : _copy.favorite,
                                    icon: Icon(
                                      fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                      color: fav ? AppColors.magenta : Colors.white70,
                                    ),
                                    onPressed: () {
                                      final n = ref.read(libraryProvider.notifier);
                                      if (fav) {
                                        if (inList) n.toggleMyList(ch.id, item: ch);
                                        if (liked) n.setRating(ch.id, 0, item: ch);
                                      } else {
                                        // Server Favourites: the same list the
                                        // TV shows as its Favourites.
                                        n.setRating(ch.id, 1, item: ch);
                                      }
                                    },
                                  );
                                },
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _listPackageId = selected.id;
                                _playChannel(ch);
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position;
    final dur = _duration;
    final live = _isLivePlayback;
    final atEdge = _atLiveEdge;
    // Live: full bar at edge. Only show DVR fraction after an explicit scrub back.
    final progress = live
        ? (_liveSeekable
            ? _liveWin.fraction
            : atEdge
              ? 1.0
              : (dur.inMilliseconds <= 0
                    ? 1.0
                    : (pos.inMilliseconds / dur.inMilliseconds).clamp(
                        0.0,
                        1.0,
                      )))
        : (dur.inMilliseconds == 0
              ? 0.0
              : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0));
    final video = _video;
    final native = _nativePlayer;
    final muted = _volume <= 0;

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Locked: Back only shows the lock button; unlock first to leave.
        if (_locked) {
          _flashLockHint();
          return;
        }
        unawaited(_requestLeave());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _locked ? (_) => _flashLockHint() : _onPlayerTapDown,
          onTapUp: _locked ? null : _onPlayerTapUp,
          onTapCancel: () => _backTapPending = false,
          // Task #143 #15: left = brightness dim, right = volume.
          onVerticalDragStart: _locked ? null : (d) {
            final w = MediaQuery.sizeOf(context).width;
            final rightHalf = d.localPosition.dx > w * 0.5;
            // Physical sides (ignore RTL): right = volume, left = brightness.
            _gestureVolume = rightHalf;
            _gestureStartY = d.localPosition.dy;
            _gestureStartValue =
                _gestureVolume ? _volume : (1.0 - _brightnessDim);
            setState(() {
              _gestureHudLevel = _gestureStartValue;
              _gestureHud = _gestureVolume ? _copy.volume : _copy.brightness;
            });
          },
          onVerticalDragUpdate: _locked ? null : (d) {
            final startY = _gestureStartY;
            final startV = _gestureStartValue;
            if (startY == null || startV == null) return;
            final h = MediaQuery.sizeOf(context).height;
            final delta = (startY - d.localPosition.dy) / (h * 0.45);
            final next = (startV + delta).clamp(0.0, 1.0);
            if (_gestureVolume) {
              _setVolume(next);
              setState(() {
                _gestureHudLevel = next;
                _gestureHud = _copy.volume;
              });
            } else {
              setState(() {
                _brightnessDim = 1.0 - next;
                _gestureHudLevel = next;
                _gestureHud = _copy.brightness;
              });
            }
          },
          onVerticalDragEnd: _locked ? null : (_) {
            _gestureStartY = null;
            _gestureStartValue = null;
            Future<void>.delayed(const Duration(milliseconds: 600), () {
              if (mounted) {
                setState(() {
                  _gestureHud = null;
                  _gestureHudLevel = null;
                });
              }
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (native != null && _ready && !_failed)
                RepaintBoundary(
                  child: NativePlaybackView(
                    controller: native,
                    mode: _screenMode,
                  ),
                )
              else if (_surfaceMounted && video != null)
                RepaintBoundary(
                  // Always expand the viewport. Fit/Zoom is only BoxFit —
                  // wrapping Fit in Center left media_kit without a full
                  // viewport so the picture looked cropped (client C3).
                  child: ColoredBox(
                    color: Colors.black,
                    child: ClipRect(
                    child: SizedBox.expand(
                      child: Transform.scale(
                        scale: _screenMode.extraScale,
                        child: Video(
                        controller: video,
                        controls: NoVideoControls,
                        fill: Colors.black,
                        alignment: Alignment.center,
                        // Fit = whole picture; Fill = proportional cover; Zoom = closer.
                        fit: _screenMode.boxFit,
                        aspectRatio: _screenMode.forcedAspect,
                        // C4: ScreenAwake owns the lock; media_kit's default
                        // wakelock clears it on every playing=false.
                        wakelock: false,
                        // media_kit pauses by default when the app leaves
                        // the screen; that stopped the sound (17 Oct).
                        pauseUponEnteringBackgroundMode: false,
                        subtitleViewConfiguration:
                            const SubtitleViewConfiguration(
                          style: TextStyle(
                            height: 1.4,
                            fontSize: 32,
                            letterSpacing: 0.2,
                            wordSpacing: 0.2,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            backgroundColor: Color(0x99000000),
                          ),
                          textAlign: TextAlign.center,
                          padding: EdgeInsets.fromLTRB(24, 0, 24, 72),
                        ),
                      ),
                      ),
                    ),
                    ),
                  ),
                )
              else
                _buildPosterLoadingOrError(),
              if (_brightnessDim > 0)
                IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: _brightnessDim * 0.85),
                  ),
                ),
              if (_locked && _lockHint)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Center(
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: const StadiumBorder(),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: _unlock,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_rounded,
                                    color: AppColors.cyan,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _copy.tapToUnlock,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_gestureHud != null && _gestureHudLevel != null)
                IgnorePointer(
                  child: Align(
                    // Absolute sides: volume = physical right, brightness = left
                    // (must not RTL-mirror like the seek flash).
                    alignment: _gestureVolume
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: _VerticalGestureSlider(
                        label: _gestureHud!,
                        level: _gestureHudLevel!,
                        icon: _gestureVolume
                            ? Icons.volume_up_rounded
                            : Icons.brightness_6_rounded,
                      ),
                    ),
                  ),
                ),
              if (_screenModeFlash != null)
                IgnorePointer(
                  // Above the play button (it covered the name).
                  child: Align(
                    alignment: const Alignment(0, -0.45),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Text(
                          _screenModeFlash!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_seekFlashSec != null)
                IgnorePointer(
                  child: Align(
                    // Absolute sides match physical left=rewind (not RTL-mirrored).
                    alignment: _seekFlashSec! < 0
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _seekFlashSec! < 0
                                    ? Icons.replay_10_rounded
                                    : Icons.forward_10_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                              Text(
                                '${_seekFlashSec!.abs()}s',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_ready && !_failed && !_leaving)
                // Watermark (client 17 Oct): approved logo only, no text, on
                // the picture itself (it sat below the video in portrait and
                // looked missing), bottom-left of the video in both
                // languages.
                Positioned.fill(
                  child: IgnorePointer(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final r = _videoRect(c.biggest);
                        // ~20% smaller (client 20 Oct: "slightly smaller").
                        final logoH = (r.height * 0.06).clamp(15.0, 27.0);
                        return Stack(
                          children: [
                            Positioned(
                              left: r.left + r.width * 0.025,
                              top: r.bottom - logoH - r.height * 0.045,
                              child: Opacity(
                                opacity: 0.6,
                                child: AppLogo(
                                  height: logoH,
                                  showWordmark: false,
                                  alignToStart: false,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              if (!_ready && !_failed && !_leaving)
                IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Only the APP loader while a stream starts: no
                          // title poster / provider art
                          AppPlaybackLoading(
                            logoHeight: 36,
                            label: _waitingLabel ?? _copy.loading,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_ready && _buffering && !_failed && !_leaving)
                IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Center(
                      child: AppPlaybackLoading(
                        logoHeight: 36,
                        label: _copy.loading,
                      ),
                    ),
                  ),
                ),
              if (_pb.ui.leaseAtRisk && _ready)
                const Positioned(
                  top: 48,
                  left: 16,
                  right: 16,
                  child: Material(
                    color: Color(0xCCB00020),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Connection unstable — reconnecting…',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              if (_pendingStutterWarn != null && _ready)
                Positioned(
                  top: 48,
                  left: 16,
                  right: 16,
                  child: Material(
                    color: const Color(0xCC333333),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _pendingStutterWarn!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _forcePlayDespiteWarn = true;
                                _pendingStutterWarn = null;
                              });
                            },
                            child: Text(_copy.playAnyway),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Back while a stream is still opening (client 9 Nov: a channel
              // with a problem left no way back; iPhone has no hardware Back).
              if (!_ready && !_failed && !_leaving)
                PositionedDirectional(
                  top: 0,
                  start: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        tooltip: _copy.playbackBack,
                        onPressed: () => unawaited(_requestLeave()),
                        icon: const AppBackIcon(
                          style: AppBackIconStyle.material,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_ready && !_failed && showControls && !_leaving)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.75),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.88),
                      ],
                      stops: const [0, 0.28, 0.55, 1],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                      child: Column(
                        children: [
                          Row(
                            key: _chromeTopKey,
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                onPressed: () => unawaited(_requestLeave()),
                                icon: const AppBackIcon(
                                  style: AppBackIconStyle.material,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                    // Live: Now / Next from the guide, with
                                    // a reminder for the next programme.
                                    if (live) _LiveGuideLine(channel: _media),
                                  ],
                                ),
                              ),
                              // Trailing actions used to overflow by ~64px on
                              // narrow widths (many IconButtons in one Row).
                              Flexible(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  reverse: true,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _chromeIcon(
                                        tooltip:
                                            muted ? _copy.unmute : _copy.volume,
                                        onPressed: _openVolumeSlider,
                                        onLongPress: _toggleMute,
                                        icon: Icon(
                                          muted
                                              ? Icons.volume_off_rounded
                                              : Icons.volume_up_rounded,
                                        ),
                                      ),
                                      _chromeIcon(
                                        tooltip: _copy.details,
                                        onPressed: _showPlayerInfo,
                                        icon: const Icon(
                                          Icons.info_outline_rounded,
                                        ),
                                      ),
                                      if (live)
                                        _chromeIcon(
                                          tooltip: _copy.channelList,
                                          onPressed: _showLiveChannelList,
                                          icon: const Icon(Icons.list_rounded),
                                        ),
                                      if (!live && _isEpisode)
                                        _chromeIcon(
                                          tooltip: _copy.seasonTab(
                                            _episodePlaylist[_episodeIndex]
                                                .season,
                                          ),
                                          onPressed: _showEpisodes,
                                          icon: const Icon(
                                            Icons.video_library_rounded,
                                          ),
                                        ),
                                      _chromeIcon(
                                        tooltip: _copy.subtitles,
                                        onPressed: _pickSubtitles,
                                        icon: Icon(
                                          Icons.closed_caption_rounded,
                                          color: _subsOn
                                              ? AppColors.cyan
                                              : Colors.white,
                                        ),
                                      ),
                                      _chromeIcon(
                                        tooltip: _copy.settings,
                                        onPressed: _openSettings,
                                        icon: const Icon(
                                          Icons.settings_rounded,
                                        ),
                                      ),
                                      _chromeIcon(
                                        tooltip: _screenModeLabel(
                                            _copy, _screenMode.next),
                                        onPressed: () {
                                          _setScreenMode(_screenMode.next,
                                              flash: true);
                                          _showControlsNow();
                                        },
                                        icon: Icon(
                                          _screenModeIcon(_screenMode),
                                        ),
                                      ),
                                      if (_canIosPip)
                                        _chromeIcon(
                                          tooltip: _copy.pictureInPicture,
                                          onPressed: () =>
                                              unawaited(_startIosPip()),
                                          icon: const Icon(
                                            Icons.picture_in_picture_alt_rounded,
                                          ),
                                        ),
                                      _chromeIcon(
                                        tooltip: _copy.lockScreen,
                                        onPressed: _lock,
                                        icon: const Icon(
                                          Icons.lock_open_rounded,
                                        ),
                                      ),
                                      _chromeIcon(
                                        tooltip: _copy.rotate,
                                        onPressed: _toggleOrientation,
                                        icon: const Icon(
                                          Icons.screen_rotation_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_showVolumeSlider)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                margin: const EdgeInsets.only(right: 8, top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                width: 220,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _toggleMute,
                                      child: Icon(
                                        muted
                                            ? Icons.volume_off_rounded
                                            : Icons.volume_up_rounded,
                                        size: 18,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 2.5,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                            enabledThumbRadius: 6,
                                          ),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                            overlayRadius: 12,
                                          ),
                                          activeTrackColor: Colors.white,
                                          inactiveTrackColor: Colors.white24,
                                          thumbColor: Colors.white,
                                        ),
                                        child: Slider(
                                          value: _volume.clamp(0.0, 1.0),
                                          onChanged: (v) => _setVolume(v),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const Spacer(),
                          // Force LTR: physical left = rewind (fixes Arabic reverse).
                          Directionality(
                            key: _chromeCenterKey,
                            textDirection: TextDirection.ltr,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_isEpisode || live) ...[
                                  IconButton(
                                    onPressed: live
                                        ? () => _zapLiveChannel(-1)
                                        : _prevEpisode,
                                    iconSize: 36,
                                    icon: const Icon(
                                      Icons.skip_previous_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                // Client 23 Oct round 3 #1: no rewind /
                                // forward on Live TV and Sports at all
                                // (replaces the 21 Oct / 23 Oct live seek).
                                if (!live) ...[
                                  IconButton(
                                    onPressed: () {
                                      _armControlsHide();
                                      unawaited(
                                        _seekBy(const Duration(seconds: -10)),
                                      );
                                    },
                                    iconSize: 36,
                                    icon:
                                        const Icon(Icons.replay_10_rounded),
                                  ),
                                  const SizedBox(width: 20),
                                ],
                                if (_buffering)
                                  const SizedBox(width: 64, height: 64)
                                else
                                  IconButton.filled(
                                    onPressed: () {
                                      _armControlsHide();
                                      unawaited(_togglePlay());
                                    },
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.all(14),
                                    ),
                                    icon: Icon(
                                      _playing
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 36,
                                    ),
                                  ),
                                if (!live) ...[
                                  const SizedBox(width: 20),
                                  IconButton(
                                    onPressed: () {
                                      _armControlsHide();
                                      unawaited(
                                        _seekBy(const Duration(seconds: 10)),
                                      );
                                    },
                                    iconSize: 36,
                                    icon:
                                        const Icon(Icons.forward_10_rounded),
                                  ),
                                ],
                                if (_isEpisode || live) ...[
                                  const SizedBox(width: 12),
                                  IconButton(
                                    onPressed: live
                                        ? () => _zapLiveChannel(1)
                                        : _nextEpisode,
                                    iconSize: 36,
                                    icon: const Icon(Icons.skip_next_rounded),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Spacer(),
                          Padding(
                            key: _chromeBottomKey,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                            // Time, seek bar, time: a timeline runs left to right in every
                            // language (Arabic had 00:03 on the right of a left-to-right bar).
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: live ? 88 : 58,
                                  child: Text(
                                    live ? _fmtLiveElapsed() : _fmt(pos),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (live)
                                  // Live: a full bar, not draggable (no
                                  // rewind / forward, client 23 Oct round 3 #1).
                                  Expanded(
                                    child: AppSeekBar(
                                      progress: 1,
                                      enabled: false,
                                      onSeekFraction: (_) async {},
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: AppSeekBar(
                                      progress: progress,
                                      enabled: _ready,
                                      onSeekFraction: (v) async {
                                        if (!_ready ||
                                            dur.inMilliseconds == 0) {
                                          return;
                                        }
                                        await _seekSafely(
                                          Duration(
                                            milliseconds:
                                                (dur.inMilliseconds * v)
                                                    .round(),
                                          ),
                                        );
                                        await _persistProgress();
                                      },
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                if (live)
                                  GestureDetector(
                                    onTap: atEdge ? null : _goLive,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: atEdge
                                            ? AppColors.live
                                            : Colors.white24,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        atEdge ? 'LIVE' : 'GO LIVE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.6,
                                          color: atEdge
                                              ? Colors.white
                                              : AppColors.cyan,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  SizedBox(
                                    width: 72,
                                    child: Text(
                                      _fmt(dur),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosterLoadingOrError() {
    // Black behind the loader / error: no title art while a stream starts.
    // Leaving: plain black (the poster flashed up full screen on exit).
    if (_leaving) return const ColoredBox(color: Colors.black);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (_failed)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.textSecondary,
                  size: 40,
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  // English API errors end with "." which BiDi flips to the
                  // start in Arabic UI (".No access token…"). Localized AR/UR
                  // messages must stay RTL.
                  child: Text(
                    _copy.errorText(_error ?? 'Playback failed. Please try again.'),
                    textAlign: TextAlign.center,
                    textDirection: _errorTextDirection(_copy.errorText(_error ?? '')),
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                // Diagnostic code stays in Details sheet (not on the face).
                const SizedBox(height: 16),
                // Always offer Back so the user is never trapped on error.
                FilledButton.tonal(
                  onPressed: () => unawaited(_leavePlayer()),
                  child: Text(_copy.playbackBack),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => unawaited(showPlaybackDiagnostics(
                    context,
                    userMessage: _error,
                    contentId: widget.id,
                  )),
                  child: Text(_copy.details),
                ),
                if (_conflict) ...[
                  if (ref.watch(sessionProvider).user?.playbackTakeover ==
                      true)
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _forceTakeover = true;
                          _failed = false;
                          _conflict = false;
                          _error = null;
                        });
                        unawaited(_init());
                      },
                      child: Text(_copy.watchHereTakeOver),
                    ),
                  TextButton(
                    // Normal exit first (portrait, system bars, player
                    // closed), then Device Management on top of the previous
                    // screen so Back works. It used `go`, stayed sideways in
                    // immersive mode with no way back (client 20 Oct iPhone).
                    onPressed: () =>
                        unawaited(_leavePlayer(thenOpen: '/settings/devices')),
                    child: Text(_copy.manageDevices),
                  ),
                  TextButton(
                    onPressed: () => unawaited(_leavePlayer()),
                    child: Text(_copy.keepOtherDevicePlaying),
                  ),
                ] else if (_decoderLimited && _hdAlternative != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.hd_rounded),
                    onPressed: () => unawaited(
                      _leavePlayer(thenOpen: _hdAlternative!.playbackRoute()),
                    ),
                    label: Text(_copy.playHdVersion),
                  )
                else if (!_decoderLimited)
                  FilledButton(
                    onPressed: () => unawaited(_init()),
                    child: Text(_copy.retry),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Compact player chrome action — keeps the top Row from overflowing.
  Widget _chromeIcon({
    required String tooltip,
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
    required Widget icon,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      onLongPress: onLongPress,
      // 48 x 48 touch target (client 24 Oct: hard to tap).
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: icon,
    );
  }
}

class _VerticalGestureSlider extends StatelessWidget {
  const _VerticalGestureSlider({
    required this.label,
    required this.level,
    required this.icon,
  });

  final String label;
  final double level;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final pct = (level.clamp(0.0, 1.0) * 100).round();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 10),
            SizedBox(
              width: 8,
              height: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    const ColoredBox(color: Colors.white24),
                    FractionallySizedBox(
                      heightFactor: level.clamp(0.0, 1.0),
                      widthFactor: 1,
                      child: ColoredBox(color: AppColors.cyan),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$pct%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveGuideLine extends ConsumerWidget {
  const _LiveGuideLine({required this.channel});

  final MediaItem? channel;

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = channel;
    if (c == null) return const SizedBox.shrink();
    final progs = ref.watch(liveEpgProvider(c.id)).valueOrNull ?? const [];
    final now = DateTime.now();
    EpgProgramDto? cur;
    EpgProgramDto? next;
    for (final p in progs) {
      if (cur == null && p.isOnAt(now)) {
        cur = p;
      } else if (p.startAt.isAfter(now)) {
        next ??= p;
      }
    }
    if (cur == null && next == null) return const SizedBox.shrink();
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    final n = next;
    final set = n != null &&
        ref.watch(programRemindersProvider).isSet(c.id, n.startAt);
    final text = [
      if (cur != null) '${copy.epgNow} ${cur.title}',
      if (n != null) '${copy.epgNext} ${_hm(n.startAt)} ${n.title}',
    ].join('  ·  ');
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(fontSize: 12, color: AppColors.cyan),
          ),
        ),
        if (n != null)
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            visualDensity: VisualDensity.compact,
            tooltip: set ? copy.reminderSet : copy.remindProgram,
            onPressed: () => ref
                .read(programRemindersProvider.notifier)
                .toggle(channel: c, program: n),
            icon: Icon(
              set
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              size: 18,
              color: set ? AppColors.cyan : Colors.white70,
            ),
          ),
      ],
    );
  }
}

/// Localized AR/UR player errors stay RTL; English API strings stay LTR so a
/// trailing "." does not flip to the start in an RTL app locale (C2).
TextDirection _errorTextDirection(String? message) {
  final m = message ?? '';
  if (_rtlScript.hasMatch(m)) return TextDirection.rtl;
  return TextDirection.ltr;
}

final _rtlScript = RegExp(
  r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]',
);
