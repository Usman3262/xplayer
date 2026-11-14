import 'dart:async';
import 'dart:io' show ProcessInfo;
import 'package:video_player/video_player.dart' as native_video;
import 'native_playback_view.dart';
import 'tv_playback_diagnostics.dart';
import '../../core/screen_awake.dart';
import '../../core/tv_frame_stats.dart';
import 'tv_player_input.dart';

import 'package:flutter/foundation.dart';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/library_controller.dart';
import '../../core/tv_demo_mode.dart';
import '../../core/providers.dart';
import '../../core/tv_clock.dart';
import '../../core/tv_live_zap.dart';
import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_poster.dart';
import '../../widgets/tv_ui.dart' show TvButton, TvGlassStyle, TvUi;

/// Lease + playUrl via media_kit — near-parity with mobile [PlayerScreen],
/// adapted for Android TV D-pad (FocusTile + remote Shortcuts).
class TvPlayerScreen extends ConsumerStatefulWidget {
  const TvPlayerScreen({
    super.key,
    required this.id,
    this.startSec,
    this.seriesId,
    this.kindHint,
    this.initialTitle,
    this.initialItem,
  });
  final String id;
  final int? startSec;

  /// Parent series id when [id] is an episode stream id.
  final String? seriesId;

  /// Optional `?kind=vod|live|series` so Continue Watching / rails do not guess.
  final MediaKind? kindHint;

  /// Stream name from the rail/card that opened playback (`?title=`).
  final String? initialTitle;

  /// Optional catalog row passed as route `extra`.
  final MediaItem? initialItem;

  @override
  ConsumerState<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends ConsumerState<TvPlayerScreen>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _video;
  final List<StreamSubscription<dynamic>> _subs = [];

  bool showControls = true;
  bool _showVolumeSlider = false;

  /// Focus target while the controls are hidden. Without it focus fell to
  /// the route scope above the remote Shortcuts, so arrows did nothing.
  final FocusNode _rootFocus = FocusNode(debugLabel: 'tv-player-root');
  /// Centre play/pause button: Down from the player enters the button row here.
  final FocusNode _playFocus = FocusNode(debugLabel: 'tv-player-play');
  final FocusNode _seekFocus = FocusNode(debugLabel: 'tv-player-seek');
  Timer? _controlsHide;

  /// Remote seek presses add up here and run as one seek (each press used to
  /// be dropped while the previous IPTV seek was still in flight).
  Duration? _seekTarget;
  Timer? _seekDebounce;

  /// Live: channel list panel (Back or the Channel list button).
  bool _showChannels = false;
  // Packages beside the channels while watching (customers, 4 Nov): arrows
  // only move the focus; OK on a package shows its channels, OK on a channel
  // plays it.
  List<CatalogCategory>? _zapCats;
  String? _zapCatId;
  bool _zapCatLoading = false;
  ScrollController? _channelScroll;
  bool _ready = false;

  /// How often the native player's position reaches the UI. Each update
  /// redraws the controls over the video; slow TVs (LG webOS) froze during
  /// playback (client 26 Oct), so they update once a second.
  static Duration get _posUiInterval => TvPlatformProfile.lowPowerUi
      ? const Duration(seconds: 1)
      : const Duration(milliseconds: 250);
  native_video.VideoPlayerController? _nativePlayer;
  /// contain = letterbox; fill = crop to edges (parity with mobile).
  bool _videoFill = false;
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
  late String _title;
  MediaItem? _media;
  String? _playbackId;
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

  List<AudioTrack> _audioTracks = const [];
  List<SubtitleTrack> _subtitleTracks = const [];
  List<VideoTrack> _videoTracks = const [];
  AudioTrack? _audioTrack;
  SubtitleTrack? _subtitleTrack;
  VideoTrack? _videoTrack;
  bool _trackPrefsApplied = false;
  bool _forcePlayDespiteWarn = false;
  String? _pendingStutterWarn;

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
  bool _pausedByLifecycle = false;
  /// True after natural EOF (not premature). Switches chrome to replay / next.
  bool _playbackEnded = false;

  /// Settings → Autoplay: at the end of an episode the next one starts after
  /// a short countdown (the setting existed but nothing used it).
  static const _autoNextSeconds = 5;
  Timer? _autoNext;
  int _autoNextLeft = 0;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
  /// How close to the reported end counts as "caught up" after a DVR scrub.
  static const _liveEdgeTolerance = Duration(seconds: 20);
  // LG row: 110 + 10 of 1080 (client 9 Nov: the lists were too large).
  static const _channelRowH = 60.0;

  /// Flat season playlist for prev/next (real catalog ids are numeric).
  List<Episode> _episodePlaylist = const [];
  /// Episode strip under the controls (client video 16 Oct, series).
  ScrollController? _episodeScroll;
  /// Series backdrop/poster for strip cards without an episode still.
  String? _seriesArt;

  /// Episode row expanded (client reference video): collapsed to a
  /// "Season" hint until Down from the buttons, then focus on the playing
  /// episode; collapses again with the controls.
  bool _episodesOpen = false;
  final FocusNode _currentEpisodeFocus =
      FocusNode(debugLabel: 'tv-player-current-episode');

