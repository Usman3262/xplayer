import 'dart:async';

import 'package:data/data.dart' show ApiException, CastPhotoDto, youtubeTrailerUri;
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/library_controller.dart';
import '../../core/remote_config.dart';
import '../../core/providers.dart';
import '../../core/tv_downloads.dart';
import '../../core/tv_locale.dart';
import '../../core/tv_media_nav.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_poster.dart';
import '../../widgets/tv_ui.dart';

/// Figma: the app TV Movie Details V2 / TV Series Details. Full-bleed
/// backdrop hero, bilingual title, cyan match %, action row, season tabs,
/// 16:9 episode cards and More Like This.
class TvDetailsScreen extends ConsumerStatefulWidget {
  const TvDetailsScreen({super.key, required this.id, this.initial});
  final String id;

  /// The tile that opened this page. Shown while the catalog lookup runs and
  /// used when the lookup misses (titles from search, My List or Kids are
  /// often not in the cached pages; before, those showed "could not be
  /// loaded").
  final MediaItem? initial;

  @override
  ConsumerState<TvDetailsScreen> createState() => _TvDetailsScreenState();
}

class _TvDetailsScreenState extends ConsumerState<TvDetailsScreen> {
  /// Selected provider season number; null = the first real season.
  int? _season;
  final FocusNode _seasonTab = FocusNode(debugLabel: 'details-season-tab');
  final FocusNode _firstEpisode = FocusNode(
    debugLabel: 'details-first-episode',
  );

  @override
  void dispose() {
    _seasonTab.dispose();
    _firstEpisode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    var itemAsync = ref.watch(mediaByIdProvider(id));
    final initial = widget.initial;
    // The tile's own item is used while loading, on error, and when the
    // catalog lookup finds nothing (cold start: the full movie list is not
    // in memory yet, so a movie id fell through to the series lookup and the
    // page said "could not be loaded").
    if (initial != null &&
        (itemAsync.isLoading ||
            itemAsync.hasError ||
            (itemAsync.hasValue && itemAsync.value == null))) {
      itemAsync = AsyncData<MediaItem?>(initial);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: itemAsync.when(
        loading: () => Padding(
          padding: const EdgeInsets.all(TvUi.pageGutter),
          child: AppShimmer.block(
            height: 300,
            radius: BorderRadius.circular(16),
          ),
        ),
        // Same page as a missing title: a message and a focused Back (the
        // raw error text showed before).
        error: (e, _) => _NotFound(copy: copy),
        data: (item) {
          if (item == null) return _NotFound(copy: copy);
          return _DetailsBody(
            id: id,
            item: item,
            season: _season,
            seasonTab: _seasonTab,
            firstEpisode: _firstEpisode,
            onSeason: (s) => setState(() => _season = s),
          );
        },
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.copy});
  final AppCopy copy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(copy.titleLoadFailed, style: TvUi.body),
          const SizedBox(height: 16),
          TvButton(
            autofocus: true,
            icon: Icons.arrow_back_rounded,
            label: copy.back,
            onTap: () => context.pop(),
          ),
        ],
      ),
    );
  }
}

class _DetailsBody extends ConsumerWidget {
  const _DetailsBody({
    required this.id,
    required this.item,
    this.season,
    required this.seasonTab,
    required this.firstEpisode,
    required this.onSeason,
  });

  final String id;
  final MediaItem item;
  final int? season;
  final FocusNode seasonTab;
  final FocusNode firstEpisode;
  final ValueChanged<int> onSeason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final isSeries = item.kind == MediaKind.series;
    // Real provider season numbers ([1, 3], [0, 1, 2] …), not 1..count.
    final seasonsAsync = isSeries
        ? ref.watch(seasonNumbersProvider(id))
        : const AsyncData<List<int>>([]);
    final seasonNums = seasonsAsync.valueOrNull ?? const <int>[];
    final seasonCount = seasonNums.isEmpty ? 1 : seasonNums.length;
    final season =
        this.season ?? (seasonNums.isNotEmpty ? seasonNums.first : 1);
    final episodesAsync = isSeries
        ? ref.watch(episodesProvider((id: id, season: season)))
        : const AsyncData<List<Episode>>([]);
    void retryEpisodes() {
      ref.invalidate(seasonNumbersProvider(id));
      ref.invalidate(episodesProvider((id: id, season: season)));
    }

