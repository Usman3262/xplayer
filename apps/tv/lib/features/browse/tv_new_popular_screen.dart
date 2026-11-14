import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/tv_locale.dart';
import '../../widgets/content_rail.dart';
import '../../widgets/focus_tile.dart';

/// TV New & Popular - Netflix New & Hot parity, Figma theme.
class TvNewPopularScreen extends ConsumerWidget {
  const TvNewPopularScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    // Client 18 Oct #14: newest movies and series (provider date added) and
    // the weekly picks, numbered, as on Home.
    final coming = ref.watch(comingSoonProvider);
    final weekly = ref.watch(weeklyPicksProvider);
    final fresh = ref.watch(newReleasesProvider);
    final freshSeries = ref.watch(newSeriesProvider);

    return ListView(
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(36, 20, 36, 48),
      children: [
        Row(
          children: [
            Text(
              copy.newAndPopular,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          copy.trendingComing,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 18),
        FocusTile(
          autofocus: true,
          escapeToSidebar: true,
          escapeUpToSidebar: true,
          borderRadius: 14,
          onTap: () => context.go('/search'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF111622),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: AppColors.cyan),
                const SizedBox(width: 12),
                Text(
                  copy.searchInSection,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        fresh.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (items) => ContentRail(
            title: copy.newMovies,
            items: items,
          ),
        ),
        freshSeries.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (items) => ContentRail(
            title: copy.newSeries,
            items: items,
          ),
        ),
        weekly.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (picks) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ContentRail(
                // No ranking data: a stable weekly selection.
                title: copy.weeklyMoviePicks,
                ranked: false,
                items: picks.movies,
              ),
              ContentRail(
                title: copy.weeklySeriesPicks,
                ranked: false,
                items: picks.series,
              ),
            ],
          ),
        ),
        // Coming Soon: backend has no calendar feed — hide empty rail.
        coming.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (items) => items.isEmpty
              ? const SizedBox.shrink()
              : ContentRail(
                  title: copy.comingSoon,
                  items: items,
                ),
        ),
      ],
    );
  }
}