  void _openEpisodes() {
    if (_episodesOpen) return;
    setState(() => _episodesOpen = true);
    _diag?.pb('CONTROLS episodes open');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentEpisodeFocus.context != null) {
        _currentEpisodeFocus.requestFocus();
      }
    });
    _armControlsHide();
  }
  int _episodeIndex = -1;
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
    if (!_userBehindLive) return true;
    if (_duration.inMilliseconds <= 0) return false;
    return _position >= _duration - _liveEdgeTolerance;
  }

  void _syncLiveEdgeFromClock() {
    if (!_isLivePlayback || !_userBehindLive) return;
    if (_duration.inMilliseconds <= 0) return;
    if (_position >= _duration - _liveEdgeTolerance) {
      _userBehindLive = false;
    }
  }

  bool get _subsOn =>
      _subtitleTrack != null &&
      _subtitleTrack!.id != 'no' &&
      _subtitleTrack!.id != 'auto';

  static const _httpHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12; Android TV) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
  };

  @override
  void initState() {
    super.initState();
    // The player keeps the screen on: no screensaver or sleep while
    // watching (client 17 Oct: screensaver after 10 min without remote
    // input; Android's native player does not hold the screen itself).
    // Counted keep-awake: survives route replacement (see ScreenAwake).
    ScreenAwake.acquire(this);
    WidgetsBinding.instance.addObserver(this);
    _mediaRepo = ref.read(tvMediaRepositoryProvider);
    _library = ref.read(libraryProvider.notifier);
    _title = _bestStreamTitle();
    // Live opens full screen; OK / Up / Down / Back bring up the UI.
    if (widget.kindHint == MediaKind.live ||
        widget.kindHint == MediaKind.sports) {
      showControls = false;
    }
    HardwareKeyboard.instance.addHandler(_onAnyKey);
    _pb.addListener(() {
      if (mounted) setState(() {});
    });
    unawaited(DeviceCapabilitiesStore.instance.ensureLoaded());
    _init();
  }

  /// Prefer the catalog / rail stream name — never the app brand.
  String _bestStreamTitle({MediaItem? item, String? episodeTitle}) {
    final zap = ref.read(liveZapProvider);
    MediaItem? fromZap;
    if (zap != null) {
      final i = zap.indexOf(widget.id);
      if (i >= 0) fromZap = zap.channels[i];
    }
    final candidates = <String?>[
      episodeTitle,
      item?.displayTitle,
      item?.title,
      widget.initialItem?.displayTitle,
      widget.initialItem?.title,
      widget.initialTitle,
      fromZap?.displayTitle,
      fromZap?.title,
      _media?.displayTitle,
      _media?.title,
    ];
    for (final raw in candidates) {
      final t = cleanDisplayName(
        (raw ?? '').trim(),
        keepQuality: _isLivePlayback,
      );
      if (t.isEmpty) continue;
      final upper = t.toUpperCase();
      if (upper == AppBrand.name.toUpperCase() ||
          upper == 'UNTITLED' ||
          upper == 'STREAM') {
        continue;
      }
      return t;
    }
    final fallback = cleanDisplayName(
      widget.initialTitle ?? '',
      keepQuality: _isLivePlayback,
    );
    return fallback.isNotEmpty ? fallback : 'Untitled';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Task #143 #13: keep TV playback running in background.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_persistProgress(force: true));
      _diag?.pb('LIFECYCLE background; playback continues');
    } else if (state == AppLifecycleState.resumed) {
      _pausedByLifecycle = false;
      ScreenAwake.ensure();
      if (mounted) setState(() {});
    }
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
    final session = ref.read(tvSessionProvider);
    // Demo (client 5 Nov #30): the sample stream opens directly, no lease.
    if (ref.read(tvDemoModeProvider)) {
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
    if (!session.loggedIn) {
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
      final media = ref.read(tvMediaRepositoryProvider);
      final auth = ref.read(tvAuthRepositoryProvider);
      final session = ref.read(tvSessionProvider);
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
          title: _bestStreamTitle(
            item: item,
            episodeTitle: ep?.title,
          ),
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
          title: _bestStreamTitle(item: widget.initialItem),
          kind: hint,
          isLive: hint == MediaKind.live || hint == MediaKind.sports,
          containerExtension: catalog.knownContainerExtension(widget.id),
          posterUrl: widget.initialItem?.posterUrl,
          backdropUrl: widget.initialItem?.backdropUrl,
        );
      }
      item ??= widget.initialItem;
      _media = item;
      _title = _bestStreamTitle(item: item);
      if (mounted) setState(() {});

      final deviceId = await auth.ensurePlaybackDeviceId(
        name: TvPlatformProfile.deviceName,
        platform: TvPlatformProfile.backendPlatform,
      );
      if (!mounted || _leaving) return false;
      _deviceId = deviceId;

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
        _title = _bestStreamTitle(item: item, episodeTitle: eps.first.title);
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

      container = await resolvePlaybackContainer(
        catalog: catalog,
        contentType: contentType,
        streamId: streamId,
        known: container,
        seriesId: seriesKey ?? item?.seriesId ?? _media?.seriesId,
        findEpisode: (sid, eid) => _episodeInSeries(catalog, sid, eid),
      );

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
          final pos = _player?.state.position.inSeconds ?? 0;
          _resumeStartSec = pos > 5 ? pos : _resumeStartSec;
          await _openNetwork(_preferredUrl(lease), label: 'APP');
        },
      );
      _stats.reset();
      _lease!.statsProvider = _stats.snapshot;

      Future<PlaybackSessionDto> start(String id) async {
        _lease!.deviceId = id;
        final caps = DeviceCapabilitiesStore.instance.current;
        final tierCfg = DeviceCapabilitiesStore.instance.mpv;
        final prefs = await SharedPreferences.getInstance();
        // Default speed from Settings → Playback (client 2 Nov).
        final savedSpeed = double.tryParse(
          (prefs.getString('tv_playback_speed') ?? '1.0x').replaceAll('x', ''),
        );
        if (savedSpeed != null && _speeds.contains(savedSpeed)) _speed = savedSpeed;
        final qualityPref = _mapTvQualityPref(
          prefs.getString('tv_playback_quality') ?? 'Auto 4K',
        );
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
      final waitStart = DateTime.now();
      // An active download holds the provider connection: pause it first.
      final pausedDownload = await PlaybackArbiter.beforePlayback();
      if (pausedDownload != null && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(_copy.downloadPausedForPlayback(pausedDownload)),
          ),
        );
      }
      final settled =
          await PlayerLifecycleGate.settle(const Duration(seconds: 6));
      _teardownWaitMs = DateTime.now().difference(waitStart).inMilliseconds;
      if (!settled) {
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
          final fresh = await auth.forceReregisterDevice(
            name: TvPlatformProfile.deviceName,
            platform: TvPlatformProfile.backendPlatform,
          );
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

      final leaseStart = DateTime.now();
      PlaybackSessionDto lease = await acquireLease(deviceId);
      final leaseHttpMs = DateTime.now().difference(leaseStart).inMilliseconds;

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
        'dur=${_diag!.msSinceTap()}ms teardownWaitMs=$_teardownWaitMs '
        'leaseHttpMs=$leaseHttpMs type=$contentType stream=$streamId',
      );

      // Never resume into live — that parks the player behind the live edge.
      if (_isLivePlayback) {
        _resumeStartSec = null;
      } else {
        var resumeSec = widget.startSec;
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
      final nativeDefault =
          await AppDecoderPreferences.nativeEngine(tv: true);
      final mpvKind = _lastOpenFailureKind;
      if (!opened &&
          mounted &&
          !_leaving &&
          (_lease?.isActive ?? false) &&
          (nativeDefault || nativeFirst) &&
          TvPlatformProfile.mpvAvailable &&
          _mpvMayHelp(mpvKind)) {
        _diag?.pb('FALLBACK engine=mpv after kind=${mpvKind?.name ?? '-'}');
        _pb.setPhase(PlaybackPhase.openingMedia);
        opened = await _openNetwork(
          lease.playUrl,
          label: 'APP',
          forceMpv: true,
        );
        _diag?.pb('FALLBACK engine=mpv result=${opened ? 'ok' : 'failed'}');
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
      debugPrint('[Playback] conflict');
      _diag?.pb('ERROR code=CONFLICT phase=resolvingLease');
      String? holderName;
      try {
        final repo = ref.read(tvMediaRepositoryProvider);
        final active = await repo.playbackActive();
        if (active.active) {
          holderName = active.deviceName ?? active.deviceId;
        }
      } catch (_) {
        holderName = e.holderDeviceId;
      }
      if (mounted) {
        final heldMsg = holderName != null && holderName.isNotEmpty
            ? _copy.playbackHeldByDevice(holderName)
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
      debugPrint('[Playback] api: $e');
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
      if (_isCancellation(e)) {
        // The user left or changed channel: expected, not a failure. Still
        // stop the lease manager so a late lease reply is released.
        _diag?.pb('CANCELLED phase=resolvingLease');
        await _stopLease();
        return false;
      }
      debugPrint('[Playback] remote failed: $e\n$st');
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
    // Same teardown as mobile: stop timers and cancel any in-flight open.
    _healthTimer?.cancel();
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
    debugPrint(
      '[Playback] dispose start id=$disposeId '
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
      final t0 = DateTime.now();
      for (final s in subs) {
        await bounded('subscription', s.cancel(), 1000);
      }
      if (kIsWeb && native != null && mounted) {
        // LG (web): the native engine is an HTML <video> platform view.
        // Disposing it while the video widget is still composited stopped
        // all rendering (simulator, 25 Oct: the exit froze mid-fade). Take
        // the widget off screen first and let one frame draw.
        setState(() {});
        await bounded(
          'unmount',
          WidgetsBinding.instance.endOfFrame,
          500,
        );
      }
      await bounded('native', native?.dispose(), 4000);
      if (p != null) {
        // Stop network/decoding first so dispose has less to unwind.
        await bounded('stop', p.stop(), 1000);
        await bounded('player', p.dispose(), 3000);
      }
      final ms = DateTime.now().difference(t0).inMilliseconds;
      if (native != null || p != null) {
        _diag?.pb(
          'TEARDOWN done ms=$ms engine=${native != null ? 'native' : 'mpv'}',
        );
      }
      debugPrint('[Playback] dispose done id=$disposeId');
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
  Future<void> _leavePlayer({String? replaceWith}) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    _silenceAndInvalidate();
    // Position is read synchronously inside _persistProgress before its
    // first await; the server save then runs in the background instead of
    // holding up the exit / channel switch (it made 2–4 API calls first).
    unawaited(_persistProgress(force: true, refreshRemote: true).catchError((_) {}));
    // Dispose now (outside the open gate) so a hung open can unblock. Only
    // this local close is tracked by the gate: it frees the provider's single
    // connection. The lease stop is a network call the next lease does not
    // need to wait for — the backend overwrites a same-device lease and
    // releases only by playbackId (leaseStore RELEASE_LEASE_LUA), so a late
    // stop cannot end the new channel (client log 16 Oct, xhzk: 6 s wait).
    final disposing = _disposePlayer();
    PlayerLifecycleGate.track(disposing);
    if (replaceWith != null) {
      // Channel switch: the next open needs the provider's line free first.
      await disposing;
      unawaited(_stopLease());
    } else {
      // Back to the list at once (customers, 4 Nov: a black screen showed
      // while the decoder closed, up to a few seconds). The close keeps
      // running and is tracked by the gate, so the next open still waits.
      unawaited(disposing.catchError((_) {}).whenComplete(_stopLease));
    }
    if (!mounted) return;
    // PopScope canPop must be true before an imperative pop succeeds.
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (replaceWith == null) tvSuppressBack();
      if (replaceWith != null) {
        // Channel switch: the old lease stop is tracked in the lifecycle
        // gate, so the next open waits for the line to be released.
        context.pushReplacement(replaceWith);
        return;
      }
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    });
  }

  /// Concurrent-lease "Manage devices" (C7): navigate immediately; dispose
  /// in background. [go('/settings/devices')] alone left nowhere to pop.
  Future<void> _leaveToManageDevices() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    _silenceAndInvalidate();
    unawaited(
      _persistProgress(force: true, refreshRemote: true).catchError((_) {}),
    );
    final disposing = _disposePlayer();
    PlayerLifecycleGate.track(disposing);
    PlayerLifecycleGate.track(_stopLease());
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      tvSuppressBack();
      context.go('/settings');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.push('/settings/devices');
      });
    });
  }

  bool _onAnyKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    // A live channel that failed: only the remote's CH+ / CH- keys switch
    // channel. Up/Down move between Back / Details / Retry (client 20 Oct,
    // IMG_5013: Up/Down zapped to the next channel, which failed too, and
    // focus jumped back to Back, so Retry could never be reached).
    if (_failed && _isLivePlayback && !_showChannels && !_leaving) {
      final key = event.logicalKey;
      final delta = key == LogicalKeyboardKey.channelUp
          ? 1
          : key == LogicalKeyboardKey.channelDown
              ? -1
              : 0;
      if (delta != 0 && ref.read(liveZapProvider)?.step(widget.id, delta) != null) {
        _zap(delta);
        return true;
      }
    }
    // Two Up presses in a row hide visible controls (client 15 Oct). Only in
    // the player-control context: not while the channel list is open, and
    // not when a dialog/sheet route sits on top of the player.
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final now = DateTime.now();
      final last = _lastUpAt;
      final onTop = ModalRoute.of(context)?.isCurrent ?? true;
      // Only presses made while the controls are already up count, so the
      // Up that brings them up is not half of a "hide" gesture.
      if (!showControls || _showChannels || !onTop || _isLivePlayback) {
        _lastUpAt = null;
      } else if (last != null && now.difference(last) <= _doubleUpWindow) {
        _lastUpAt = null;
        _upHidAt = now;
        _hideControls('up-up');
        return false;
      } else {
        _lastUpAt = now;
      }
    } else {
      _lastUpAt = null;
    }
    // Any remote press keeps visible controls up a little longer.
    if (showControls) _armControlsHide();
    return false;
  }

  static const _doubleUpWindow = Duration(milliseconds: 700);
  static const controlsAutoHide = Duration(seconds: 5);
  DateTime? _lastUpAt;
  /// Set when Up-Up hid the controls: the same press must not also zap the
  /// live channel (the player Up shortcut sees it right after).
  DateTime? _upHidAt;

  void _armControlsHide() {
    _controlsHide?.cancel();
    _controlsHide = Timer(controlsAutoHide, () {
      if (!mounted || !showControls || _leaving) return;
      // Kept while paused (nothing to watch) or failed/loading; an open
      // volume slider no longer pins them forever — it hides with them.
      if (!_ready || _failed || !_playing) return;
      _hideControls('timer');
    });
  }

  void _hideControls([String reason = 'other']) {
    _diag?.pb('CONTROLS hide reason=$reason focus=${FocusManager.instance.primaryFocus?.debugLabel ?? '-'}');
    setState(() {
      showControls = false;
      _showVolumeSlider = false;
      _episodesOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_showChannels) _rootFocus.requestFocus();
    });
  }

  void _showControlsNow() {
    if (!mounted) return;
    // Client 18 Oct TV #2: live channels get the info bar only (quality and
    // time), never the movie control bar.
    if (_isLivePlayback) {
      _showLiveBar();
      return;
    }
    if (!showControls) setState(() => showControls = true);
    _armControlsHide();
  }

  /// True when no control button holds focus (the player root does).
  bool _rootHasFocus() {
    final primary = FocusManager.instance.primaryFocus;
    return primary == null || identical(primary, _rootFocus);
  }

  /// Remote seek: VOD jumps [seconds]; the controls come up so the seek bar
  /// shows the new time (seeking with hidden controls looked like no-op).
  void _remoteSeek(int seconds, {required bool live}) {
    if (live) {
      _showLiveBar();
      return;
    }
    _showControlsNow();
    _seekBy(Duration(seconds: seconds));
    // Movies and series alike (TCL 16 Oct): Left/Right lands on the seek
    // bar, highlighted, so the next presses keep seeking there; no Down
    // first. Down from the bar still reaches the buttons and episodes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !showControls || _seekFocus.context == null) return;
      if (_seekFocus.hasFocus) return;
      _diag?.pb('CONTROLS seek→seekbar');
      _seekFocus.requestFocus();
    });
  }

  void _onOk() {
    // Client 18 Oct TV #2/#3: live has no control bar; OK opens the channel
    // list (OK on a row plays it), or shows the info bar without a list.
    if (_isLivePlayback) {
      final zap = ref.read(liveZapProvider);
      if (!_showChannels && zap != null && zap.channels.length > 1) {
        _openChannels();
      } else if (!_showChannels) {
        _showLiveBar();
      }
      return;
    }
    unawaited(_togglePlay());
  }

  DateTime? _lastBack;

  /// Set when Back closed the channel list: a second Back soon after asks
  /// to leave live TV.
  DateTime? _exitArmedAt;
  /// After Back closes the channel list, the next Back within this window
  /// asks to exit. 3 s was too short at normal remote speed: Back kept
  /// opening and closing the list and the player could not be left (TCL
  /// test 21 Oct). The bar shows "Press Back again to exit" meanwhile.
  static const _exitArmWindow = Duration(seconds: 8);

  void _onBack() {
    if (_leaving) return;
    // Back reaches the player only through PopScope now, so one press is
    // one event. The short guard only absorbs a platform re-delivery.
    final now = DateTime.now();
    final last = _lastBack;
    _lastBack = now;
    if (last != null && now.difference(last) < const Duration(milliseconds: 150)) {
      return;
    }
    final zap = ref.read(liveZapProvider);
    final action = tvBackAction(
      pendingZap: _pendingZap != null,
      listOpen: _showChannels,
      live: _isLivePlayback,
      hasChannelList: zap != null && zap.channels.length > 1,
      failed: _failed,
      ready: _ready,
      exitArmed: _exitArmedAt != null &&
          now.difference(_exitArmedAt!) < _exitArmWindow,
    );
    _exitArmedAt = null;
    _diag?.pb(
      'BACK live=$_isLivePlayback list=$_showChannels ready=$_ready '
      'action=${action.name}',
    );
    switch (action) {
      case TvBackAction.cancelPendingZap:
        _cancelPendingZap();
      case TvBackAction.confirmExit:
        unawaited(_confirmLeave());
      case TvBackAction.openChannelList:
        _openChannels();
      case TvBackAction.closeChannelList:
        _closeChannels();
        _exitArmedAt = now;
        _showLiveBar(hold: _exitArmWindow);
      case TvBackAction.leave:
        tvSuppressBack();
        unawaited(_leavePlayer());
    }
  }

  bool _zapCatsLoading = false;

  Future<void> _loadZapCats() async {
    // Loaded once when it worked; an empty / failed load is tried again the
    // next time the list opens (client 5 Nov: "the packages do not appear" in
    // the channel list inside the player; a failed first load kept it empty).
    if ((_zapCats?.isNotEmpty ?? false) || _zapCatsLoading) return;
    _zapCatsLoading = true;
    try {
      final cats = await ref
          .read(catalogRepositoryProvider)
          .getCategories(MediaKind.live);
      final seen = <String>{};
      // Same section only, as on LG 6.1.21 (client 5 Nov): a sports channel
      // lists the sports packages, a Live TV channel the Live TV packages.
      final mine0 = (_media?.categoryId ?? '').trim();
      final current = cats.where((c) => c.id == mine0).firstOrNull;
      final sport = current != null
          ? RemoteCatalogRepository.isSportsCategory(current)
          : widget.kindHint == MediaKind.sports;
      // A kids channel lists only the kids packages (client 5 Nov, LG photo:
      // Kids showed MBC 4K, NEWS, EGYPT...).
      final kids = current != null &&
          !sport &&
          KidsPanelCategories.looksKids(current.name);
      var list = [
        for (final c in cats)
          if (seen.add(c.id) &&
              (kids
                  ? !RemoteCatalogRepository.isSportsCategory(c) &&
                      KidsPanelCategories.looksKids(c.name)
                  : RemoteCatalogRepository.isSportsCategory(c) == sport))
            c,
      ];
      final pid = ref.read(tvSessionProvider).activeProfileId;
      if (pid != null && pid.isNotEmpty) {
        final ids = await ref.read(categoryOrderStoreProvider).load(pid, 'live');
        list = applyCategoryOrder(list, ids);
      }
      if (!mounted) return;
      final mine = (_media?.categoryId ?? '').trim();
      setState(() {
        _zapCats = list;
        _zapCatId ??= mine.isEmpty ? null : mine;
      });
    } catch (_) {
      if (mounted) setState(() => _zapCats = const []);
    } finally {
      _zapCatsLoading = false;
    }
  }

  /// OK on a package: its channels replace the list (nothing plays).
  Future<void> _openZapCategory(CatalogCategory c) async {
    if (_zapCatLoading) return;
    setState(() {
      _zapCatId = c.id;
      _zapCatLoading = true;
    });
    try {
      final page = await ref.read(catalogRepositoryProvider).browse(
            kind: MediaKind.live,
            categoryId: c.id,
            limit: 400,
          );
      final items = page.items
          .where((m) => !isProviderAdOrHeaderChannel(m.title))
          .toList();
      if (!mounted || items.isEmpty) return;
      ref.read(liveZapProvider.notifier).state =
          LiveZapList(items, title: cleanDisplayName(c.name));
      if (_channelScroll?.hasClients ?? false) _channelScroll!.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // The first row can hold either node (client 9 Nov: OK on a package
        // left the focus there, the requested node was not on screen).
        if (mounted) _zapChannelTarget.requestFocus();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _zapCatLoading = false);
    }
  }

  final FocusNode _zapFirstChannel = FocusNode(debugLabel: 'zap-first');
  final FocusNode _zapCatFocus = FocusNode(debugLabel: 'zap-open-package');

  /// The channel row to land on: the playing one, else the first.
  FocusNode get _zapChannelTarget =>
      _channelFocus.context != null ? _channelFocus : _zapFirstChannel;

  /// Packages come first in reading order: left of the channels in English,
  /// right of them in Arabic.
  bool get _zapRtl => Directionality.of(context) == TextDirection.rtl;
  LogicalKeyboardKey get _zapKeyToPackages => _zapRtl
      ? LogicalKeyboardKey.arrowRight
      : LogicalKeyboardKey.arrowLeft;
  LogicalKeyboardKey get _zapKeyToChannels => _zapRtl
      ? LogicalKeyboardKey.arrowLeft
      : LogicalKeyboardKey.arrowRight;

  void _openChannels() {
    unawaited(_loadZapCats());
    _controlsHide?.cancel();
    final zap = ref.read(liveZapProvider);
    final current = zap?.indexOf(widget.id) ?? -1;
    _channelScroll?.dispose();
    _channelScroll = ScrollController(
      initialScrollOffset: current > 2 ? (current - 2) * _channelRowH : 0,
    );
    setState(() {
      _showChannels = true;
      showControls = false;
      _showVolumeSlider = false;
      _liveBarVisible = false;
    });
    _focusChannelList();
  }

  void _closeChannels() {
    setState(() => _showChannels = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rootFocus.requestFocus();
    });
  }

  void _zap(int delta) {
    if (!_isLivePlayback) {
      _showControlsNow();
      return;
    }
    final zap = ref.read(liveZapProvider);
    final from = _pendingZap?.id ?? widget.id;
    final next = zap?.step(from, delta);
    if (next == null) {
      _showControlsNow();
      return;
    }
    // Remote Up/Down: show the target channel at once and open it only when
    // the presses stop. Each press used to tear down and reopen the player
    // (new lease + decoder), so quick zapping stacked several slow opens.
    setState(() => _pendingZap = next);
    _zapCommit?.cancel();
    _liveBarHide?.cancel();
    _healthTimer?.cancel();
    _channelFocus.dispose();
    _zapFirstChannel.dispose();
    _zapCatFocus.dispose();
    _errorFocus.dispose();
    _zapCommit = Timer(_zapSettle, () {
      final target = _pendingZap;
      if (!mounted || target == null || _leaving) return;
      _zapTo(target);
    });
  }

  static const _zapSettle = Duration(milliseconds: 900);
  MediaItem? _pendingZap;
  Timer? _zapCommit;

  void _cancelPendingZap() {
    _zapCommit?.cancel();
    _zapCommit = null;
    if (mounted) setState(() => _pendingZap = null);
  }

  bool _liveBarVisible = false;
  Timer? _liveBarHide;
  bool _volumeFlash = false;

  /// Live info bar (client 16 Oct): shown by the first Up/Down, then each
  /// press changes the channel. Clean and minimal: number, name, quality,
  /// time; volume while Left/Right adjust it. Hides after 5 s.
  void _showLiveBar({bool volume = false, Duration? hold}) {
    if (!mounted) return;
    setState(() {
      _liveBarVisible = true;
      if (volume) _volumeFlash = true;
    });
    _liveBarHide?.cancel();
    _liveBarHide = Timer(hold ?? controlsAutoHide, () {
      if (!mounted) return;
      setState(() {
        _liveBarVisible = false;
        _volumeFlash = false;
      });
    });
  }

  /// Live Left/Right: app volume in 10 % steps.
  void _nudgeVolume(double delta) {
    final next = ((_volume + delta) * 10).round() / 10;
    unawaited(_setVolume(next));
    _showLiveBar(volume: true);
  }

  Widget _liveInfoBar(LiveZapList? zap) {
    MediaItem? current;
    final i = zap?.indexOf(widget.id) ?? -1;
    if (zap != null && i >= 0) current = zap.channels[i];
    final ch = _pendingZap ?? current;
    final idx = ch == null ? -1 : (zap?.indexOf(ch.id) ?? -1);
    final name = ch?.displayTitle ?? _title;
    final clock = tvClockNow(context);
    final quality = _pendingZap == null ? _videoQualityLabel() : null;
    final muted = _volume <= 0;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 0, 48, 36),
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: TvGlassStyle.surface(
                radius: BorderRadius.circular(18),
              ).copyWith(color: Colors.black.withValues(alpha: 0.72)),
              child: Row(
                children: [
                  if (idx >= 0) ...[
                    Text(
                      '${idx + 1}',
                      style: TextStyle(
                        color: AppColors.cyan,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 18),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_exitArmedAt != null &&
                            DateTime.now().difference(_exitArmedAt!) <
                                _exitArmWindow)
                          Text(
                            _copy.pressBackAgainToExit,
                            style: TextStyle(
                              color: AppColors.cyan,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_volumeFlash) ...[
                    Icon(
                      muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      size: 22,
                      color: AppColors.cyan,
                    ),
                    const SizedBox(width: 8),
                    // Client 18 Oct TV #4: in Arabic the bar filled from
                    // the right, so Right (louder) looked like quieter.
                    SizedBox(
                      width: 120,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: LinearProgressIndicator(
                            value: _volume.clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: Colors.white24,
                            color: AppColors.cyan,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${(_volume * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 18),
                  ],
                  if (quality != null) ...[
                    _playerTechChip(quality, accent: AppColors.cyan),
                    const SizedBox(width: 14),
                  ],
                  const TechBadge('LIVE', tone: BadgeTone.live, compact: true),
                  const SizedBox(width: 14),
                  Text(
                    clock,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Expected cancellation (Back, channel change, newer open), as opposed to
  /// a network / authorization / decoder failure. Both the open gate and the
  /// lease manager throw StateError('… cancelled') for this.
  bool _isCancellation(Object e) {
    if (_leaving || !mounted) return true;
    return e is StateError && e.message.toLowerCase().contains('cancelled');
  }

  Timer? _healthTimer;
  bool _confirmOpen = false;
  int _teardownWaitMs = 0;
  final FocusNode _channelFocus = FocusNode(debugLabel: 'tv-channel-current');

  /// Exit confirmation (client 16 Oct #5/#16): playback never closes on a
  /// single Back. Duplicate Back events from the TV (key + system back)
  /// arriving in the first 600 ms do not dismiss it.
  Future<void> _confirmLeave() async {
    if (_confirmOpen || _leaving) return;
    _confirmOpen = true;
    _controlsHide?.cancel();
    final opened = DateTime.now();
    final copy = _copy;
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (DateTime.now().difference(opened) <
              const Duration(milliseconds: 600)) {
            return;
          }
          Navigator.of(ctx).pop(false);
        },
        child: Dialog(
          backgroundColor: const Color(0xFF1A1F2A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
              child: FocusTraversalGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.playerExitTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      copy.playerExitMessage,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TvButton(
                          autofocus: true,
                          label: copy.cancel,
                          onTap: () => Navigator.of(ctx).pop(false),
                        ),
                        const SizedBox(width: TvUi.buttonGap),
                        TvButton(
                          primary: true,
                          icon: Icons.logout_rounded,
                          label: copy.playerExitConfirm,
                          onTap: () => Navigator.of(ctx).pop(true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _confirmOpen = false;
    if (!mounted) return;
    if (leave == true) {
      tvSuppressBack();
      unawaited(_leavePlayer());
      return;
    }
    // Cancel: back to where the user was (list row or the picture).
    _lastBack = DateTime.now();
    if (_showChannels) {
      _focusChannelList();
    } else {
      _rootFocus.requestFocus();
      if (showControls) _armControlsHide();
    }
  }

  /// Moves remote focus into the channel list. `autofocus` on the row was
  /// ignored because the player root already held focus, so Up/Down kept
  /// zapping behind the list and OK did nothing (client 16 Oct #13).
  void _focusChannelList() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showChannels) return;
      if (_channelFocus.context != null) _channelFocus.requestFocus();
    });
  }

  void _zapTo(MediaItem channel) {
    if (channel.id == widget.id) {
      if (_showChannels) _closeChannels();
      return;
    }
    _diag?.pb('ZAP to=${channel.id}');
    final name = channel.displayTitle.trim();
    final titleQ = name.isNotEmpty
        ? '&title=${Uri.encodeQueryComponent(name)}'
        : '';
    unawaited(
      _leavePlayer(replaceWith: '/player/${channel.id}?kind=live$titleQ'),
    );
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
    );
    if (!mounted || _leaving || !identical(_player, player)) {
      throw StateError('Playback cancelled');
    }
  }

  Future<void> _awaitOpenStep(Future<void> operation) async {
    final cancelled = _openCancelled;
    await Future.any<void>([
      operation,
      if (cancelled != null)
        cancelled.future.then<void>(
          (_) => throw StateError('Playback cancelled'),
        ),
    ]).timeout(const Duration(seconds: 30));
  }

  void _startStallWatchdog(Player player) {
    _stallWatchdog?.cancel();
    _lastPlaybackAdvance = DateTime.now();
    var previous = player.state.position;
    _stallWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _leaving || !identical(_player, player)) return;
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
        if (mounted) setState(() => _playing = playing);
      }),
    );
    _subs.add(
      player.stream.buffering.listen((b) {
        if (!mounted || !identical(_player, player)) return;
        _diag?.onBuffering(b);
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
    final prefs = await SharedPreferences.getInstance();
    final rawAudio = prefs.getString('tv_audio') ?? 'Dolby Atmos · English';
    final pref = _mapTvAudioPref(rawAudio);
    final wantAudio = appPreferAudio(_audioTracks, pref);
    if (wantAudio != null && wantAudio.id != player.state.track.audio.id) {
      await player.setAudioTrack(wantAudio);
    }
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

  /// Settings labels → shared [playbackMaxHeightFor] keys.
  static String _mapTvQualityPref(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.contains('720')) return '720p';
    if (q.contains('1080')) return '1080p';
    if (q.contains('data')) return 'Data saver';
    if (q.contains('original')) return 'Original';
    return 'Auto';
  }

  static String _mapTvAudioPref(String raw) {
    final a = raw.trim().toLowerCase();
    if (a.contains('atmos')) return 'Dolby Atmos';
    if (a.contains('spanish')) return 'Spanish';
    if (a.contains('stereo')) return 'English';
    return 'Dolby Atmos';
  }

  void _ensureProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || !_playing || !_ready) return;
      _persistProgress();
    });
  }

  String? _providerAuthUrl;

  /// Log into the provider from this TV before streaming, like a standard
  /// Xtream player (the backend logs in from its own server IP).
  Future<void> _loginProviderFromDevice() async {
    final url = _providerAuthUrl;
    if (url == null || url.isEmpty) {
      _diag?.pb('PROVIDER_LOGIN skipped (backend sent no providerAuthUrl)');
      return;
    }
    final r = await loginProviderFromDevice(url, headers: _httpHeaders);
    _diag?.pb('PROVIDER_LOGIN $r');
  }

  /// Scheme that opened last time (http/https), so a renewed lease reopens
  /// on the URL that works on this network.
  String? _preferredScheme;

  String _preferredUrl(PlaybackSessionDto lease) {
    final want = _preferredScheme;
    if (want == null) return lease.playUrl;
    for (final u in [lease.playUrl, ...lease.alternatePlayUrls]) {
      if (Uri.tryParse(u)?.scheme == want) return u;
    }
    return lease.playUrl;
  }

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

  /// Shown on the loading screen while waiting for a busy line.
  String? _waitingLabel;
  Timer? _waitingTicker;

  /// The provider keeps a closed connection counted for a while (HTTP 456
  /// right after another app or the previous title stopped). Keep the
  /// loading screen up and retry until the line is free, for up to ~90 s.
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

  /// Sends one scrubbed report of this attempt to the backend (Monitor page).
  /// Best effort: never blocks or throws.
  Future<void> _sendPlaybackReport(String event) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      final failed = event != 'open_ok';
      final lines = DiagTrail.lines;
      final tail = failed || lines.length <= 60
          ? lines
          : lines.sublist(lines.length - 60);
      var device = tvDeviceSummary();
      if (device.length > 600) device = device.substring(0, 600);
      final body = <String, Object?>{
        'deviceId': deviceId,
        'event': event,
        'contentType': _contentType,
        'streamId': widget.id,
        'code': failed ? _clip(tvPlaybackErrorCode(), 300) : null,
        'message': failed ? _clip(_error, 300) : null,
        'engine': _nativePlayer != null ? 'native' : 'mpv',
        'elapsedMs': _diag?.msSinceTap(),
        'app': await tvAppVersionLabel(),
        'device': device,
        'lines': tail,
      };
      await ref
          .read(tvMediaRepositoryProvider)
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
    bool forceMpv = false,
  }) {
    return _enqueueOpen((gen) => _openNetworkNow(
          url,
          label: label,
          gen: gen,
          forceNative: forceNative,
          forceMpv: forceMpv,
        ));
  }

  /// The Android engine is the TV default; when it cannot open a stream for a
  /// reason another engine might get past, try mpv once.
  static bool _mpvMayHelp(AppFailureKind? kind) => switch (kind) {
        AppFailureKind.authorization => false,
        AppFailureKind.notFound => false,
        AppFailureKind.connectionLimit => false,
        AppFailureKind.upstream => false,
        _ => true,
      };

  /// One open on the Android ExoPlayer engine after the MPV open failed, for
  /// failures another engine can plausibly get past. Never for server
  /// answers that would be the same on any engine.
  Future<bool> _shouldTryNativeFallback(AppFailureKind? kind) async {
    // No second engine to fall back to where mpv is missing (Samsung, LG).
    if (!TvPlatformProfile.nativeEngineAvailable ||
        !TvPlatformProfile.mpvAvailable) {
      return false;
    }
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
    return !await AppDecoderPreferences.nativeEngine(tv: true);
  }

  Future<bool> _openNetworkNow(
    String url, {
    required String label,
    required int gen,
    bool forceNative = false,
    bool forceMpv = false,
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
      // Without mpv (Samsung, LG) the native engine is the only engine.
      final nativeSelected = TvPlatformProfile.nativeEngineAvailable &&
          (!TvPlatformProfile.mpvAvailable ||
              (!forceMpv &&
                  (forceNative ||
                      await AppDecoderPreferences.nativeEngine(tv: true))));
      if (!mounted || gen != _openGen) return false;
      if (nativeSelected) return await _openNativeNetwork(url, gen: gen);
      final decoderMode = await AppDecoderPreferences.load(tv: true);
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
        forTv: true,
      );

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
      // Mute until video params exist (same idea as mobile buffer gate +
      // TV native mute-prime): audio must not lead a cold 4K decode.
      await player.setVolume(0);
      await player.setRate(_speed);
      _pb.setPhase(PlaybackPhase.initialBuffering);
      if (!mounted || gen != _openGen) return false;
      _syncTracksFromPlayer(player);
      // Match mobile: ~1.8s demuxer + first frame before audible play.
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
      await _waitUntilReady(player,
        requireSurfaceDecoder: decoderMode == AppDecoderMode.androidSurface,
        failure: failureMonitor.fatalBeforeFirstFrame,
      ).timeout(const Duration(seconds: 20));
      failureMonitor.markFirstFrame();
      timeline.mark('videoParams');
      if (!mounted || gen != _openGen) return false;
      await player.setVolume(_volume * 100);
      _diag!.pb(
        'VIDEO_OUTPUT_READY +${_diag!.msSinceTap()} '
        'openMs=+${msSinceOpen()}ms '
        'w=${player.state.width} dur=${player.state.duration.inSeconds}s',
      );
      _pb.setPhase(PlaybackPhase.playing);
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
        _playbackEnded = false;
        // Live: clean picture until a deliberate press (client 15 Oct).
        if (_isLivePlayback) showControls = false;
        _sourceLabelKey = label;
        _error = null;
        _position = player!.state.position;
        _duration = player.state.duration;
        _resumeSeekDone = false;
      });
      _positionN.value = player.state.position;
      _durationN.value = player.state.duration;
      _ensureProgressTimer();
      if (showControls) _armControlsHide();
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
        await AppDecoderPreferences.save(AppDecoderMode.auto, tv: true);
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
      if (_isCancellation(e) || gen != _openGen) {
        if (gen == _openGen) await _disposePlayer();
        _diag?.pb('CANCELLED phase=openingMedia ${timeline.line}');
        return false;
      }
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
      unawaited(
        _recoverOrFail(
          player,
          _midPlayFailureKind ?? AppFailureKind.prematureEof,
          'eof',
        ),
      );
      return;
    }
    _diag?.pb('PLAYBACK_COMPLETED pos=${pos.inSeconds}s dur=${dur.inSeconds}s');
    unawaited(_persistProgress(force: true));
    if (!mounted) return;
    setState(() {
      _playbackEnded = true;
      _playing = false;
    });
    _showControlsNow();
    _armAutoNext();
  }

  bool get _hasNextEpisode =>
      _isEpisode && _episodeIndex + 1 < _episodePlaylist.length;

  void _armAutoNext() {
    _cancelAutoNext();
    if (!_hasNextEpisode || !ref.read(tvSessionProvider).autoplay) return;
    setState(() => _autoNextLeft = _autoNextSeconds);
    _autoNext = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || !_playbackEnded || _leaving) {
        _cancelAutoNext();
        return;
      }
      if (_autoNextLeft <= 1) {
        _cancelAutoNext();
        _nextEpisode();
        return;
      }
      setState(() => _autoNextLeft--);
    });
  }

  void _cancelAutoNext() {
    _autoNext?.cancel();
    _autoNext = null;
    _autoNextLeft = 0;
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
    );
    _nativePlayer = controller;
    _stats.attachNative();
    _diag?.pb('NATIVE_ENGINE_OPEN view=texture frames=surfaceTexture');
    // Stop waiting as soon as the player is closed or the channel changes.
    // A plain initialize() kept a left channel's open alive for its full
    // 30 s, and the next channel queued behind it (TCL log 15 Oct: 18 s).
    _openCancelled ??= Completer<void>();
    await _awaitOpenStep(controller.initialize());
    if (!mounted || gen != _openGen || !identical(_nativePlayer, controller)) return false;
    if (controller.value.size.width <= 0 || controller.value.size.height <= 0) {
      throw StateError('Android player could not initialize video');
    }
    if (!mounted || gen != _openGen) return false;
    final start = _resumeStartSec;
    if (start != null && start > 5) await controller.seekTo(Duration(seconds: start));
    if (!mounted || gen != _openGen) return false;
    await controller.setVolume(0);
    await controller.setPlaybackSpeed(_speed);
    // Prime one frame muted so ExoPlayer does not lead with audio-only.
    await controller.play();
    final primed = DateTime.now();
    while (DateTime.now().difference(primed) < const Duration(seconds: 4)) {
      if (!mounted || gen != _openGen || !identical(_nativePlayer, controller)) {
        return false;
      }
      final v = controller.value;
      // Live may report position 0; size + not buffering is enough.
      if (v.isInitialized && v.size.width > 0 && !v.isBuffering) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted || gen != _openGen || !identical(_nativePlayer, controller)) {
      return false;
    }
    await controller.pause();
    await controller.setVolume(_volume);
    // Playback health (client 16 Oct: "NATIVE_ENGINE_INITIALIZED" is not a
    // first frame). First advance = position moving while playing; rebuffer
    // count/time and process memory every 30 s while this player is current.
    final openedAt = DateTime.now(); // engine initialized (not opened)
    TvFrameStats.instance
      ..ensureStarted()
      ..take();
    Duration? firstPos;
    var firstAdvanceLogged = false;
    var rebuffers = 0;
    var rebufferMs = 0;
    DateTime? bufferingSince;
    var wasBuffering = false;
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || gen != _openGen || !identical(_nativePlayer, controller)) {
        return;
      }
      final v = controller.value;
      final stillMs = bufferingSince == null
          ? 0
          : DateTime.now().difference(bufferingSince!).inMilliseconds;
      _diag?.pb(
        'NATIVE_HEALTH pos=${v.position.inSeconds}s playing=${v.isPlaying} '
        'rebuffers=$rebuffers rebufferMs=${rebufferMs + stillMs} '
        // ProcessInfo is dart:io: not on the LG (web) build.
        'rssMb=${kIsWeb ? '-' : (ProcessInfo.currentRss / 1048576).round()} '
        '${TvFrameStats.instance.take()}',
      );
    });
    controller.addListener(() {
      if (!mounted || gen != _openGen || !identical(_nativePlayer, controller)) {
        return;
      }
      final value = controller.value;
      _stats
        ..reportBuffering(value.isBuffering, playing: value.isPlaying)
        ..reportNativeSize(value.size.width.round(), value.size.height.round());
      if (!firstAdvanceLogged && value.isPlaying && !value.isBuffering) {
        firstPos ??= value.position;
        if (value.position - firstPos! >= const Duration(milliseconds: 200) ||
            (_isLivePlayback && value.position > Duration.zero)) {
          firstAdvanceLogged = true;
          _diag?.pb(
            'NATIVE_FIRST_ADVANCE +${_diag!.msSinceTap()}ms '
            'sinceInitialized=${DateTime.now().difference(openedAt).inMilliseconds}ms',
          );
        }
      }
      // Web (LG): the TV can start the stream (sound plays) while the play()
      // call has not returned yet; the loading overlay then stayed on screen
      // (client photo, 26 Oct). Playback actually advancing is ready enough.
      if (kIsWeb && firstAdvanceLogged && !_ready && !_failed) {
        setState(() {
          _ready = true;
          _surfaceMounted = true;
          if (_isLivePlayback) showControls = false;
        });
      }
      if (firstAdvanceLogged) {
        if (value.isBuffering && !wasBuffering) {
          rebuffers++;
          bufferingSince = DateTime.now();
          _diag?.pb('NATIVE_REBUFFER start n=$rebuffers pos=${value.position.inSeconds}s');
        } else if (!value.isBuffering && wasBuffering && bufferingSince != null) {
          final ms = DateTime.now().difference(bufferingSince!).inMilliseconds;
          rebufferMs += ms;
          bufferingSince = null;
          _diag?.pb('NATIVE_REBUFFER end ms=$ms');
        }
        wasBuffering = value.isBuffering;
      }
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
      final dur = value.duration;
      if (!_playbackEnded &&
          !_isLivePlayback &&
          dur > Duration.zero &&
          value.position >= dur - const Duration(milliseconds: 400) &&
          !value.isPlaying) {
        _diag?.pb(
          'PLAYBACK_COMPLETED pos=${value.position.inSeconds}s '
          'dur=${dur.inSeconds}s engine=native',
        );
        unawaited(_persistProgress(force: true));
        setState(() {
          _playbackEnded = true;
          _playing = false;
        });
        _showControlsNow();
        _armAutoNext();
        return;
      }
      final now = DateTime.now();
      if (playingChanged ||
          bufferingChanged ||
          _lastPosUi == null ||
          now.difference(_lastPosUi!) >= _posUiInterval) {
        _lastPosUi = now;
        _positionN.value = value.position;
        _durationN.value = value.duration;
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
      _playbackEnded = false;
      _surfaceMounted = true;
      // Live: clean picture until a deliberate press (client 15 Oct).
      if (_isLivePlayback) showControls = false;
    });
    // VOD starts with the controls up: start the 5 s auto-hide now, not
    // only after the first key press.
    if (showControls) _armControlsHide();
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

  /// Demo playback: the demo catalog's own stream URL, no backend lease.
  Future<bool> _openDemoPlayback() async {
    try {
      final catalog = ref.read(catalogRepositoryProvider);
      final seriesKey = (widget.seriesId != null && widget.seriesId!.isNotEmpty)
          ? widget.seriesId
          : catalog.knownSeriesIdForEpisode(widget.id);
      MediaItem? item;
      String? url;
      Future<void> useEpisode(MediaItem? series, String sid, Episode ep) async {
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
        final found = await catalog.getById(widget.id, kind: widget.kindHint);
        if (found != null && found.kind == MediaKind.series) {
          final eps = await catalog.getEpisodes(found.id, season: 1);
          if (eps.isNotEmpty) await useEpisode(found, found.id, eps.first);
        } else {
          item = found;
          url = found?.streamUrl;
        }
      }
      final u = url;
      if (!mounted || u == null || u.isEmpty) return false;
      final m = item;
      _media = m;
      _contentType = m != null && (m.isLive || m.kind == MediaKind.live) ? 'live' : 'vod';
      _title = _bestStreamTitle(item: m);
      _diag = PlaybackDiagSession();
      _pb.beginSession(_diag!.sid);
      _diag!.pb('PLAY demo content=${widget.id}');
      return await _openNetwork(u, label: 'APP');
    } catch (e) {
      Diag.err('demo playback', e);
      return false;
    }
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
    MediaItem? series;
    try {
      series = await catalog.getById(seriesId, kind: MediaKind.series);
    } catch (_) {}
    if (!mounted) return;
    _seriesArt = series?.backdropUrl ?? series?.posterUrl;
    final idx = all.indexWhere((e) => e.id == episodeId);
    // Strip opens with the playing episode in view (one card before it).
    var inSeason = 0;
    if (idx >= 0) {
      for (var i = 0; i < idx; i++) {
        if (all[i].season == all[idx].season) inSeason++;
      }
    }
    _episodeScroll?.dispose();
    _episodeScroll = ScrollController(
      initialScrollOffset: (inSeason > 0 ? inSeason - 1 : 0) *
          (_episodeCardW + _episodeGap),
    );
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
    _diag?.pb('PLAYPAUSE toggle playing=$_playing');
    if (_playbackEnded) {
      await _replayFromStart();
      return;
    }
    final player = _player;
    if (player == null) {
      final n = _nativePlayer;
      if (n == null) return;
      if (n.value.isPlaying) {
        _userPaused = true;
        await n.pause();
        setState(() => _playing = false);
        await _persistProgress(force: true);
      } else {
        _userPaused = false;
        _lastPlaybackAdvance = DateTime.now();
        await n.play();
        setState(() => _playing = true);
      }
      _showControlsNow();
      return;
    }
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
    if (!mounted) return;
    _showControlsNow();
  }

  void _seekBy(Duration delta) {
    if (!_ready) return;
    final native = _nativePlayer;
    final player = _player;
    if (native == null && player == null) return;
    final base = _seekTarget ??
        (native?.value.position ?? player!.state.position);
    final dur = native?.value.duration ?? player!.state.duration;
    final next = base + delta;
    final clamped = next < Duration.zero
        ? Duration.zero
        : (dur > Duration.zero && next > dur ? dur : next);
    setState(() => _seekTarget = clamped);
    if (showControls) _armControlsHide();
    _seekDebounce?.cancel();
    _seekDebounce = Timer(const Duration(milliseconds: 450), _flushSeek);
  }

  Future<void> _flushSeek() async {
    final target = _seekTarget;
    if (target == null || !mounted) return;
    if (_seekInFlight) {
      // Previous seek still running: try again shortly with the latest target.
      _seekDebounce = Timer(const Duration(milliseconds: 250), _flushSeek);
      return;
    }
    await _seekSafely(target);
    if (!mounted) return;
    final dur = _nativePlayer?.value.duration ??
        _player?.state.duration ??
        Duration.zero;
    setState(() {
      if (identical(_seekTarget, target)) _seekTarget = null;
      if (_isLivePlayback) {
        _userBehindLive =
            dur > Duration.zero && target < dur - _liveEdgeTolerance;
      }
    });
    if (!_isLivePlayback) unawaited(_persistProgress());
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

  void _scheduleHideVolume() {
    _hideVolume?.cancel();
    _hideVolume = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showVolumeSlider = false);
    });
  }

  void _toggleControls() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (showControls) {
        _hideControls('toggle');
      } else {
        _showControlsNow();
      }
    });
  }

  void _goEpisode(int delta) {
    if (!_isEpisode) return;
    _playEpisodeAt(_episodeIndex + delta);
  }

  /// Opens playlist entry [index] (strip card, prev/next). The current one
  /// just returns focus to Play.
  void _playEpisodeAt(int index) {
    if (!_isEpisode || index < 0 || index >= _episodePlaylist.length) return;
    if (index == _episodeIndex) {
      _playFocus.requestFocus();
      _armControlsHide();
      return;
    }
    _diag?.pb('EPISODE pick from=$_episodeIndex to=$index');
    final ep = _episodePlaylist[index];
    final series = _resolvedSeriesId ?? widget.seriesId ?? '';
    final q = series.isNotEmpty
        ? '?kind=series&seriesId=$series'
        : '?kind=series';
    context.pushReplacement('/player/${ep.id}$q');
  }

  void _nextEpisode() => _goEpisode(1);

  Future<void> _replayFromStart() async {
    _cancelAutoNext();
    setState(() => _playbackEnded = false);
    await _seekSafely(Duration.zero);
    final p = _player;
    final n = _nativePlayer;
    if (p != null) {
      await p.play();
    } else if (n != null) {
      await n.play();
    }
    if (mounted) setState(() => _playing = true);
  }

  AppCopy get _copy => AppCopy.ofLanguage(ref.read(tvLanguageProvider));

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

  /// D-pad-friendly dialog (AlertDialog + FocusTile rows).
  Future<T?> _showPlayerDialog<T>({
    required String title,
    required List<Widget> children,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
        actions: [
          FocusTile(
            borderRadius: 10,
            onTap: () => Navigator.pop(ctx),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                _copy.cancel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSubtitles() async {
    final player = _player;
    if (player != null) _syncTracksFromPlayer(player, applyPrefs: false);
    final copy = _copy;
    await _showPlayerDialog<void>(
      title: copy.subtitles,
      children: [
        FocusTile(
          autofocus: !_subsOn,
          borderRadius: 10,
          onTap: () async {
            await _player?.setSubtitleTrack(SubtitleTrack.no());
            setState(() => _subtitleTrack = SubtitleTrack.no());
            if (mounted) Navigator.pop(context);
          },
          child: ListTile(
            title: Text(copy.off),
            trailing: !_subsOn
                ? Icon(Icons.check, color: AppColors.cyan)
                : null,
          ),
        ),
        for (var i = 0; i < _subtitleTracks.length; i++)
          FocusTile(
            autofocus: _subsOn && _subtitleTracks[i].id == _subtitleTrack?.id,
            borderRadius: 10,
            onTap: () async {
              final t = _subtitleTracks[i];
              await _player?.setSubtitleTrack(t);
              setState(() => _subtitleTrack = t);
              if (mounted) Navigator.pop(context);
            },
            child: ListTile(
              title: Text(_subLabel(_subtitleTracks[i])),
              trailing: _subtitleTracks[i].id == _subtitleTrack?.id
                  ? Icon(Icons.check, color: AppColors.cyan)
                  : null,
            ),
          ),
        if (_subtitleTracks.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              copy.noEmbeddedSubtitles,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openSettings() async {
    final player = _player;
    if (player != null) _syncTracksFromPlayer(player, applyPrefs: false);
    final copy = _copy;
    await _showPlayerDialog<void>(
      title: copy.settings,
      children: [
        FocusTile(
          autofocus: true,
          borderRadius: 10,
          onTap: () async {
            Navigator.pop(context);
            await _pickSpeed();
          },
          child: ListTile(
            leading: Icon(Icons.speed_rounded, color: AppColors.cyan),
            title: Text(copy.playbackSpeed),
            subtitle: Text('${_speed}x'),
          ),
        ),
        FocusTile(
          borderRadius: 10,
          onTap: () async {
            Navigator.pop(context);
            await _pickQuality();
          },
          child: ListTile(
            leading: Icon(
              Icons.high_quality_rounded,
              color: AppColors.cyan,
            ),
            title: Text(copy.quality),
            subtitle: Text(_qualitySubtitle(copy)),
          ),
        ),
        FocusTile(
          borderRadius: 10,
          onTap: () {
            setState(() => _videoFill = !_videoFill);
            Navigator.pop(context);
            _toggleControls();
          },
          child: ListTile(
            leading: Icon(
              _videoFill
                  ? Icons.fit_screen_rounded
                  : Icons.aspect_ratio_rounded,
              color: AppColors.cyan,
            ),
            title: Text(_videoFill ? _copy.videoModeZoom : _copy.videoModeFit),
            subtitle: Text(
              _videoFill
                  ? _copy.videoModeZoomHint
                  : _copy.videoModeFitHint,
            ),
          ),
        ),
        // Slow starts that end up playing never reached the error screen,
        // so their timing report could not be opened on the TV.
        FocusTile(
          borderRadius: 10,
          onTap: () {
            Navigator.pop(context);
            unawaited(showTvPlaybackDiagnostics(
              context,
              userMessage: _error,
              contentId: widget.id,
            ));
          },
          child: ListTile(
            leading: Icon(
              Icons.receipt_long_rounded,
              color: AppColors.cyan,
            ),
            title: Text(_copy.playbackDetails),
            subtitle: Text(_copy.playbackDetailsHint),
          ),
        ),
        FocusTile(
          borderRadius: 10,
          onTap: () async {
            Navigator.pop(context);
            await _pickAudio();
          },
          child: ListTile(
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
          ),
        ),
        FocusTile(
          borderRadius: 10,
          onTap: () async {
            Navigator.pop(context);
            await _pickSubtitles();
          },
          child: ListTile(
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
          ),
        ),
      ],
    );
  }

  Future<void> _pickSpeed() async {
    await _showPlayerDialog<void>(
      title: _copy.playbackSpeed,
      children: [
        for (var i = 0; i < _speeds.length; i++)
          FocusTile(
            autofocus: _speeds[i] == _speed,
            borderRadius: 10,
            onTap: () async {
              await _setSpeed(_speeds[i]);
              if (mounted) Navigator.pop(context);
            },
            child: ListTile(
              title: Text('${_speeds[i]}x'),
              trailing: _speeds[i] == _speed
                  ? Icon(Icons.check, color: AppColors.cyan)
                  : null,
            ),
          ),
      ],
    );
  }

  Future<void> _pickAudio() async {
    final player = _player;
    if (player != null) _syncTracksFromPlayer(player, applyPrefs: false);
    final copy = _copy;
    await _showPlayerDialog<void>(
      title: copy.audio,
      children: [
        for (var i = 0; i < _audioTracks.length; i++)
          FocusTile(
            autofocus: _audioTracks[i].id == _audioTrack?.id,
            borderRadius: 10,
            onTap: () async {
              final t = _audioTracks[i];
              await _player?.setAudioTrack(t);
              setState(() => _audioTrack = t);
              if (mounted) Navigator.pop(context);
            },
            child: ListTile(
              title: Text(_trackLabel(_audioTracks[i])),
              trailing: _audioTracks[i].id == _audioTrack?.id
                  ? Icon(Icons.check, color: AppColors.cyan)
                  : null,
            ),
          ),
        if (_audioTracks.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              copy.noEmbeddedAudio,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _pickQuality() async {
    final player = _player;
    if (player != null) _syncTracksFromPlayer(player, applyPrefs: false);
    final copy = _copy;
    final autoSelected =
        _videoTrack == null ||
        _videoTrack!.id == 'auto' ||
        !appIsSelectableTrackId(_videoTrack!.id);
    await _showPlayerDialog<void>(
      title: copy.quality,
      children: [
        FocusTile(
          autofocus: autoSelected,
          borderRadius: 10,
          onTap: () async {
            await _player?.setVideoTrack(VideoTrack.auto());
            setState(() => _videoTrack = VideoTrack.auto());
            if (mounted) Navigator.pop(context);
          },
          child: ListTile(
            title: Text(copy.qualityAuto),
            subtitle: Text(_localizedSource(copy)),
            trailing: autoSelected
                ? Icon(Icons.check, color: AppColors.cyan)
                : null,
          ),
        ),
        for (var i = 0; i < _videoTracks.length; i++)
          FocusTile(
            autofocus: !autoSelected && _videoTracks[i].id == _videoTrack?.id,
            borderRadius: 10,
            onTap: () async {
              final t = _videoTracks[i];
              await _player?.setVideoTrack(t);
              setState(() => _videoTrack = t);
              if (mounted) Navigator.pop(context);
            },
            child: ListTile(
              title: Text(_videoLabel(_videoTracks[i])),
              trailing: _videoTracks[i].id == _videoTrack?.id
                  ? Icon(Icons.check, color: AppColors.cyan)
                  : null,
            ),
          ),
        if (_videoTracks.length <= 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              copy.noAlternateQuality,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
      ],
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
    HardwareKeyboard.instance.removeHandler(_onAnyKey);
    _autoNext?.cancel();
    _controlsHide?.cancel();
    _seekDebounce?.cancel();
    _zapCommit?.cancel();
    _channelScroll?.dispose();
    _episodeScroll?.dispose();
    _currentEpisodeFocus.dispose();
    _rootFocus.dispose();
    _playFocus.dispose();
    _seekFocus.dispose();
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
    final player = _player;
    final native = _nativePlayer;
    final media = _media;
    final lib = _library;
    if (!_leaving &&
        !_cleanupQueued &&
        !_isLivePlayback &&
        _resumeSeekDone &&
        (player != null || native != null) &&
        _ready &&
        media != null &&
        lib != null) {
      // The Android player is the TV default: save its position too, not
      // only mpv's, or Continue Watching keeps an older point.
      final durMs =
          (native?.value.duration ?? player!.state.duration).inMilliseconds;
      if (durMs > 0) {
        final posMs =
            (native?.value.position ?? player!.state.position).inMilliseconds;
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

      // Gate = local player close only (provider connection); see
      // _leavePlayer for why the lease stop is not awaited by the next open.
      PlayerLifecycleGate.track(disposing);
      unawaited(() async {
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
    for (final subscription in _subs) {
      unawaited(subscription.cancel());
    }
    _subs.clear();
    _pb.dispose();
    _positionN.dispose();
    _durationN.dispose();
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
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m '
          '${s.toString().padLeft(2, '0')}s';
    }
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  Future<void> _goLive() async {
    final native = _nativePlayer;
    final p = _player;
    final dur = native?.value.duration ?? p?.state.duration ?? Duration.zero;
    if (dur > Duration.zero) {
      await _seekSafely(dur);
    }
    if (mounted) setState(() => _userBehindLive = false);
  }

  Widget _iconControl({
    required IconData icon,
    required VoidCallback onTap,
    double size = 44,
    double iconSize = 28,
    bool autofocus = false,
  }) {
    return FocusTile(
      autofocus: autofocus,
      borderRadius: size / 2,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: iconSize),
      ),
    );
  }

  Widget _playerTechChip(String label, {Color? accent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (accent ?? Colors.white).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (accent ?? Colors.white).withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: accent ?? Colors.white,
        ),
      ),
    );
  }

  Widget _playerUpNextChip() {
    if (!_playbackEnded || !_isEpisode) return const SizedBox.shrink();
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Align(
      alignment: rtl ? Alignment.centerLeft : Alignment.centerRight,
      child: FocusTile(
        borderRadius: 12,
        onTap: _nextEpisode,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.cyan.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.skip_next_rounded, color: AppColors.cyan, size: 22),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (_autoNextLeft > 0
                            ? _copy.nextEpisodeIn(_autoNextLeft)
                            : _copy.next)
                        .toUpperCase(),
                    style: TextStyle(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 0.6,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    // The episode that plays next (it showed the one
                    // that just ended).
                    child: Text(
                      _hasNextEpisode
                          ? _episodePlaylist[_episodeIndex + 1].title
                          : _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom-left: tech chips + wifi + clock (was the old top status strip).
  /// Resolution of the picture actually decoded (null until known).
  String? _videoQualityLabel() {
    final native = _nativePlayer;
    final h = native != null
        ? native.value.size.height
        : (_player?.state.height ?? 0).toDouble();
    if (h <= 0) return null;
    if (h >= 1600) return '4K UHD';
    if (h >= 1000) return 'FULL HD';
    if (h >= 700) return 'HD';
    return '${h.round()}p';
  }

  Widget _playerBottomMeta() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Only what the decoder reports. "4K UHD · HDR10+ · ATMOS" used to
          // be fixed text on every stream, HD ones included.
          if (_videoQualityLabel() case final q?) ...[
            _playerTechChip(q, accent: AppColors.cyan),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 1,
              height: 16,
              color: Colors.white24,
            ),
          ],
          Icon(Icons.wifi_rounded, size: 16, color: AppColors.cyan),
          const SizedBox(width: 6),
          Text(
            tvClockNow(context),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom-right: volume / captions / settings.
  Widget _playerEdgeControls({required bool muted}) {
    Widget btn({
      required VoidCallback onTap,
      required Widget icon,
      bool active = false,
    }) {
      return FocusTile(
        borderRadius: 16,
        onTap: onTap,
        child: TvGlass(
          radius: 16,
          tint: active ? AppColors.cyan : Colors.white,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(child: icon),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Client 2 Nov (#7): no volume button; the TV's own volume keys.
        btn(
          onTap: _pickSubtitles,
          active: _subsOn,
          icon: Icon(
            Icons.closed_caption_rounded,
            color: _subsOn ? AppColors.cyan : Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 8),
        // Client 2 Nov (#10): no info "!" button.
        btn(
          onTap: _openSettings,
          // Client 2 Nov (#9): quality icon instead of the settings gear.
          icon: const Icon(Icons.hd_rounded, size: 22),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = _seekTarget ?? _position;
    final dur = _duration;
    final live = _isLivePlayback;
    final zap = live ? ref.watch(liveZapProvider) : null;
    final canZap = zap != null && zap.channels.length > 1;
    final atEdge = _atLiveEdge;
    // Live: full bar at edge. Only show DVR fraction after an explicit scrub back.
    final progress = live
        ? (atEdge
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
        _onBack();
      },
      child: Scaffold(
        // Web (LG): video is shown on a layer behind the page; an opaque
        // background here hid the picture (see NativePlaybackView).
        backgroundColor: kIsWeb ? Colors.transparent : Colors.black,
        body: Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            // Back is handled only through PopScope (Android's system back).
            // Also mapping the Back key here made ONE press count twice — key
            // down here + system back on key up, up to ~1.3 s apart on the
            // TV — so a press opened the list AND the exit dialog, or left
            // the player AND the section (client 16 Oct #13/#16).
            SingleActivator(LogicalKeyboardKey.mediaPlayPause): _PlayIntent(),
            // Separate Play / Pause keys (some remotes) and Fire TV's Menu key.
            SingleActivator(LogicalKeyboardKey.mediaPlay): _PlayIntent(),
            SingleActivator(LogicalKeyboardKey.mediaPause): _PlayIntent(),
            SingleActivator(LogicalKeyboardKey.contextMenu): _OkIntent(),
            SingleActivator(LogicalKeyboardKey.select): _OkIntent(),
            SingleActivator(LogicalKeyboardKey.enter): _OkIntent(),
            SingleActivator(LogicalKeyboardKey.mediaRewind): _SeekBackIntent(),
            SingleActivator(LogicalKeyboardKey.mediaFastForward):
                _SeekFwdIntent(),
            // Left/Right seek whenever no control button is focused, also
            // while the controls are on screen (they used to do nothing then:
            // focus stays on the player root, so there was nothing to move to).
            SingleActivator(LogicalKeyboardKey.arrowLeft): _ArrowSeekIntent(-10),
            SingleActivator(LogicalKeyboardKey.arrowRight): _ArrowSeekIntent(10),
            // Live (client 16 Oct): Up = NEXT channel, Down = previous (the
            // same physical keys in Arabic and English). The first press only
            // shows the info bar. VOD: either key shows the controls; Down
            // again enters the button row.
            SingleActivator(LogicalKeyboardKey.arrowUp):
                _ChannelIntent(tvChannelDelta(upKey: true)),
            SingleActivator(LogicalKeyboardKey.arrowDown):
                _ChannelIntent(tvChannelDelta(upKey: false), downKey: true),
            SingleActivator(LogicalKeyboardKey.channelUp):
                _ChannelIntent(tvChannelDelta(upKey: true)),
            SingleActivator(LogicalKeyboardKey.channelDown):
                _ChannelIntent(tvChannelDelta(upKey: false), downKey: true),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _BackIntent: CallbackAction<_BackIntent>(
                onInvoke: (_) {
                  _onBack();
                  return null;
                },
              ),
              _PlayIntent: CallbackAction<_PlayIntent>(
                onInvoke: (_) {
                  _togglePlay();
                  return null;
                },
              ),
              _OkIntent: CallbackAction<_OkIntent>(
                onInvoke: (_) {
                  _onOk();
                  return null;
                },
              ),
              _SeekBackIntent: CallbackAction<_SeekBackIntent>(
                onInvoke: (_) {
                  _remoteSeek(_seekStep(-1), live: live);
                  return null;
                },
              ),
              _SeekFwdIntent: CallbackAction<_SeekFwdIntent>(
                onInvoke: (_) {
                  _remoteSeek(_seekStep(1), live: live);
                  return null;
                },
              ),
              // Disabled while a control button is focused, so the key falls
              // through to normal focus movement between the buttons.
              _ArrowSeekIntent: _GatedAction<_ArrowSeekIntent>(
                enabled: _rootHasFocus,
                onInvoke: (intent) {
                  // Live: Left/Right = volume (client 16 Oct #15).
                  if (live && !showControls) {
                    _nudgeVolume(intent.seconds > 0 ? 0.1 : -0.1);
                  } else {
                    _remoteSeek(_seekStep(intent.seconds), live: live);
                  }
                  return null;
                },
              ),
              // Off on the error screen so Up/Down reach the buttons there.
              _ChannelIntent: _GatedAction<_ChannelIntent>(
                enabled: () => !_failed || _showChannels,
                onInvoke: (intent) {
                  final hidAt = _upHidAt;
                  _upHidAt = null;
                  if (hidAt != null &&
                      DateTime.now().difference(hidAt) <
                          const Duration(milliseconds: 250)) {
                    return null;
                  }
                  if (live && canZap && !showControls) {
                    switch (tvLiveKeyAction(
                      listOpen: _showChannels,
                      barVisible: _liveBarVisible,
                      pendingZap: _pendingZap != null,
                    )) {
                      case TvLiveKeyAction.focusList:
                        _focusChannelList();
                      case TvLiveKeyAction.revealBar:
                        _showLiveBar();
                      case TvLiveKeyAction.changeChannel:
                        _zap(intent.delta);
                        _showLiveBar();
                    }
                  } else if (showControls &&
                      intent.downKey &&
                      _rootHasFocus()) {
                    _diag?.pb('CONTROLS down→buttons');
                    _playFocus.requestFocus();
                    _armControlsHide();
                  } else {
                    _showControlsNow();
                  }
                  return null;
                },
              ),
            },
            child: Focus(
              focusNode: _rootFocus,
              // With the channel list open the hidden player root is not a
              // stop: arrows at a list edge landed there and the list lost
              // the remote (client 9 Nov).
              skipTraversal: _showChannels,
              autofocus: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (native != null && _ready && !_failed)
                      RepaintBoundary(
                        child: NativePlaybackView(
                          controller: native,
                          fill: _videoFill,
                        ),
                      )
                    else if (_surfaceMounted && video != null)
                      RepaintBoundary(
                        // Wire Fit/Zoom to media_kit (toggle was UI-only before).
                        // Always expand the viewport so contain/cover are correct.
                        child: ColoredBox(
                          color: Colors.black,
                          child: SizedBox.expand(
                            child: Video(
                              controller: video,
                              controls: NoVideoControls,
                              fill: Colors.black,
                              alignment: Alignment.center,
                              // Fit = whole frame; Zoom = fill (client 20 Oct).
                              fit: _videoFill ? BoxFit.cover : BoxFit.contain,
                              wakelock: false,
                              subtitleViewConfiguration:
                                  const SubtitleViewConfiguration(
                                    style: TextStyle(
                                      height: 1.4,
                                      fontSize: 36,
                                      letterSpacing: 0.2,
                                      wordSpacing: 0.2,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      backgroundColor: Color(0x99000000),
                                    ),
                                    textAlign: TextAlign.center,
                                    padding: EdgeInsets.fromLTRB(48, 0, 48, 96),
                                  ),
                            ),
                          ),
                        ),
                      )
                    else
                      _buildPosterLoadingOrError(),
                    if (!_ready && !_failed && !_leaving)
                      IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.45),
                          child: Center(
                            child: AppPlaybackLoading(
                              logoHeight: 40,
                              label: _waitingLabel ?? _copy.loading,
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
                              logoHeight: 40,
                              label: _waitingLabel ?? _copy.loading,
                            ),
                          ),
                        ),
                      ),
                    if (_pendingStutterWarn != null && _ready && !_leaving)
                      Positioned(
                        top: 56,
                        left: 48,
                        right: 48,
                        child: Material(
                          color: const Color(0xCC1A1F2A),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _pendingStutterWarn!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 8),
                                FocusTile(
                                  borderRadius: 10,
                                  autofocus: true,
                                  onTap: () {
                                    setState(() {
                                      _forcePlayDespiteWarn = true;
                                      _pendingStutterWarn = null;
                                    });
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 10,
                                    ),
                                    child: Text(
                                      'Play anyway',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_ready && !_failed && !_leaving)
                      const Positioned(
                        left: 0,
                        bottom: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(36, 0, 0, 30),
                            // Watermark (client 17 Oct): approved logo only,
                            // bottom-left in both languages. 32 dp: slightly
                            // smaller than 40 (client 20 Oct), still clearer
                            // than the 28 dp / 38% that was easy to miss.
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: 0.6,
                                child: AppLogo(
                                  height: 32,
                                  showWordmark: false,
                                  alignToStart: false,
                                ),
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
                              Colors.black.withValues(alpha: 0.55),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.92),
                            ],
                            stops: const [0, 0.22, 0.48, 1],
                          ),
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
                            child: Column(
                              children: [
                                // Top: back · streaming title (no centered wordmark).
                                Row(
                                  children: [
                                    FocusTile(
                                      borderRadius: 14,
                                      onTap: () => unawaited(_leavePlayer()),
                                      child: TvGlass(
                                        radius: 14,
                                        child: const SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: AppBackIcon(
                                            size: 22,
                                            style:
                                                AppBackIconStyle.material,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        _title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 22,
                                          height: 1.15,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                _playerUpNextChip(),
                                // Seek row only — edge actions stay on the bottom rail.
                                // Always LTR like the transport: remote Left =
                                // back, so the bar fills left→right, and the
                                // "-mm:ss / mm:ss" text is not bidi-reordered
                                // in Arabic ("37:55-" on the emulator).
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Padding(
                                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: live ? 96 : 50,
                                        child: Text(
                                          live ? _fmtLiveElapsed() : _fmt(pos),
                                          maxLines: 1,
                                          textAlign: live
                                              ? TextAlign.start
                                              : TextAlign.center,
                                          style: TextStyle(
                                            fontSize: live ? 13 : 12,
                                            fontWeight: live
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            fontFeatures: [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: live ? 10 : 12),
                                      if (live)
                                        const Spacer()
                                      else
                                        Expanded(
                                          // Focusable (client 16 Oct #4): Up
                                          // from the buttons lands here with a
                                          // clear ring; Left/Right seek 10 s.
                                          child: _FocusableSeekBar(
                                            focusNode: _seekFocus,
                                            progress: progress,
                                            seekLabel: _seekTarget == null
                                                ? null
                                                : _seekBubbleText(pos),
                                            onSeek: (sec) => _seekBy(
                                              Duration(seconds: sec),
                                            ),
                                            onFocused: () {
                                              _diag?.pb('CONTROLS seekbar focus');
                                              _armControlsHide();
                                            },
                                            child: AppSeekBar(
                                            // LG sizes (1920 px / 2): knob 22,
                                            // bar 8, full width (client 9 Nov).
                                            thumbSize: 11,
                                            gutter: 0,
                                            touchHeight: 11,
                                            thumbShadowBlur: 3,
                                            progress: progress,
                                            enabled: _ready &&
                                                (!live ||
                                                    dur.inMilliseconds > 0),
                                            onSeekFraction: (v) async {
                                              if (!_ready) return;
                                              if (live) {
                                                if (dur.inMilliseconds <= 0) {
                                                  return;
                                                }
                                                final target = Duration(
                                                  milliseconds:
                                                      (dur.inMilliseconds * v)
                                                          .round(),
                                                );
                                                await _seekSafely(target);
                                                final behind = target <
                                                    dur - _liveEdgeTolerance;
                                                setState(
                                                  () =>
                                                      _userBehindLive = behind,
                                                );
                                                return;
                                              }
                                              if (dur.inMilliseconds == 0) {
                                                return;
                                              }
                                              _cancelAutoNext();
                                              setState(
                                                () => _playbackEnded = false,
                                              );
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
                                        ),
                                      SizedBox(width: live ? 10 : 12),
                                      if (live)
                                        FocusTile(
                                          borderRadius: 8,
                                          onTap: atEdge ? null : _goLive,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 7,
                                            ),
                                            decoration: BoxDecoration(
                                              color: atEdge
                                                  ? AppColors.live
                                                  : Colors.white24,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              atEdge ? 'LIVE' : 'GO LIVE',
                                              style: TextStyle(
                                                fontSize: 12,
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
                                          width: 50,
                                          // Total length only, as on LG.
                                          child: Text(
                                            _fmt(dur),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              fontFeatures: [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                ),
                                const SizedBox(height: 13),
                                // Bottom rail, one Row: chips (start) ·
                                // transport (centre) · edge buttons (end).
                                // Was a Stack with the transport drawn over a
                                // fixed 120 dp gap, so it covered the chips and
                                // the volume/CC buttons (client photo, Arabic).
                                // Side columns scale down instead of overlap.
                                SizedBox(
                                  height: _showVolumeSlider ? 108 : 64,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Align(
                                          alignment:
                                              AlignmentDirectional.bottomStart,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: AlignmentDirectional
                                                .bottomStart,
                                            child: _playerBottomMeta(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      // Physical left = rewind (Arabic RTL
                                      // must not reverse the transport).
                                      Directionality(
                                        textDirection: TextDirection.ltr,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (!live && _isEpisode) ...[
                                              _episodeSkip(next: false),
                                              const SizedBox(width: 14),
                                            ],
                                            if (!live) ...[
                                              _iconControl(
                                                icon: Icons.replay_30_rounded,
                                                onTap: () => _seekBy(
                                                  const Duration(seconds: -30),
                                                ),
                                                size: 52,
                                                iconSize: 28,
                                              ),
                                              const SizedBox(width: 14),
                                            ],
                                            if (live && canZap) ...[
                                              _iconControl(
                                                icon: Icons
                                                    .keyboard_arrow_up_rounded,
                                                onTap: () => _zap(1),
                                                size: 52,
                                                iconSize: 28,
                                              ),
                                              const SizedBox(width: 14),
                                            ],
                                            FocusTile(
                                              autofocus: true,
                                              focusNode: _playFocus,
                                              ringColor: Colors.white,
                                              // Blue Play/Pause: glass focus
                                              // (client 12 Nov).
                                              glassFocus: true,
                                              borderRadius: 40,
                                              onTap: _togglePlay,
                                              child: Container(
                                                width: 58,
                                                height: 58,
                                                decoration: BoxDecoration(
                                                  color: AppColors.cyan,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: AppColors.cyan
                                                          .withValues(
                                                        alpha: 0.45,
                                                      ),
                                                      blurRadius: 18,
                                                    ),
                                                  ],
                                                ),
                                                child: Icon(
                                                  _playbackEnded
                                                      ? Icons.replay_rounded
                                                      : (_playing
                                                          ? Icons.pause_rounded
                                                          : Icons
                                                              .play_arrow_rounded),
                                                  size: 32,
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ),
                                            if (!live) ...[
                                              const SizedBox(width: 14),
                                              _iconControl(
                                                icon: Icons.forward_30_rounded,
                                                onTap: () => _seekBy(
                                                  const Duration(seconds: 30),
                                                ),
                                                size: 52,
                                                iconSize: 28,
                                              ),
                                            ],
                                            if (!live && _isEpisode) ...[
                                              const SizedBox(width: 14),
                                              _episodeSkip(next: true),
                                            ],
                                            if (live && canZap) ...[
                                              const SizedBox(width: 14),
                                              _iconControl(
                                                icon: Icons
                                                    .keyboard_arrow_down_rounded,
                                                onTap: () => _zap(-1),
                                                size: 52,
                                                iconSize: 28,
                                              ),
                                              const SizedBox(width: 12),
                                              _channelListButton(),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Align(
                                          alignment:
                                              AlignmentDirectional.bottomEnd,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment:
                                                AlignmentDirectional.bottomEnd,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                  if (_showVolumeSlider)
                                                    Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                        bottom: 8,
                                                      ),
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 12,
                                                        vertical: 6,
                                                      ),
                                                      width: 240,
                                                      decoration: BoxDecoration(
                                                        color: Colors.black
                                                            .withValues(
                                                          alpha: 0.72,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(24),
                                                        border: Border.all(
                                                          color: Colors.white24,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          FocusTile(
                                                            borderRadius: 16,
                                                            onTap: _toggleMute,
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .all(4),
                                                              child: Icon(
                                                                muted
                                                                    ? Icons
                                                                        .volume_off_rounded
                                                                    : Icons
                                                                        .volume_up_rounded,
                                                                size: 18,
                                                                color: Colors
                                                                    .white70,
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            child: SliderTheme(
                                                              data: SliderTheme
                                                                      .of(
                                                                context,
                                                              )
                                                                  .copyWith(
                                                                trackHeight:
                                                                    2.5,
                                                                thumbShape:
                                                                    const RoundSliderThumbShape(
                                                                  enabledThumbRadius:
                                                                      7,
                                                                ),
                                                                overlayShape:
                                                                    const RoundSliderOverlayShape(
                                                                  overlayRadius:
                                                                      12,
                                                                ),
                                                                activeTrackColor:
                                                                    AppColors
                                                                        .cyan,
                                                                inactiveTrackColor:
                                                                    Colors
                                                                        .white24,
                                                                thumbColor:
                                                                    Colors
                                                                        .white,
                                                              ),
                                                              child: Slider(
                                                                value: _volume
                                                                    .clamp(
                                                                  0.0,
                                                                  1.0,
                                                                ),
                                                                onChanged: (v) =>
                                                                    _setVolume(
                                                                  v,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  _playerEdgeControls(
                                                    muted: muted,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Series: the season's episodes under the
                                // controls (client video 16 Oct). Down from
                                // the buttons enters it; the video keeps
                                // playing while the row is browsed.
                                if (!live &&
                                    _isEpisode &&
                                    _episodePlaylist.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  _episodeStrip(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (!showControls &&
                        !_showChannels &&
                        _seekTarget != null &&
                        !live)
                      Align(
                        alignment: const Alignment(0, 0.82),
                        child: IgnorePointer(child: _seekPill(pos, dur)),
                      ),
                    if (live &&
                        !_showChannels &&
                        !showControls &&
                        (_liveBarVisible || _pendingZap != null))
                      _liveInfoBar(zap),
                    if (_showChannels && zap != null)
                      _channelPanel(zap),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Target time and jump while the remote seeks on the bar
  /// (client 10 Nov: "no clear position"), e.g. "45:10  +1:30".
  String _seekBubbleText(Duration target) {
    final delta = target - _position;
    final sign = delta.isNegative ? '-' : '+';
    return '${_fmt(target)}  $sign${_fmt(delta.abs())}';
  }

  Widget _seekPill(Duration pos, Duration dur) {
    final forward = pos >= _position;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
            color: AppColors.cyan,
          ),
          const SizedBox(width: 10),
          Text(
            dur > Duration.zero ? '${_fmt(pos)} / ${_fmt(dur)}' : _fmt(pos),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  static const double _episodeCardW = 184;
  static const double _episodeGap = 12;

  /// Previous / next episode in the transport (series only; disabled look at
  /// the first / last episode).
  Widget _episodeSkip({required bool next}) {
    final target = _episodeIndex + (next ? 1 : -1);
    final ok = target >= 0 && target < _episodePlaylist.length;
    return Opacity(
      opacity: ok ? 1 : 0.35,
      child: _iconControl(
        icon: next ? Icons.skip_next_rounded : Icons.skip_previous_rounded,
        onTap: ok ? () => _playEpisodeAt(target) : () {},
        size: 52,
        iconSize: 28,
      ),
    );
  }

  /// The playing episode's season as a horizontal row of cards.
  Widget _episodeStrip() {
    final current = _episodePlaylist[_episodeIndex];
    final art = _seriesArt ?? _media?.backdropUrl ?? _media?.posterUrl;
    final copy = _copy;
    final entries = <int>[
      for (var i = 0; i < _episodePlaylist.length; i++)
        if (_episodePlaylist[i].season == current.season) i,
    ];
    if (!_episodesOpen) {
      // Collapsed: one focusable hint under the buttons. Down lands here
      // and opens the row.
      return Align(
        alignment: Alignment.center,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (f) {
            if (f) _openEpisodes();
          },
          child: FocusTile(
            borderRadius: 18,
            onTap: _openEpisodes,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                  const SizedBox(width: 6),
                  Text(
                    '${copy.seasonTab(current.season)}  ·  '
                    '${copy.episodesCount(entries.length)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.seasonTab(current.season),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: FocusTraversalGroup(
              child: ListView.separated(
                controller: _episodeScroll,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: _episodeGap),
                itemBuilder: (_, n) {
                  final index = entries[n];
                  final ep = _episodePlaylist[index];
                  final playing = index == _episodeIndex;
                  final still = ep.stillUrl ?? art;
                  // Provider titles are often "Series - S01E04": the code is
                  // already on the card, so only real episode names show.
                  final name = ep.title.trim();
                  final showName = name.isNotEmpty &&
                      !RegExp(r'S\d+\s*E\d+', caseSensitive: false)
                          .hasMatch(name);
                  return SizedBox(
                    width: _episodeCardW,
                    child: Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      onFocusChange: (f) {
                        if (!f) return;
                        _diag?.pb('CONTROLS episode focus idx=$index');
                        _armControlsHide();
                      },
                      child: FocusTile(
                        focusNode: playing ? _currentEpisodeFocus : null,
                        borderRadius: 10,
                        onTap: () => _playEpisodeAt(index),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: _episodeCardW,
                                height: 92,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    const ColoredBox(color: Color(0xFF1B2232)),
                                    if (still != null && still.isNotEmpty)
                                      RemoteImage(
                                        url: still,
                                        // Broken still → series art (I6).
                                        fallbackUrl: art,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 320,
                                      ),
                                    if (playing)
                                      Positioned(
                                        left: 6,
                                        top: 6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.cyan,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            copy.playerNowPlaying,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'S${ep.season} · E${ep.number}'
                              '${showName ? '  $name' : ''}'
                              '${ep.durationLabel.isEmpty ? '' : '  ·  ${ep.durationLabel}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: playing
                                    ? AppColors.cyan
                                    : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelListButton() {
    return FocusTile(
      borderRadius: 26,
      onTap: _openChannels,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.format_list_bulleted_rounded),
            const SizedBox(width: 8),
            Text(
              _copy.channelList,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelPanel(LiveZapList zap) {
    final current = zap.indexOf(widget.id);
    return Align(
      // Reading-order side, as on LG: on the right in Arabic (client 9 Nov).
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        // LG sizes: panel 1320 and packages 400 of 1920 (client 9 Nov).
        width: (_zapCats?.isNotEmpty ?? false) ? 660 : 460,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [
              const Color(0xF20A0F1A),
              const Color(0xE60A0F1A),
              Colors.black.withValues(alpha: 0),
            ],
            stops: const [0, 0.85, 1],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(28, 20, 25, 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            if (_zapCats?.isNotEmpty ?? false) ...[
              SizedBox(width: 200, child: _zapPackages(_zapCats!)),
              const SizedBox(width: 11),
            ],
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zap.title ?? _copy.channelList,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _copy.channelListHint,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: FocusTraversalGroup(
                    child: ListView.builder(
                      controller: _channelScroll,
                      itemExtent: _channelRowH,
                      itemCount: zap.channels.length,
                      itemBuilder: (_, i) {
                        final c = zap.channels[i];
                        final playing = i == current;
                        // Star beside each channel (client 21 Oct): Right
                        // from a channel focuses it, OK adds / removes the
                        // favourite without leaving the player. Same rule as
                        // the Live TV page (liked = favourite).
                        final fav = ref.watch(libraryProvider).ratingFor(c.id) == 1;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                           crossAxisAlignment: CrossAxisAlignment.stretch,
                           children: [
                           Expanded(child: FocusTile(
                            focusNode: (playing || (current < 0 && i == 0))
                                ? _channelFocus
                                : (i == 0 ? _zapFirstChannel : null),
                            borderRadius: 12,
                            onTap: () => _zapTo(c),
                            // Client 2 Nov: Down on the last channel stays.
                            onKeyFirst: (e) {
                              if (e is KeyUpEvent) return KeyEventResult.ignored;
                              if (i == zap.channels.length - 1 &&
                                  e.logicalKey == LogicalKeyboardKey.arrowDown) {
                                return KeyEventResult.handled;
                              }
                              // Back to the packages, the same in Arabic and
                              // English (client 9 Nov).
                              if (e.logicalKey == _zapKeyToPackages &&
                                  _zapCatFocus.context != null) {
                                _zapCatFocus.requestFocus();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: playing
                                    ? AppColors.cyan.withValues(alpha: 0.14)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: playing
                                      ? AppColors.cyan
                                      : Colors.white.withValues(alpha: 0.08),
                                  width: playing ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 34,
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 64,
                                      height: 40,
                                      child: ColoredBox(
                                        color: AppColors.surfaceElevated,
                                        child: RemoteImage(
                                          url: c.posterUrl ?? c.backdropUrl,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      c.displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: playing
                                            ? AppColors.cyan
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                  // Only the playing channel, as on LG: the
                                  // narrower list keeps room for the names.
                                  if (playing)
                                    const TechBadge(
                                      'NOW PLAYING',
                                      tone: BadgeTone.cyan,
                                      compact: true,
                                    ),
                                ],
                              ),
                            ),
                          )),
                           const SizedBox(width: 8),
                           FocusTile(
                             borderRadius: 12,
                             onTap: () => ref
                                 .read(libraryProvider.notifier)
                                 .setRating(c.id, 1, item: c),
                             child: Container(
                               width: _channelRowH - 12,
                               alignment: Alignment.center,
                               decoration: BoxDecoration(
                                 color: Colors.white.withValues(alpha: 0.05),
                                 borderRadius: BorderRadius.circular(12),
                                 border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                               ),
                               child: Icon(
                                 fav ? Icons.star_rounded : Icons.star_border_rounded,
                                 color: fav ? AppColors.gold : Colors.white70,
                                 size: 26,
                                 semanticLabel: fav ? _copy.favorited : _copy.favorite,
                               ),
                             ),
                           ),
                           ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            )),
              ],
            ),
          ),
        ),
      ),
    );
  }
  /// Package column of the in-player channel list (OK opens a package).
  Widget _zapPackages(List<CatalogCategory> cats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _copy.categories,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: FocusTraversalGroup(
            child: ListView.builder(
              itemExtent: 52,
              itemCount: cats.length,
              itemBuilder: (_, i) {
                final c = cats[i];
                final on = c.id == _zapCatId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: FocusTile(
                    borderRadius: 10,
                    focusNode:
                        on || (_zapCatId == null && i == 0) ? _zapCatFocus : null,
                    // Into the channels, the same in Arabic and English
                    // (client 9 Nov).
                    onKeyFirst: (e) {
                      if (e is KeyUpEvent ||
                          e.logicalKey != _zapKeyToChannels) {
                        return KeyEventResult.ignored;
                      }
                      final target = _zapChannelTarget;
                      if (target.context == null) return KeyEventResult.ignored;
                      target.requestFocus();
                      return KeyEventResult.handled;
                    },
                    onTap: () => unawaited(_openZapCategory(c)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: AlignmentDirectional.centerStart,
                      decoration: BoxDecoration(
                        color: on
                            ? AppColors.cyan.withValues(alpha: 0.14)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: on
                              ? AppColors.cyan.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        '${on ? '● ' : ''}${cleanDisplayName(c.name)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: on ? AppColors.cyan : Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  final FocusNode _errorFocus = FocusNode(debugLabel: 'tv-player-error');

  Widget _buildPosterLoadingOrError() {
    if (_failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_failed || _showChannels) return;
        if (_rootHasFocus() && _errorFocus.context != null) {
          _errorFocus.requestFocus();
        }
      });
    }
    // Loading: dark only — no poster under the spinner (client 20 Oct).
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.1,
              colors: [Color(0xFF101826), Colors.black],
            ),
          ),
        ),
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
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  // English API errors end with "." which BiDi flips to the
                  // start in Arabic UI. Localized AR/UR messages stay RTL.
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
                FocusTile(
                  // A real focus node: autofocus was ignored while the
                  // player root held focus, so OK on this screen paused the
                  // dead player instead of pressing a button (emulator).
                  focusNode: _errorFocus,
                  onTap: () => unawaited(_leavePlayer()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      _copy.playbackBack,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FocusTile(
                  onTap: () => unawaited(showTvPlaybackDiagnostics(
                    context,
                    userMessage: _error,
                    contentId: widget.id,
                  )),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      _copy.details,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_conflict) ...[
                  if (ref.watch(tvSessionProvider).playbackTakeover) ...[
                    FocusTile(
                      onTap: () {
                        setState(() {
                          _forceTakeover = true;
                          _failed = false;
                          _conflict = false;
                          _error = null;
                        });
                        unawaited(_init());
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cyan,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _copy.watchHereTakeOver,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  FocusTile(
                    onTap: () => unawaited(_leaveToManageDevices()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _copy.manageDevices,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FocusTile(
                    onTap: () => unawaited(_leavePlayer()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        _copy.keepOtherDevicePlaying,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ] else if (_decoderLimited && _hdAlternative != null)
                  FocusTile(
                    onTap: () => unawaited(
                      _leavePlayer(replaceWith: _hdAlternative!.playbackRoute()),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.cyan,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _copy.playHdVersion,
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
                      ),
                    ),
                  )
                else if (!_decoderLimited)
                  FocusTile(
                    onTap: () => unawaited(_init()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cyan,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _copy.retry,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

class _PlayIntent extends Intent {
  const _PlayIntent();
}

class _SeekBackIntent extends Intent {
  const _SeekBackIntent();
}

class _SeekFwdIntent extends Intent {
  const _SeekFwdIntent();
}

class _OkIntent extends Intent {
  const _OkIntent();
}

// Client 2 Nov (#8): seek 30 s per press, faster while the key is held or
// pressed quickly (60 s after 4 presses, 120 s after 10).
DateTime? _lastSeekKey;
int _seekRun = 0;
int _seekStep(int direction) {
  final now = DateTime.now();
  final last = _lastSeekKey;
  _seekRun = last != null && now.difference(last) < const Duration(milliseconds: 450)
      ? _seekRun + 1
      : 0;
  _lastSeekKey = now;
  final step = _seekRun >= 10 ? 120 : (_seekRun >= 4 ? 60 : 30);
  return direction < 0 ? -step : step;
}

class _ChannelIntent extends Intent {
  const _ChannelIntent(this.delta, {this.downKey = false});

  /// +1 = next channel in the list, -1 = previous.
  final int delta;
  final bool downKey;
}

class _ArrowSeekIntent extends Intent {
  const _ArrowSeekIntent(this.seconds);
  final int seconds;
}

/// A [CallbackAction] that only handles the key while [enabled] is true;
/// otherwise the key is left for normal D-pad focus movement.
class _GatedAction<T extends Intent> extends CallbackAction<T> {
  _GatedAction({required this.enabled, required super.onInvoke});

  final bool Function() enabled;

  @override
  bool isEnabled(T intent) => enabled();
}


/// Seek bar the remote can focus. Selected: a larger knob with a cyan ring
/// (only the knob; client 10 Nov: the ring around the whole bar made it look
/// all blue, with no clear position). While Left / Right seek, a bubble above
/// the knob shows the target time and the jump. Up / Down move on like the
/// other player controls.
class _FocusableSeekBar extends StatefulWidget {
  const _FocusableSeekBar({
    required this.child,
    required this.onSeek,
    required this.onFocused,
    required this.progress,
    this.seekLabel,
    this.focusNode,
  });

  final Widget child;
  final FocusNode? focusNode;
  final ValueChanged<int> onSeek;
  final VoidCallback onFocused;

  /// Same fraction the bar draws (pending seek target included).
  final double progress;

  /// Shown above the knob while a seek is pending.
  final String? seekLabel;

  @override
  State<_FocusableSeekBar> createState() => _FocusableSeekBarState();
}

class _FocusableSeekBarState extends State<_FocusableSeekBar> {
  bool _focused = false;

  // Must match the AppSeekBar sizes at the call site (knob 11, gutter 0,
  // height 11).
  static const _thumb = 11.0;
  static const _barHeight = 11.0;
  static const _ring = 19.0;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) widget.onFocused();
      },
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.arrowLeft ||
            k == LogicalKeyboardKey.arrowRight) {
          widget.onSeek(_seekStep(k == LogicalKeyboardKey.arrowRight ? 1 : -1));
          widget.onFocused();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp ||
            k == LogicalKeyboardKey.arrowDown) {
          tvMoveFocus(
            node,
            k == LogicalKeyboardKey.arrowUp
                ? TraversalDirection.up
                : TraversalDirection.down,
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          // Knob centre exactly as AppSeekBar places it.
          final track = (w - _thumb).clamp(0.0, w);
          final knobLeft = (_thumb / 2 +
                  track * widget.progress.clamp(0.0, 1.0) -
                  _thumb / 2)
              .clamp(0.0, (w - _thumb).clamp(0.0, w));
          final cx = knobLeft + _thumb / 2;
          final label = _focused ? widget.seekLabel : null;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              widget.child,
              if (_focused)
                Positioned(
                  left: cx - _ring / 2,
                  top: (_barHeight - _ring) / 2,
                  child: IgnorePointer(
                    child: Container(
                      width: _ring,
                      height: _ring,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.cyan, width: 3),
                        boxShadow: const [
                          BoxShadow(color: Color(0x80000000), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              if (label != null)
                Positioned(
                  bottom: _barHeight + 10,
                  left: (cx - 60).clamp(0.0, (w - 120).clamp(0.0, w)),
                  width: 120,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.cyan),
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
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