    final related = ref.watch(relatedProvider(id)).valueOrNull ?? const [];
    final lib = ref.watch(libraryProvider);
    final inList = lib.contains(id);
    final liked = lib.ratingFor(id) == 1;
    final reminded = lib.hasReminder(id);
    // Movies: provider details (plot, cast, runtime) when the list row has
    // none. Series bring their plot with the episode list.
    final info = isSeries ? null : ref.watch(vodInfoProvider(id)).valueOrNull;
    final sc = isSeries ? ref.watch(seriesCastProvider(id)).valueOrNull : null;
    final castList = castRow(
      isSeries ? sc?.names : info?.cast,
      [
        for (final c in (isSeries ? sc?.photos : info?.castPhotos) ?? const <CastPhotoDto>[])
          (name: c.name, photoUrl: c.photoUrl),
      ],
    );
    final castNames = castList.names;
    // The movie's own backdrop first; TMDB before provider art with a
    // burned-in logo (client 2 Nov).
    final art = pickWideArt([info?.backdropUrl, item.backdropUrl], poster: item.posterUrl);
    final arabic = (item.titleArabic ?? '').trim();
    final year = item.year?.toString() ?? info?.year ?? info?.releaseDate;
    // Provider durationSec is often already minutes (Xtream); never ÷60 blind.
    final duration = item.durationLabel ??
        formatRuntimeLabel(runtimeMinutesFromDurationSec(info?.durationSec));
    final credits = [
      if ((info?.director ?? '').isNotEmpty)
        '${copy.directorLabel}: ${info!.director}',
    ].join('  ·  ');

    // Each part is a Unicode isolate (FSI…PDI) so Latin words and numbers
    // keep their order inside an Arabic (RTL) line: "1 Season · Drama" was
    // shown as "Season · Drama 1" on the client's TV.
    String iso(String s) => '\u2068$s\u2069';
    // Rating from the list, else from the movie's full info (client 20 Oct
    // #4: ratings missing on some titles).
    final ratingLabel = TvRatingBadge.label(
      item.rating ?? double.tryParse(info?.rating ?? ''),
    );
    final metaRest = <String>[
      if (ratingLabel != null) iso('★ $ratingLabel'),
      if (year != null) iso(year),
      if (isSeries)
        iso(copy.seasonsCount(seasonCount))
      else if (duration != null)
        iso(duration),
      if (item.genres.isNotEmpty)
        iso(copy.genres(item.genres).take(2).join(' / ')),
    ];

    MediaItem? lastEpisode;
    if (isSeries) {
      for (final e in lib.continueWatching) {
        if (e.seriesId == id && e.id != id) {
          lastEpisode = e;
          break;
        }
      }
    }
    final resume = lastEpisode == null
        ? null
        : ref
              .watch(
                seriesResumeProvider((
                  seriesId: id,
                  episodeId: lastEpisode.id,
                  progress: lastEpisode.progress ?? 0,
                  startSec: lastEpisode.resumePositionSec,
                )),
              )
              .valueOrNull;
    final progressLabel = (item.progressLabel ?? '').trim();
    final watchLabel = resume != null
        ? copy.continueEpisode(resume.episode.season, resume.episode.number)
        : progressLabel.isNotEmpty
        ? '${copy.resume} · $progressLabel'
        : copy.watchNow;

