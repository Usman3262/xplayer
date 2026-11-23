import 'package:data/data.dart' show CastPhotoDto, youtubeTrailerUri;
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart' hide youtubeTrailerUri;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/demo_mode.dart';
import '../../core/remote_config.dart';
import '../../core/downloads_controller.dart';
import '../../core/library_controller.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/nav_loader.dart';
import '../../widgets/rate_remind_bar.dart';
import '../demo/demo_screens.dart' show DemoCreditLine;

final _knownMovies = <String, MediaItem>{};

class MovieDetailsScreen extends ConsumerWidget {
  const MovieDetailsScreen({super.key, required this.id, this.initial});
  final String id;

  /// The tapped tile's item: shown while loading, on error, and when the
  /// catalog lookup finds nothing (cold start), instead of an empty page.
  final MediaItem? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var itemAsync = ref.watch(mediaByIdProvider(id));
    final first = initial;
    if (first != null &&
        (itemAsync.isLoading ||
            itemAsync.hasError ||
            (itemAsync.hasValue && itemAsync.value == null))) {
      itemAsync = AsyncData<MediaItem?>(first);
    }
    final lib = ref.watch(libraryProvider);
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    final inList = lib.contains(id);
    final progress = lib.progressFor(id);
    // Provider details (plot, cast, director, runtime) — backend 16 Oct.
    final info = ref.watch(vodInfoProvider(id)).valueOrNull;
    final demo = ref.watch(demoModeProvider);
    AppDownload? dl;
    // Demo: no account, no downloads (the controller is never started).
    for (final e in demo ? const <AppDownload>[] : ref.watch(appDownloadsProvider)) {
      if (e.id == id) dl = e;
    }
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: itemAsync.when(
        loading: () =>
            Center(child: AppLoader.page(label: copy.loading)),
        error: (e, _) => AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: copy.couldNotLoad,
          actionLabel: copy.retry,
          onAction: () => ref.invalidate(mediaByIdProvider(id)),
        ),
        data: (item) {
          // Last known version of this title: after a language switch the
          // app rebuilds and the catalog lookup can miss; the page then
          // showed the content id ("615777") instead of the title.
          if (item != null && item.title.trim().isNotEmpty) {
            _knownMovies[id] = item;
          }
          final resolved = item ??
              _knownMovies[id] ??
              MediaItem(
                id: id,
                title: '',
                kind: MediaKind.movie,
              );
          final year =
              resolved.year?.toString() ?? info?.year ?? info?.releaseDate;
          // Provider durationSec is often already minutes (Xtream); never ÷60 blind.
          final mins = runtimeMinutes(resolved.durationLabel) ??
              runtimeMinutesFromDurationSec(info?.durationSec);
          final duration = mins == null || mins <= 0
              ? null
              : copy.runtime(mins);
          final rating =
              formatRating(resolved.rating) ?? formatRating(info?.rating);
          final genres =
              resolved.genres.isNotEmpty ? resolved.genres : info?.genres ?? const [];
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
                        // TMDB first: provider art can carry a big logo.
                        url: pickWideArt(
                          [info?.backdropUrl, resolved.backdropUrl],
                          poster: resolved.posterUrl,
                        ),
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
                            await withPageLoader(context, () async {
                              await Future<void>.delayed(
                                const Duration(milliseconds: 60),
                              );
                            });
                            if (!context.mounted) return;
                            context.push(
                              '/player/${Uri.encodeComponent(resolved.id)}?kind=movie',
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
                resolved.title.trim().isEmpty
                    ? ''
                    : resolved.displayTitle.toUpperCase(),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              if (resolved.subtitle != null)
                Text(
                  resolved.subtitle!,
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                // Only what the catalog / provider reports (the fixed "18+"
                // was not real data).
                [
                  if (rating != null && rating.isNotEmpty) '★ $rating',
                  if (resolved.matchPercent != null)
                    '${resolved.matchPercent}% Match',
                  ?year,
                  ?duration,
                ].join('  •  '),
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              if (genres.isNotEmpty) Text(copy.genres(genres).join(' • ')),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final b in resolved.badges)
                    TechBadge(
                      b,
                      tone: b.contains('ATMOS')
                          ? BadgeTone.magenta
                          : BadgeTone.cyan,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Not released yet: "Soon", no Watch Now (client 4 Nov, as on LG).
              if (resolved.isUpcoming)
                SoonPill(label: copy.soon)
              else
              PrimaryButton(
                label: progress > 0.05
                    ? (lib.resumePositionSecFor(id) ?? 0) > 60
                        ? copy.resumeMinutes(lib.resumePositionSecFor(id)!, progress)
                        : copy.resumePercent((progress * 100).round())
                    : copy.watchNow,
                onPressed: () async {
                  await withPageLoader(context, () async {
                    await Future<void>.delayed(
                      const Duration(milliseconds: 60),
                    );
                  });
                  if (!context.mounted) return;
                  context.push('/player/${Uri.encodeComponent(resolved.id)}?kind=movie');
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Action(
                    inList ? Icons.check_rounded : Icons.add,
                    inList ? copy.inMyList : copy.myList,
                    () async {
                      final wasIn = inList;
                      await ref
                          .read(libraryProvider.notifier)
                          .toggleMyList(id, item: resolved);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            wasIn
                                ? copy.removedFromMyList
                                : copy.addedToMyList,
                          ),
                        ),
                      );
                    },
                  ),
                  // Real YouTube trailer, else no button (client 20 Oct #3:
                  // Trailer played the movie itself).
                  if (youtubeTrailerUri(info?.trailer) case final trailer?
                      when ref.watch(featureEnabledProvider('trailers')))
                    _Action(
                      Icons.play_circle_outline,
                      copy.trailer,
                      () async {
                        var ok = false;
                        try {
                          ok = await launchUrl(
                            trailer,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {}
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(copy.trailerUnavailable)),
                          );
                        }
                      },
                    ),
                  // Real download (backend grant, app storage); a finished
                  // file opens the offline player. It used to only flip a
                  // local "downloaded" flag.
                  if (!resolved.isUpcoming)
                  _Action(
                    // Client 18 Oct #12: phone with a check = on this phone.
                    dl?.status == DownloadStatus.completed
                        ? Icons.mobile_friendly_rounded
                        : Icons.download_rounded,
                    switch (dl?.status) {
                      null => copy.download,
                      DownloadStatus.completed => copy.downloaded,
                      DownloadStatus.downloading =>
                        '${copy.download} ${((dl!.fraction ?? 0) * 100).round()}%',
                      DownloadStatus.queued => copy.downloadQueued,
                      DownloadStatus.paused => copy.downloadPaused,
                      _ => copy.downloadFailed,
                    },
                    () {
                      final d = dl;
                      if (demo) {
                        context.push(demoSignInRoute);
                      } else if (d == null) {
                        ref
                            .read(appDownloadsProvider.notifier)
                            .enqueue(resolved);
                      } else if (d.status == DownloadStatus.completed) {
                        context.push('/offline/${Uri.encodeComponent(id)}');
                      } else {
                        context.push('/downloads');
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              RateRemindBar(id: id, item: resolved),
              const SizedBox(height: 20),
              Builder(
                builder: (_) {
                  final syn = (resolved.synopsis ?? info?.plot ?? '').trim();
                  final fallback = [
                    if ((resolved.subtitle ?? '').trim().isNotEmpty)
                      resolved.subtitle!.trim(),
                    if (resolved.genres.isNotEmpty)
                      copy.genres(resolved.genres).join(' • '),
                    if (resolved.year != null) '${resolved.year}',
                  ].where((e) => e.isNotEmpty).join('\n');
                  final body = syn.isNotEmpty ? syn : fallback;
                  if (body.isEmpty) return const SizedBox.shrink();
                  return Text(body, style: const TextStyle(height: 1.4));
                },
              ),
              DemoCreditLine(id: id),
              const SizedBox(height: 16),
              // Credits from the provider only. The box used to show the same
              // invented director, audio, subtitle and "4K HDR10+ Studio
              // Master" lines on every movie.
              if ((info?.director ?? '').isNotEmpty ||
                  resolved.badges.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((info?.director ?? '').isNotEmpty)
                        _Meta(copy.director, info!.director!),
                      if (resolved.badges.isNotEmpty)
                        _Meta(
                          copy.masterSpec,
                          resolved.badges.map(badgeText).join(' • '),
                          highlight: true,
                        ),
                    ],
                  ),
                ),
              // Cast in its own section with photos, as on LG (client 4 Nov).
              if (castRow(info?.cast, [for (final c in info?.castPhotos ?? const <CastPhotoDto>[]) (name: c.name, photoUrl: c.photoUrl)])
                  case final row when row.names.isNotEmpty) ...[
                SectionHeader(title: copy.castLabel),
                CastStrip(names: row.names, photos: row.photos),
              ],
              ref.watch(relatedProvider(id)).when(
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

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            icon,
            color: onTap == null
                ? AppColors.textSecondary
                : AppColors.cyan,
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value, {this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: highlight ? AppColors.cyan : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
