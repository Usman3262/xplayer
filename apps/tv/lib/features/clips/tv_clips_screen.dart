import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/providers.dart';
import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_action_feedback.dart';

/// TV vertical clips feed — mid previews, mute default, no history in feed.
class TvClipsScreen extends ConsumerStatefulWidget {
  const TvClipsScreen({super.key});

  @override
  ConsumerState<TvClipsScreen> createState() => _TvClipsScreenState();
}

class _TvClipsScreenState extends ConsumerState<TvClipsScreen> {
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
      final session = ref.read(tvSessionProvider);
      if (!session.loggedIn) {
        setState(() {
          _loading = false;
          _error = 'Sign in to watch clips.';
        });
        return;
      }
      final catalog = ref.read(catalogRepositoryProvider);
      final feed = buildClipFeed(
        movies: await catalog.getMovies(),
        series: await catalog.getSeries(),
        live: await catalog.getLiveChannels(),
        limit: CatalogPaging.pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = feed;
        _loading = false;
        if (feed.isEmpty) _error = 'No catalog items for clips.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = TvActionFeedback.clean(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                copy.clips,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
              ),
              const SizedBox(width: 12),
              TechBadge(
                copy.neu,
                tone: BadgeTone.magenta,
                compact: true,
              ),
              const Spacer(),
              FocusTile(
                borderRadius: 10,
                onTap: _loading ? null : _load,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.refresh_rounded, color: AppColors.cyan),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            copy.verticalTrailers,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? Center(child: AppLoader.player(size: 64))
                : _error != null
                    ? AppEmpty(
                        title: copy.clips,
                        subtitle: _error,
                        actionLabel: copy.retry,
                        onAction: _load,
                      )
                    : PageView.builder(
                        controller: _page,
                        scrollDirection: Axis.vertical,
                        itemCount: _items.length,
                        onPageChanged: (i) => setState(() => _index = i),
                        itemBuilder: (context, i) => _TvClipPage(
                          key: ValueKey('${_items[i].catalogId}-$i'),
                          item: _items[i],
                          active: i == _index,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _TvClipPage extends ConsumerStatefulWidget {
  const _TvClipPage({
    super.key,
    required this.item,
    required this.active,
  });

  final ClipFeedItem item;
  final bool active;

  @override
  ConsumerState<_TvClipPage> createState() => _TvClipPageState();
}

class _TvClipPageState extends ConsumerState<_TvClipPage> {
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
  void didUpdateWidget(covariant _TvClipPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _start();
    } else if (!widget.active && oldWidget.active) {
      _tearDown();
    }
  }

  @override
  void dispose() {
    _tearDownSync();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _ready) return;
    _busy = true;
    setState(() => _error = null);
    try {
      final session = ref.read(tvSessionProvider);
      final auth = ref.read(tvAuthRepositoryProvider);
      final media = ref.read(tvMediaRepositoryProvider);
      final catalog = ref.read(catalogRepositoryProvider);

      final deviceId = await auth.ensurePlaybackDeviceId(
        name: TvPlatformProfile.deviceName,
        platform: TvPlatformProfile.backendPlatform,
      );
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
        final fresh = await auth.forceReregisterDevice(
          name: TvPlatformProfile.deviceName,
          platform: TvPlatformProfile.backendPlatform,
        );
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
        _startSec = 0;
        _clipStart = Duration.zero;
        _clipEnd = const Duration(seconds: 15);
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
        final copy = AppCopy.ofLanguage(ref.read(tvLanguageProvider));
        final takeover = ref.read(tvSessionProvider).playbackTakeover;
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
          _error = 'Clip took too long to open. Swipe to next or retry.';
        });
      }
      await _stopLease();
    } catch (e) {
      if (mounted) setState(() => _error = TvActionFeedback.clean(e));
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
        await ref.read(tvMediaRepositoryProvider).heartbeatPlayback(
              playbackId: id,
              deviceId: deviceId,
            );
      } catch (e, st) {
        Diag.err('tv clips heartbeat', e, st);
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
      await ref.read(tvMediaRepositoryProvider).stopPlayback(
            playbackId: id,
            deviceId: deviceId,
          );
    } catch (e, st) {
      Diag.err('tv clips stop lease', e, st);
    }
  }

  Future<void> _tearDown() async {
    _loopWatch?.cancel();
    _heartbeat?.cancel();
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
        ref.read(tvMediaRepositoryProvider).stopPlayback(
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
      context.push('/player/${item.catalogId}?kind=live');
      return;
    }
    if (item.isSeries) {
      final sid = _playStreamId ?? item.catalogId;
      context.push(
        '/player/$sid?kind=series&seriesId=${item.catalogId}&startSec=$start',
      );
      return;
    }
    context.push('/player/${item.catalogId}?startSec=$start');
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final item = widget.item;
    final buffering = _controller?.value.isBuffering == true;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.mediaPlayPause): ActivateIntent(),
      },
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggleMute();
              return null;
            },
          ),
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_ready && _controller != null)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                )
              else
                ColoredBox(
                  color: const Color(0xFF0A0C12),
                  child: Center(
                    child: _error != null
                        ? Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          )
                        : AppLoader.player(size: 56),
                  ),
                ),
              if (buffering && _ready)
                IgnorePointer(
                  child: Center(child: AppLoader.player(size: 48)),
                ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.75),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 28,
                right: 28,
                bottom: 28,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TechBadge(
                            item.isLive
                                ? copy.livePreview
                                : (item.isSeries
                                    ? copy.seriesLabel
                                    : copy.moviesLabel),
                            tone: item.isLive
                                ? BadgeTone.live
                                : BadgeTone.magenta,
                            compact: true,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 26,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.isLive
                                ? copy.livePreview
                                : copy.verticalTrailers,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    FocusTile(
                      autofocus: true,
                      borderRadius: 14,
                      onTap: _openFull,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cyan,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          item.isLive ? copy.live : copy.watch,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FocusTile(
                      borderRadius: 14,
                      onTap: _toggleMute,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
