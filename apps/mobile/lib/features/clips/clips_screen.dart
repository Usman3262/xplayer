import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/action_feedback.dart';

/// Vertical Reels-style clips: mid-content 10–15s preview.
/// Feed does **not** write history; "Watch full" / "Go Live" opens normal player.
class ClipsScreen extends ConsumerStatefulWidget {
  const ClipsScreen({super.key});

  @override
  ConsumerState<ClipsScreen> createState() => _ClipsScreenState();
}

class _ClipsScreenState extends ConsumerState<ClipsScreen> {
  final _page = PageController();
  List<ClipFeedItem> _items = const [];
  bool _loading = true;
  String? _error;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = ref.read(sessionProvider);
      if (!session.isLoggedIn) {
        setState(() {
          _loading = false;
          _error = 'Sign in to watch clips from your catalog.';
        });
        return;
      }
      final catalog = ref.read(catalogRepositoryProvider);
      final movies = await catalog.getMovies();
      final series = await catalog.getSeries();
      final live = await catalog.getLiveChannels();
      final feed = buildClipFeed(
        movies: movies,
        series: series,
        live: live,
        limit: CatalogPaging.pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = feed;
        _loading = false;
        if (feed.isEmpty) {
          _error = 'No catalog items available for clips right now.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ActionFeedback.clean(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const AppBackIcon(),
                  ),
                  const Text(
                    'Clips',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                  ),
                  const SizedBox(width: 8),
                  const TechBadge('REELS', tone: BadgeTone.magenta, compact: true),
                  const Spacer(),
                  IconButton(
                    onPressed: _loading ? null : _load,
                    icon: Icon(Icons.refresh_rounded, color: AppColors.cyan),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: AppPlaybackLoading(logoHeight: 72),
                    )
                  : _error != null
                      ? AppEmpty(
                          title: 'Clips unavailable',
                          subtitle: _error,
                          actionLabel: 'Retry',
                          onAction: _load,
                        )
                      : PageView.builder(
                          controller: _page,
                          scrollDirection: Axis.vertical,
                          itemCount: _items.length,
                          onPageChanged: (i) => setState(() => _index = i),
                          itemBuilder: (context, i) {
                            return _ClipPage(
                              key: ValueKey('${_items[i].catalogId}-$i'),
                              item: _items[i],
                              active: i == _index,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipPage extends ConsumerStatefulWidget {
  const _ClipPage({
    super.key,
    required this.item,
    required this.active,
  });

  final ClipFeedItem item;
  final bool active;

  @override
  ConsumerState<_ClipPage> createState() => _ClipPageState();
}

class _ClipPageState extends ConsumerState<_ClipPage> {
  VideoPlayerController? _controller;
  Timer? _heartbeat;
  Timer? _loopWatch;
  String? _playbackId;
  String? _deviceId;
  String? _playStreamId;
  String? _error;
  bool _ready = false;
  bool _muted = true;
  bool _busy = false;
  bool _forceTakeover = false;
  Duration _clipStart = Duration.zero;
  Duration _clipEnd = const Duration(seconds: 12);
  int _startSec = 0;

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
  };

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant _ClipPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _start();
    } else if (!widget.active && oldWidget.active) {
      // Keep decoder warm briefly for quick swipe-back (TikTok-style).
      _pauseKeepWarm();
    }
  }

  Future<void> _pauseKeepWarm() async {
    _loopWatch?.cancel();
    _loopWatch = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    try {
      await _controller?.pause();
    } catch (_) {}
    // Release lease so one-stream rule is free; keep controller for swipe-back.
    await _stopLease();
    Future<void>.delayed(const Duration(seconds: 25), () {
      if (!mounted || widget.active) return;
      _tearDownSync();
      if (mounted) setState(() => _ready = false);
    });
  }

  @override
  void dispose() {
    _tearDownSync();
    PlaybackArbiter.afterPlayback();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    // Swipe-back: reuse warm decoder (lease was released on leave).
    final warm = _controller;
    if (_ready && warm != null && warm.value.isInitialized) {
      try {
        if (!widget.item.isLive) {
          await warm.seekTo(_clipStart);
          _loopWatch?.cancel();
          _loopWatch = Timer.periodic(const Duration(milliseconds: 400), (_) {
            final ctrl = _controller;
            if (ctrl == null || !ctrl.value.isInitialized) return;
            if (ctrl.value.position >= _clipEnd) {
              ctrl.seekTo(_clipStart);
            }
          });
        }
        await warm.play();
        return;
      } catch (_) {
        await _tearDown();
      }
    }

    _busy = true;
    setState(() => _error = null);
    try {
      final session = ref.read(sessionProvider);
      final auth = ref.read(authRepositoryProvider);
      final media = ref.read(mediaRepositoryProvider);
      final catalog = ref.read(catalogRepositoryProvider);

      // Clip playback uses the provider connection too: pause a download.
      await PlaybackArbiter.beforePlayback();
      final deviceId = await auth.ensurePlaybackDeviceId();
      _deviceId = deviceId;

      var contentType = widget.item.contentType;
      var streamId = widget.item.catalogId;
      var ext = widget.item.containerExtension;

      if (widget.item.isSeries) {
        final seasons = await catalog.getSeasonCount(widget.item.catalogId);
        final season = 1 + (DateTime.now().millisecond % seasons.clamp(1, 99));
        final eps = await catalog.getEpisodes(
          widget.item.catalogId,
          season: season,
        );
        if (eps.isEmpty) {
          final fallback = await catalog.getEpisodes(widget.item.catalogId);
          if (fallback.isEmpty) {
            throw Exception('No episodes for this series');
          }
          final ep = fallback[DateTime.now().microsecond % fallback.length];
          streamId = ep.id;
          ext = ep.containerExtension ?? ext;
        } else {
          final ep = eps[DateTime.now().microsecond % eps.length];
          streamId = ep.id;
          ext = ep.containerExtension ?? ext;
        }
        contentType = 'series';
      }

      _playStreamId = streamId;
      ext = await resolvePlaybackContainer(
        catalog: catalog,
        contentType: contentType,
        streamId: streamId,
        known: ext,
        seriesId: widget.item.isSeries ? widget.item.catalogId : null,
      );

      Future<PlaybackSessionDto> start(String id) => mapPlaybackConflict(
            () => media.startPlayback(
              deviceId: id,
              contentType: contentType,
              streamId: streamId,
              profileId: session.activeProfileId,
              containerExtension: contentType == 'live' ? null : ext,
              force: _forceTakeover,
            ),
          );

      PlaybackSessionDto lease;
      try {
        lease = await start(deviceId);
      } on ApiException catch (e) {
        if (!AppAuthRepository.isDeviceGoneError(e)) rethrow;
        final fresh = await auth.forceReregisterDevice();
        _deviceId = fresh;
        lease = await start(fresh);
      }
      _playbackId = lease.playbackId;
      _startHeartbeat(lease.leaseTtlSec);

      final c = VideoPlayerController.networkUrl(
        Uri.parse(lease.playUrl),
        httpHeaders: _headers,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await c.initialize().timeout(const Duration(seconds: 75));
      if (!mounted) {
        await c.dispose();
        await _stopLease();
        return;
      }

      await c.setVolume(0);
      await c.play();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) {
        await c.dispose();
        await _stopLease();
        return;
      }

      if (widget.item.isLive) {
        _clipStart = Duration.zero;
        _clipEnd = const Duration(seconds: 15);
        _startSec = 0;
      } else {
        var window = pickClipWindowForUrl(lease.playUrl, c.value.duration);
        try {
          await c.seekTo(window.start).timeout(const Duration(seconds: 12));
        } catch (_) {
          window = (
            start: Duration.zero,
            end: Duration(seconds: window.clipSec),
            clipSec: window.clipSec,
          );
          try {
            await c.seekTo(Duration.zero).timeout(const Duration(seconds: 5));
          } catch (_) {}
        }
        _clipStart = window.start;
        _clipEnd = window.end;
        _startSec = window.start.inSeconds;
        _loopWatch?.cancel();
        _loopWatch = Timer.periodic(const Duration(milliseconds: 400), (_) {
          final ctrl = _controller;
          if (ctrl == null || !ctrl.value.isInitialized) return;
          if (ctrl.value.position >= _clipEnd) {
            ctrl.seekTo(_clipStart);
          }
        });
      }

      _controller = c;
      c.addListener(() {
        if (mounted) setState(() {});
      });
      _forceTakeover = false;
      setState(() => _ready = true);
    } on PlaybackConflictException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
        final takeover =
            ref.read(sessionProvider).user?.playbackTakeover == true;
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: Text(copy.playbackLeaseHeldTitle),
              content: Text(e.message),
              actions: [
                if (takeover)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'takeover'),
                    child: Text(copy.watchHereTakeOver),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'devices'),
                  child: Text(copy.manageDevices),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'keep'),
                  child: Text(copy.keepOtherDevicePlaying),
                ),
              ],
            );
          },
        );
        if (!mounted) return;
        if (action == 'devices') {
          context.push('/settings/devices');
        } else if (action == 'takeover') {
          _forceTakeover = true;
          _busy = false;
          if (mounted) unawaited(_start());
        }
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Clip took too long to open (large progressive file). Swipe to next or retry.';
        });
      }
      await _stopLease();
    } catch (e) {
      if (mounted) {
        setState(() => _error = ActionFeedback.clean(e));
      }
      await _stopLease();
    } finally {
      _busy = false;
    }
  }

  void _startHeartbeat(int leaseTtlSec) {
    _heartbeat?.cancel();
    final ttl = leaseTtlSec <= 0 ? 60 : leaseTtlSec;
    final every = Duration(seconds: (ttl / 3).ceil().clamp(15, 45));

    Future<void> beat() async {
      final id = _playbackId;
      final deviceId = _deviceId;
      if (id == null || deviceId == null) return;
      try {
        await ref.read(mediaRepositoryProvider).heartbeatPlayback(
              playbackId: id,
              deviceId: deviceId,
            );
      } catch (e, st) {
        Diag.err('clips heartbeat', e, st);
      }
    }

    unawaited(beat());
    _heartbeat = Timer.periodic(every, (_) => unawaited(beat()));
  }

  Future<void> _stopLease() async {
    final id = _playbackId;
    final deviceId = _deviceId;
    _playbackId = null;
    if (id == null || deviceId == null) return;
    try {
      await ref.read(mediaRepositoryProvider).stopPlayback(
            playbackId: id,
            deviceId: deviceId,
          );
    } catch (e, st) {
      Diag.err('clips stop lease', e, st);
    }
  }

  Future<void> _tearDown() async {
    _loopWatch?.cancel();
    _loopWatch = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    final c = _controller;
    _controller = null;
    _ready = false;
    await c?.pause();
    await c?.dispose();
    await _stopLease();
    if (mounted) setState(() {});
  }

  void _tearDownSync() {
    _loopWatch?.cancel();
    _heartbeat?.cancel();
    _controller?.dispose();
    _controller = null;
    final id = _playbackId;
    final deviceId = _deviceId;
    _playbackId = null;
    if (id != null && deviceId != null) {
      try {
        ref.read(mediaRepositoryProvider).stopPlayback(
              playbackId: id,
              deviceId: deviceId,
            );
      } catch (_) {}
    }
  }

  Future<void> _toggleMute() async {
    final c = _controller;
    if (c == null) return;
    setState(() => _muted = !_muted);
    await c.setVolume(_muted ? 0 : 1);
  }

  Future<void> _openFull() async {
    final item = widget.item;
    final start = _startSec;
    await _tearDown();
    if (!mounted) return;
    if (item.isLive) {
      context.push('/player/${Uri.encodeComponent(item.catalogId)}');
      return;
    }
    if (item.isSeries) {
      final sid = _playStreamId ?? item.catalogId;
      context.push(
        '/player/${Uri.encodeComponent(sid)}?kind=series&seriesId=${item.catalogId}&startSec=$start',
      );
      return;
    }
    context.push('/player/${Uri.encodeComponent(item.catalogId)}?startSec=$start');
  }

  Future<void> _openDetails() async {
    final item = widget.item;
    await _tearDown();
    if (!mounted) return;
    if (item.isLive) {
      context.push('/player/${Uri.encodeComponent(item.catalogId)}');
      return;
    }
    if (item.isSeries) {
      context.push('/series/${item.catalogId}');
      return;
    }
    context.push('/movie/${item.catalogId}');
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final buffering = _controller?.value.isBuffering == true;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_ready && _controller != null)
          GestureDetector(
            onTap: _toggleMute,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            ),
          )
        else
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _error = null;
                                _ready = false;
                              });
                              _start();
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : AppPlaybackLoading(logoHeight: 64),
            ),
          ),
        if (buffering && _ready)
          const IgnorePointer(
            child: Center(
              child: AppPlaybackLoading(logoHeight: 56),
            ),
          ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.85),
                ],
                stops: const [0, 0.25, 0.55, 1],
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TechBadge(
                item.isLive
                    ? 'LIVE CLIP'
                    : (item.isSeries ? 'SERIES CLIP' : 'MOVIE CLIP'),
                tone: item.isLive ? BadgeTone.live : BadgeTone.magenta,
                compact: true,
              ),
              const SizedBox(height: 8),
              Text(
                item.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.isLive
                    ? 'Preview · tap Go Live for the channel'
                    : 'Mid preview · not saved to history',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: item.isLive ? 'Go Live' : 'Watch full',
                      onPressed: _openFull,
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    onPressed: _toggleMute,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(
                      _muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _openDetails,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.info_outline_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
