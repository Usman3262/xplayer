import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library_controller.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/download_status_button.dart';
import '../../widgets/nav_loader.dart';
import '../../widgets/rate_remind_bar.dart';
import '../demo/demo_screens.dart' show DemoCreditLine;

final _knownSeries = <String, MediaItem>{};

class SeriesDetailsScreen extends ConsumerStatefulWidget {
  const SeriesDetailsScreen({super.key, required this.id, this.initial});
  final String id;

  /// The tapped tile's item, used while loading / when the lookup misses.
  final MediaItem? initial;

  @override
  ConsumerState<SeriesDetailsScreen> createState() =>
      _SeriesDetailsScreenState();
}

class _SeriesDetailsScreenState extends ConsumerState<SeriesDetailsScreen> {
  int _season = 1;

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    var itemAsync = ref.watch(mediaByIdProvider(id));
    final first = widget.initial;
    if (first != null &&
        (itemAsync.isLoading ||
            itemAsync.hasError ||
            (itemAsync.hasValue && itemAsync.value == null))) {
      itemAsync = AsyncData<MediaItem?>(first);
    }
    final seasonsAsync = ref.watch(seasonCountProvider(id));
    final episodesAsync = ref.watch(
      episodesProvider((id: id, season: _season)),
    );
    final relatedAsync = ref.watch(relatedProvider(id));
    final lib = ref.watch(libraryProvider);
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    final inList = lib.contains(id);
    final progress = lib.progressFor(id);
    MediaItem? lastEpisode;
    for (final e in lib.continueWatching) {
      if (e.seriesId == id && e.id != id) {
        lastEpisode = e;
        break;
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

    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: itemAsync.when(
        loading: () => Center(child: AppLoader.page(label: copy.loading)),
        error: (e, _) => AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: copy.couldNotLoad,
          actionLabel: copy.retry,
          onAction: () => ref.invalidate(mediaByIdProvider(id)),
        ),
        data: (found) {
          // Last known version (the lookup can miss after a language
          // switch rebuilds the app).
          if (found != null) _knownSeries[id] = found;
          final item = found ?? _knownSeries[id];
          if (item == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This series could not be loaded. Go back and try again.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          final resolved = item;
          final seasonCount = seasonsAsync.valueOrNull ?? 2;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RemoteImage(
                        url: pickWideArt([resolved.backdropUrl], poster: resolved.posterUrl),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                      Center(
                        child: IconButton.filled(
                          onPressed: () async {
                            if (resume != null) {
                              final start = resume.startSec;
                              context.push(
                                '/player/${resume.episode.id}?kind=series'
                                '&seriesId=$id'
                                '${start != null && start > 5 ? '&startSec=$start' : ''}',
                              );
                              return;
                            }
                            final eps = await withPageLoader(context, () async {
                              return ref.read(
                                episodesProvider((id: id, season: _season))
                                    .future,
                              );
                            });
                            if (!context.mounted) return;
                            if (eps.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(copy.noEpisodesYet),
                                ),
                              );
                              return;
                            }
                            context.push(
                              '/player/${eps.first.id}?kind=series&seriesId=$id',
                            );
                          },
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.all(14),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 32),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                resolved.displayTitle.toUpperCase(),
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              if (resolved.subtitle != null)
                Text(
                  resolved.subtitle!.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.cyan,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                [
                  if (formatRating(resolved.rating) != null)
                    '★ ${formatRating(resolved.rating)}',
                  if (resolved.matchPercent != null)
                    '${resolved.matchPercent}% Match',
                  if (resolved.year != null) '${resolved.year}',
                  copy.seasonsCount(seasonCount),
                ].join('  •  '),
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(copy.genres(resolved.genres).join(' • ')),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: resolved.badges.map(TechBadge.new).toList(),
              ),
              const SizedBox(height: 16),
              // Not released yet: "Soon", no Watch Now (client 4 Nov, as on LG).
              if (resolved.isUpcoming)
                SoonPill(label: copy.soon)
              else
              PrimaryButton(
                label: resume != null
                    ? copy.continueEpisode(
                        resume.episode.season,
                        resume.episode.number,
                      )
                    : progress > 0.05
                    ? (lib.resumePositionSecFor(id) ?? 0) > 60
                        ? copy.resumeMinutes(lib.resumePositionSecFor(id)!, progress)
                        : copy.resumePercent((progress * 100).round())
                    : copy.watchNow,
                onPressed: () async {
                  if (resume != null) {
                    final start = resume.startSec;
                    context.push(
                      '/player/${resume.episode.id}?kind=series&seriesId=$id'
                      '${start != null && start > 5 ? '&startSec=$start' : ''}',
                    );
                    return;
                  }
                  final eps = await withPageLoader(context, () async {
                    return ref.read(
                      episodesProvider((id: id, season: _season)).future,
                    );
                  });
                  if (!context.mounted) return;
                  if (eps.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(copy.noEpisodesYet)),
                    );
                    return;
                  }
                  context.push(
                    '/player/${eps.first.id}?kind=series&seriesId=$id',
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Action(
                    inList ? Icons.check_rounded : Icons.add,
                    inList ? copy.inMyList : copy.myList,
                    () => ref
                        .read(libraryProvider.notifier)
                        .toggleMyList(id, item: resolved)
                        .then((_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                inList
                                    ? copy.removedFromMyList
                                    : copy.addedToMyList,
                              ),
                            ),
                          );
                        }),
                  ),
                  // No series Download here: downloads are per movie (same as
                  // TV); the button only flipped a local flag.
                ],
              ),
              const SizedBox(height: 14),
              RateRemindBar(id: id, item: resolved),
              const SizedBox(height: 18),
              Text(
                resolved.synopsis ?? '',
                style: const TextStyle(height: 1.4),
              ),
              DemoCreditLine(id: id),
              // Cast in its own section with photos, as on LG (client 4 Nov).
              if (ref.watch(seriesCastProvider(id)).valueOrNull
                      case final sc?
                  when castRow(sc.names, [for (final c in sc.photos) (name: c.name, photoUrl: c.photoUrl)]).names.isNotEmpty) ...[
                SectionHeader(title: copy.castLabel),
                Builder(builder: (_) {
                  final sc = ref.watch(seriesCastProvider(id)).valueOrNull!;
                  final row = castRow(sc.names, [for (final c in sc.photos) (name: c.name, photoUrl: c.photoUrl)]);
                  return CastStrip(names: row.names, photos: row.photos);
                }),
              ],
              SectionHeader(title: copy.episodes),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: seasonCount,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final s = i + 1;
                    return CategoryChip(
                      label: copy.seasonTab(s),
                      selected: _season == s,
                      onTap: () => setState(() => _season = s),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              episodesAsync.when(
                loading: () =>
                    AppShimmer.listRows(count: 4, showPaging: false),
                error: (e, _) => Text(copy.couldNotLoad),
                data: (episodes) => Column(
                  children: [
                    for (final ep in episodes)
                      _EpisodeTile(
                        episode: ep,
                        seriesTitle: resolved.displayTitle,
                        seriesPoster: resolved.posterUrl,
                        fallbackArt: resolved.backdropUrl ?? resolved.posterUrl,
                      ),
                  ],
                ),
              ),
              relatedAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (related) {
                  if (related.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(title: copy.moreLikeThis),
                      SizedBox(
                        height: PosterCard.railHeightFor(),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          scrollDirection: Axis.horizontal,
                          itemCount: related.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (_, i) {
                            final r = related[i];
                            return PosterCard(
                              title: r.title,
                              rating: r.posterRating,
                              badges: r.badges,
                              imageUrl: r.posterUrl,
                              seed: r.posterSeed ?? i,
                              onTap: () {
                                if (r.kind == MediaKind.movie) {
                                  context.push('/movie/${r.id}');
                                } else {
                                  context.push('/series/${r.id}');
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    this.fallbackArt,
    this.seriesTitle,
    this.seriesPoster,
  });
  final Episode episode;
  final String? seriesTitle;
  final String? seriesPoster;

  /// Series art when the provider sends no still for the episode (most
  /// do not), so the cards are not empty boxes.
  final String? fallbackArt;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(
        '/player/${episode.id}?kind=series&seriesId=${episode.seriesId}',
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              height: 64,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RemoteImage(
                    url: (episode.stillUrl ?? '').isNotEmpty
                        ? episode.stillUrl
                        : fallbackArt,
                    fallbackUrl: fallbackArt,
                    borderRadius: BorderRadius.circular(10),
                    memCacheWidth: 220,
                  ),
                  const Center(
                    child: Icon(Icons.play_arrow_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'S${episode.season} : E${episode.number}  ${episode.title}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  // Runtime only (a fixed "4K UHD" was on every episode).
                  if (episode.durationLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      AppCopy.ofContext(context)
                          .durationText(episode.durationLabel),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (episode.synopsis != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      episode.synopsis!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Client 18 Oct #12: download beside each episode.
            DownloadStatusButton(
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
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: AppColors.cyan),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
