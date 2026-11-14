import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/library_controller.dart';
import '../../core/media_nav.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

/// Netflix-style New & Popular - trending + coming soon + Remind Me.
class NewPopularScreen extends ConsumerWidget {
  const NewPopularScreen({super.key});

  void _open(BuildContext context, MediaItem item) =>
      openMediaBrowse(context, item);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Client 18 Oct #14: "Trending" and "Top 10" were both the first rows of
    // the catalog. Now: newest movies and series (provider date added) and
    // the weekly picks, numbered, as on Home.
    final newMovies = ref.watch(newReleasesProvider);
    final newSeries = ref.watch(newSeriesProvider);
    final coming = ref.watch(comingSoonProvider);
    final weekly = ref.watch(weeklyPicksProvider);
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );

    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              Text(
                copy.newAndPopular,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            copy.trendingComing,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          newMovies.when(
            loading: () => AppShimmer.posterRail(),
            error: (e, _) => _LoadError(
              copy: copy,
              onRetry: () => ref.invalidate(newReleasesProvider),
            ),
            data: (items) => _Rail(
              title: copy.newMovies,
              items: items,
              onOpen: (i) => _open(context, i),
            ),
          ),
          newSeries.when(
            loading: () => AppShimmer.posterRail(),
            error: (e, _) => _LoadError(
              copy: copy,
              onRetry: () => ref.invalidate(newSeriesProvider),
            ),
            data: (items) => _Rail(
              title: copy.newSeries,
              items: items,
              onOpen: (i) => _open(context, i),
            ),
          ),
          weekly.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (picks) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Rail(
                  title: copy.weeklyMoviePicks,
                  items: picks.movies,
                  numbered: false,
                  onOpen: (i) => _open(context, i),
                ),
                _Rail(
                  title: copy.weeklySeriesPicks,
                  items: picks.series,
                  numbered: false,
                  onOpen: (i) => _open(context, i),
                ),
              ],
            ),
          ),
          coming.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (items) => items.isEmpty
                ? const SizedBox.shrink()
                : _ComingRail(
                    copy: copy,
                    items: items,
                    onOpen: (i) => _open(context, i),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.title,
    required this.items,
    required this.onOpen,
    this.numbered = false,
  });

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem) onOpen;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        SizedBox(
          height: numbered ? 220 : 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final item = items[i];
              final card = PosterCard(
                title: item.displayTitle,
                rating: item.posterRating,
                imageUrl: item.posterUrl,
                badges: item.badges.take(1).toList(),
                seed: item.posterSeed ?? i,
                onTap: () => onOpen(item),
              );
              return numbered
                  ? RankedRailItem(
                      rank: i + 1,
                      color: AppColors.cyan,
                      bottom: RankedRailItem.bottomClearOfTitle,
                      child: card,
                    )
                  : card;
            },
          ),
        ),
      ],
    );
  }
}

class _ComingRail extends ConsumerWidget {
  const _ComingRail({
    required this.copy,
    required this.items,
    required this.onOpen,
  });

  final AppCopy copy;
  final List<MediaItem> items;
  final void Function(MediaItem) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const SizedBox.shrink();
    final lib = ref.watch(libraryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: copy.comingSoon),
        ...items.map((item) {
          final on = lib.hasReminder(item.id);
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(
              width: 48,
              height: 72,
              child: RemoteImage(
                url: item.posterUrl,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            title: Text(
              item.displayTitle,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              item.genres.take(2).join(' · '),
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            trailing: NeonTap(
              onTap: () =>
                  ref.read(libraryProvider.notifier)
                  .toggleReminder(item.id, item: item),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: on
                      ? AppColors.cyan.withValues(alpha: 0.2)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: on ? AppColors.cyan : AppColors.border,
                  ),
                ),
                child: Text(
                  on ? copy.reminded : copy.remindMe,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: on ? AppColors.cyan : Colors.white,
                  ),
                ),
              ),
            ),
            onTap: () => onOpen(item),
          );
        }),
      ],
    );
  }
}

/// A rail that failed to load says so (client 18 Oct #6: no silent empties).
class _LoadError extends StatelessWidget {
  const _LoadError({required this.copy, required this.onRetry});

  final AppCopy copy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              copy.loadFailed,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(copy.retry)),
        ],
      ),
    );
  }
}
