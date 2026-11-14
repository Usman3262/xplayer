import 'package:data/data.dart' show Diag;
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/tv_locale.dart';
import '../live/tv_live_screen.dart';
import 'tv_match_centre_screen.dart';
import '../../widgets/tv_feed_loading.dart';
import '../../widgets/tv_media_card.dart';
import '../../widgets/tv_ui.dart';

/// Sports Match Center feel: today's fixtures (from home feed) above
/// categorical sports channel trails. Gated by [sportsEnabledProvider].
class TvSportsScreen extends ConsumerWidget {
  const TvSportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(sportsEnabledProvider);
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: enabled.when(
        loading: () => const Padding(
          padding: EdgeInsets.fromLTRB(48, 8, 48, 48),
          child: TvFeedLoading(
            showHero: false,
            railCount: 2,
            padding: EdgeInsets.zero,
          ),
        ),
        error: (e, _) => AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: copy.couldNotLoad,
        ),
        data: (on) {
          if (!on) {
            return Center(
              child: Text(
                copy.sportsNotInPackage,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          // Client 15 Oct: Sports = the Live TV layout (categories, channel
          // list, preview), focus, Back-twice and channel switching, filtered
          // to sports categories. Real fixtures (Match Centre / lineups) need
          // the Sports feed; the strip only shows when the feed sends them.
          const live = TvLiveScreen(sportsOnly: true);
          // Client 20 Oct: match schedules + lineups from the match centre
          // feed (/v1/sports/*); the entry shows only when the server has it.
          if (ref.watch(matchCentreOnProvider).valueOrNull == true) {
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(36, 8, 36, 4),
                  child: TvMatchCentreStrip(),
                ),
                Expanded(child: live),
              ],
            );
          }
          final feed = ref.watch(homeFeedProvider);
          final matches = feed.valueOrNull?.matches ?? const <SportsMatch>[];
          Diag.dev(
            'SPORTS_DATA tvSportsScreen homeFeed.matches=${matches.length} '
            '(0 expected without fixtures API; strip hidden when empty)',
          );
          if (matches.isEmpty) return live;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 8, 36, 8),
                child: _TodayMatchesStrip(matches: matches),
              ),
              const Expanded(child: live),
            ],
          );
        },
      ),
    );
  }
}

class _TodayMatchesStrip extends StatelessWidget {
  const _TodayMatchesStrip({required this.matches});

  final List<SportsMatch> matches;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.magenta,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              "Today's Matches",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(width: 10),
            const TvPill('LIVE', tone: TvPillTone.live, compact: true),
            const Spacer(),
            Text(
              '${matches.length} fixtures',
              style: TextStyle(
                color: AppColors.cyan,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: TvMatchCard.height + 8,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: matches.length.clamp(0, 24),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final m = matches[i];
              return TvMatchCard(
                match: m,
                autofocus: i == 0,
                escapeToSidebar: i == 0,
                onTap: () => context.push('/player/${m.id}?kind=live'),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        TvStatusFooter(
          left: '${AppBrand.name.toUpperCase()} ULTRA HD · SPORTS MATCH CENTER',
          right: 'Live Fixtures Synced',
        ),
      ],
    );
  }
}