    Future<void> play() async {
      if (!isSeries) {
        context.push(item.playbackRoute());
        return;
      }
      if (resume != null) {
        final start = resume.startSec;
        context.push(
          '/player/${resume.episode.id}?seriesId=$id&kind=series'
          '${start != null && start > 5 ? '&startSec=$start' : ''}',
        );
        return;
      }
      // Never play the series id itself: the provider answers HTTP 405 (the
      // client's "Kids videos don't play"). Pressing Play before the episode
      // list arrived used to do exactly that; wait for it instead.
      List<Episode> eps;
      try {
        eps =
            episodesAsync.valueOrNull ??
            await ref.read(episodesProvider((id: id, season: season)).future);
      } catch (_) {
        eps = const [];
      }
      if (!context.mounted) return;
      if (eps.isEmpty) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(copy.noEpisodesForSeason)));
        return;
      }
      // Prefer an in-progress episode when the library has one.
      Episode? resumeEp;
      for (final e in eps) {
        if (lib.progressFor(e.id) > 0.02) {
          resumeEp = e;
          break;
        }
      }
      final target = resumeEp ?? eps.first;
      context.push('/player/${target.id}?seriesId=$id&kind=series');
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        RemoteImage(url: art, fit: BoxFit.cover),
        ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0xCC000000), Color(0xF2000000)],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: [Color(0xF2000000), Color(0x99000000), Color(0x22000000)],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
        SafeArea(
          child: ListView(
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(
              TvUi.pageGutter,
              24,
              TvUi.pageGutter,
              36,
            ),
            children: [
              // Full-bleed hero reading column (Figma v2TV1 / v2TV10).
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 720,
                  minHeight: 280,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Not autofocus: Watch Now below is the default focus
                    // (two autofocus nodes → the first, Back, won). Back stays
                    // reachable with Up and with the remote Back key.
                    FocusTile(
                      borderRadius: 12,
                      borderWidth: 2,
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/home');
                        }
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const AppBackIcon(
                          size: 20,
                          style: AppBackIconStyle.material,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        TechBadge(
                          isSeries ? 'SERIES' : 'MOVIE',
                          tone: BadgeTone.magenta,
                          compact: true,
                        ),
                        for (final b in item.badges.take(4))
                          TechBadge(b, compact: true),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        Text(
                          item.displayTitle.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TvUi.titleXL,
                        ),
                        if (arabic.isNotEmpty)
                          Text(
                            arabic,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TvUi.titleArabic,
                            textDirection: TextDirection.rtl,
                          )
                        else if ((item.subtitle ?? '').trim().isNotEmpty)
                          Text(
                            item.subtitle!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TvUi.titleArabic,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text.rich(
                      TextSpan(
                        style: TvUi.meta,
                        children: [
                          if (item.matchPercent != null) ...[
                            TextSpan(
                              text: '${item.matchPercent}% Match',
                              style: TvUi.meta.copyWith(
                                color: AppColors.cyan,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (metaRest.isNotEmpty)
                              const TextSpan(text: '  ·  '),
                          ],
                          if (metaRest.isNotEmpty)
                            TextSpan(text: metaRest.join('  ·  ')),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Builder(
                      builder: (_) {
                        final syn = (item.synopsis ?? info?.plot ?? '').trim();
                        final fallback = [
                          if ((item.subtitle ?? '').trim().isNotEmpty)
                            item.subtitle!.trim(),
                          if (item.genres.isNotEmpty)
                            copy.genres(item.genres).join(' · '),
                          if (item.year != null) '${item.year}',
                        ].where((e) => e.isNotEmpty).join(' · ');
                        final body = syn.isNotEmpty
                            ? syn
                            : (fallback.isNotEmpty ? fallback : '');
                        if (body.isEmpty && credits.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (body.isNotEmpty)
                                Text(
                                  body,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: TvUi.body,
                                ),
                              if (credits.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    credits,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TvUi.body.copyWith(
                                      color: Colors.white60,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      // Series: Down from action row jumps to episodes
                      // (first card), falling back to season tabs.
                      onKeyEvent: (_, e) {
                        if (!isSeries ||
                            e is! KeyDownEvent ||
                            e.logicalKey != LogicalKeyboardKey.arrowDown) {
                          return KeyEventResult.ignored;
                        }
                        if (firstEpisode.context != null) {
                          firstEpisode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (seasonTab.context != null) {
                          seasonTab.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Wrap(
                        spacing: TvUi.buttonGap,
                        runSpacing: TvUi.buttonGap,
                        children: [
                          // Not released yet: "Soon", no Watch Now /
                          // Download (client 4 Nov, as on LG).
                          if (item.isUpcoming)
                            SoonPill(label: copy.soon, height: 52, fontSize: 18)
                          else
                          TvButton(
                            primary: true,
                            autofocus: true,
                            icon: Icons.play_arrow_rounded,
                            label: watchLabel,
                            onTap: () => unawaited(play()),
                          ),
                          TvButton(
                            autofocus: item.isUpcoming,
                            icon: inList
                                ? Icons.check_rounded
                                : Icons.add_rounded,
                            label: inList ? copy.inMyList : copy.myList,
                            selected: inList,
                            onTap: () => ref
                                .read(libraryProvider.notifier)
                                .toggleMyList(id, item: item),
                          ),
                          // C12: YouTube only; hidden when info has no trailer.
                          if (!isSeries &&
                              youtubeTrailerUri(info?.trailer) != null &&
                              ref.watch(featureEnabledProvider('trailers')))
                            TvButton(
                              icon: Icons.movie_filter_outlined,
                              label: copy.trailer,
                              onTap: () async {
                                final uri = youtubeTrailerUri(info?.trailer);
                                if (uri == null) return;
                                final ok = await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.maybeOf(context)
                                      ?.showSnackBar(
                                    SnackBar(
                                      content: Text(copy.trailerUnavailable),
                                    ),
                                  );
                                }
                              },
                            ),
                          TvButton(
                            icon: liked
                                ? Icons.thumb_up_alt_rounded
                                : Icons.thumb_up_alt_outlined,
                            label: liked ? copy.likedLabel : copy.like,
                            selected: liked,
                            onTap: () => ref
                                .read(libraryProvider.notifier)
                                .setRating(id, 1, item: item),
                          ),
                          if (!isSeries && !item.isLive && !item.isUpcoming)
                            _DownloadButton(item: item, copy: copy),
                          TvButton(
                            icon: reminded
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_none_rounded,
                            label: reminded ? copy.reminded : copy.remindMe,
                            selected: reminded,
                            onTap: () => ref
                                .read(libraryProvider.notifier)
                                .toggleReminder(id, item: item),
                          ),
                        ],
                      ),
                    ),
                    if (item.badges.length > 4) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final b in item.badges.skip(4).take(3))
                            TechBadge(b, compact: true),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Client 2 Nov: the full cast with photos sits under the
              // details (as on LG), not behind a separate Cast button.
              if (castNames.isNotEmpty) ...[
                const SizedBox(height: TvUi.sectionGap),
                TvSectionTitle(copy.castLabel, trailing: '${castNames.length}'),
                const SizedBox(height: TvUi.rowGap),
                SizedBox(
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: castNames.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (_, i) => FocusTile(
                      borderRadius: 16,
                      padding: const EdgeInsets.all(8),
                      child: CastCard(
                        name: castNames[i],
                        photoUrl: i < (castList.photos?.length ?? 0) ? castList.photos![i] : null,
                        scale: 1.1,
                      ),
                    ),
                  ),
                ),
              ],
              if (isSeries) ...[
                const SizedBox(height: TvUi.sectionGap + 4),
                if (seasonNums.length > 1)
                  TvTextTabs(
                    labels: [for (final s in seasonNums) copy.seasonTab(s)],
                    selected: seasonNums.indexOf(season).clamp(0, 999),
                    selectedFocusNode: seasonTab,
                    onSelect: (i) {
                      onSeason(seasonNums[i]);
                      // The tab bar moves its focus node to the newly
                      // selected tab; keep focus there (emulator: it jumped
                      // up to My List after choosing Season 2).
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (seasonTab.context != null) seasonTab.requestFocus();
                      });
                    },
                  )
                else
                  TvSectionTitle(
                    copy.seasonTab(
                      seasonNums.isNotEmpty ? seasonNums.first : season,
                    ),
                  ),
                const SizedBox(height: TvUi.rowGap),
                SizedBox(
                  height: _EpisodeCard.height,
                  child: episodesAsync.when(
                    loading: () => Center(child: AppLoader.inline(size: 28)),
                    // Never the raw upstream text ("Xtream upstream HTTP
                    // 403"): say whose failure it is and offer Retry.
                    error: (e, _) => _EpisodesMessage(
                      message:
                          e is ApiException && e.code == 'XTREAM_UPSTREAM_ERROR'
                          ? copy.episodesSourceError
                          : copy.episodesLoadError,
                      retryLabel: copy.retry,
                      onRetry: retryEpisodes,
                    ),
                    data: (eps) => eps.isEmpty
                        ? _EpisodesMessage(
                            message: copy.noEpisodesForSeason,
                            retryLabel: copy.retry,
                            onRetry: retryEpisodes,
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            itemCount: eps.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 14),
                            itemBuilder: (_, i) => _EpisodeCard(
                              episode: eps[i],
                              seriesTitle: item.displayTitle,
                              seriesPoster: item.posterUrl,
                              fallbackArt: art,
                              progress: lib.progressFor(eps[i].id),
                              focusNode: i == 0 ? firstEpisode : null,
                              onTap: () => context.push(
                                '/player/${eps[i].id}?kind=series'
                                '&seriesId=${eps[i].seriesId}',
                              ),
                            ),
                          ),
                  ),
                ),
              ],
              if (related.isNotEmpty) ...[
                const SizedBox(height: TvUi.sectionGap),
                TvSectionTitle(
                  copy.moreLikeThis,
                  trailing: '${related.length}',
                ),
                const SizedBox(height: TvUi.rowGap),
                SizedBox(
                  height: TvPoster.railHeightFor(),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: related.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final r = related[i];
                      return TvPoster.fromMedia(
                        r,
                        onTap: () => openTvMedia(context, r),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.fallbackArt,
    required this.progress,
    required this.onTap,
    this.focusNode,
    this.seriesTitle,
    this.seriesPoster,
  });

  static const width = 248.0;
  static const _imageH = 140.0;
  static const _downloadH = 44.0;
  static const height = _imageH + 78 + _downloadH + 8;

  final Episode episode;
  final String? seriesTitle;
  final String? seriesPoster;
  final String? fallbackArt;
  final double progress;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final still = episode.stillUrl;
    final resuming = progress > 0.02;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          _episodeTile(context, still, resuming),
          const SizedBox(height: 8),
          // Client 18 Oct #12: download beside each episode (Down from the
          // episode reaches it).
          SizedBox(
            height: _downloadH,
            child: _EpisodeDownload(
              item: MediaItem(
                id: episode.id,
                title: [
                  // Provider episode titles often repeat the series name.
                  if ((seriesTitle ?? '').isNotEmpty &&
                      !episode.title.toLowerCase().contains(
                        seriesTitle!.toLowerCase(),
                      ))
                    seriesTitle!,
                  'S${episode.season}:E${episode.number}',
                  if (episode.title.trim().isNotEmpty) episode.title.trim(),
                ].join(' · '),
                kind: MediaKind.series,
                posterUrl: seriesPoster ?? fallbackArt,
                containerExtension: episode.containerExtension,
                seriesId: episode.seriesId,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _episodeTile(BuildContext context, String? still, bool resuming) {
    return SizedBox(
      width: width,
      height: _imageH + 78,
      child: FocusTile(
        focusNode: focusNode,
        borderRadius: 12,
        focusScale: 1.03,
        onTap: onTap,
        child: TvGlass(
          radius: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _imageH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RemoteImage(
                      url: (still != null && still.isNotEmpty)
                          ? still
                          : fallbackArt,
                      fallbackUrl: fallbackArt,
                      fit: BoxFit.cover,
                      memCacheWidth: 500,
                    ),
                    if (still == null || still.isEmpty)
                      ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
                    PositionedDirectional(
                      top: 8,
                      start: 8,
                      child: TechBadge(
                        resuming
                            ? 'RESUME S${episode.season}:E${episode.number}'
                            : 'S${episode.season}:E${episode.number}',
                        tone: resuming ? BadgeTone.live : BadgeTone.neutral,
                        compact: true,
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.cyan.withValues(alpha: 0.92),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.cyan.withValues(alpha: 0.4),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 28,
                        ),
                      ),
                    ),
                    if (progress > 0)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          color: AppColors.cyan,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${episode.number}. ${episode.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      (episode.synopsis ?? '').isNotEmpty
                          ? episode.synopsis!
                          : AppCopy.ofContext(context)
                                .durationText(episode.durationLabel),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        height: 1.3,
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

/// Per-episode download control for the remote: download arrow, progress
/// ring, then a check once the file is on this TV (OK plays it offline).
class _EpisodeDownload extends ConsumerWidget {
  const _EpisodeDownload({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofContext(context);
    TvDownload? d;
    for (final e in ref.watch(tvDownloadsProvider)) {
      if (e.id == item.id) d = e;
    }
    final status = d?.status;
    final f = d?.fraction;
    final label = switch (status) {
      null => copy.download,
      TvDownloadStatus.completed => copy.downloaded,
      TvDownloadStatus.downloading =>
        '${copy.download} ${((f ?? 0) * 100).round()}%',
      TvDownloadStatus.queued => copy.downloadQueued,
      TvDownloadStatus.paused => copy.downloadPaused,
      _ => copy.downloadFailed,
    };
    final Widget icon = switch (status) {
      TvDownloadStatus.downloading || TvDownloadStatus.queued => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          value: status == TvDownloadStatus.queued ? null : f,
          strokeWidth: 2.4,
          color: AppColors.cyan,
          backgroundColor: Colors.white24,
        ),
      ),
      TvDownloadStatus.completed => Icon(
        Icons.download_done_rounded,
        color: AppColors.cyan,
      ),
      null => Icon(Icons.download_rounded, color: AppColors.cyan),
      _ => Icon(Icons.error_outline_rounded, color: AppColors.gold),
    };
    return FocusTile(
      borderRadius: 10,
      onTap: () {
        if (d == null) {
          ref.read(tvDownloadsProvider.notifier).enqueue(item);
        } else if (status == TvDownloadStatus.completed) {
          context.push('/offline/${Uri.encodeComponent(item.id)}');
        } else {
          context.push('/downloads');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Episode-row message (error or empty season) with a focusable Retry, so the
/// row never becomes a dead end for the remote.
class _EpisodesMessage extends StatelessWidget {
  const _EpisodesMessage({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(message, style: TvUi.body),
          ),
          const SizedBox(height: 12),
          TvButton(
            icon: Icons.refresh_rounded,
            label: retryLabel,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}

/// Movie Download action (client 16 Oct #20). Shows the queue state; a
/// finished file opens the offline player.
class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({required this.item, required this.copy});

  final MediaItem item;
  final AppCopy copy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    TvDownload? d;
    for (final e in ref.watch(tvDownloadsProvider)) {
      if (e.id == item.id) d = e;
    }
    final done = d?.status == TvDownloadStatus.completed;
    final pct = d?.fraction == null ? '' : ' ${(d!.fraction! * 100).round()}%';
    final label = switch (d?.status) {
      null => copy.download,
      TvDownloadStatus.completed => copy.downloaded,
      TvDownloadStatus.downloading => '${copy.download}$pct',
      TvDownloadStatus.queued => copy.downloadQueued,
      TvDownloadStatus.paused => '${copy.downloadPaused}$pct',
      _ => copy.downloadFailed,
    };
    return TvButton(
      icon: done ? Icons.download_done_rounded : Icons.download_rounded,
      label: label,
      selected: d != null,
      onTap: () {
        if (done) {
          context.push('/offline/${Uri.encodeComponent(item.id)}');
        } else if (d == null) {
          ref.read(tvDownloadsProvider.notifier).enqueue(item);
        } else {
          context.push('/downloads');
        }
      },
    );
  }
}


