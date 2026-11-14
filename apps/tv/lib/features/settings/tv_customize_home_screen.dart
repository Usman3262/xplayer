import 'package:data/data.dart';
import 'package:domain/domain.dart' show AppBrand;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_poster.dart';
import '../../widgets/tv_ui.dart';
import 'tv_security_scaffold.dart';

/// TV port of mobile [CustomizeHomeScreen] — D-pad move up/down instead of drag.
class TvCustomizeHomeScreen extends ConsumerWidget {
  const TvCustomizeHomeScreen({super.key});

  IconData _iconFor(String id) {
    switch (id) {
      case 'continue':
        return Icons.play_circle_outline_rounded;
      case 'trending':
        return Icons.trending_up_rounded;
      case 'live':
        return Icons.live_tv_rounded;
      case 'movies':
        return Icons.movie_outlined;
      case 'series':
        return Icons.video_library_outlined;
      case 'sports':
        return Icons.sports_soccer_rounded;
      case 'kids':
        return Icons.child_care_rounded;
      case 'new':
        return Icons.fiber_new_rounded;
      default:
        return Icons.view_agenda_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(tvLanguageProvider);
    final copy = AppCopy.ofLanguage(language);
    final session = ref.watch(tvSessionProvider);
    final sections = session.homeSections;
    final profileName = session.activeProfile?.name ?? AppBrand.name;

    return TvSecurityScaffold(
      title: copy.customizeHome,
      subtitle: copy.customizeHomeHint,
      trailing: FocusTile(
        borderRadius: 12,
        onTap: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/settings');
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.cyan,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.cyan.withValues(alpha: 0.35),
                blurRadius: 16,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_rounded, color: Colors.black, size: 18),
              const SizedBox(width: 8),
              Text(
                'Apply to Home',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Section Ordering & Layout',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${sections.length} Sections',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    'D-pad Up / Down changes section position · Featured Hero stays pinned.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: sections.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final id = sections[i];
                      final pinned = i == 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              pinned
                                  ? Icons.lock_outline_rounded
                                  : Icons.drag_indicator_rounded,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Icon(
                                _iconFor(id),
                                size: 18,
                                color: AppColors.cyan,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          copy.homeSectionLabel(id),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      if (pinned) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            '#1',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    copy.priorityN(i + 1),
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '#${i + 1}',
                              style: TextStyle(
                                color: AppColors.cyan,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            FocusTile(
                              autofocus: i == 0,
                              borderRadius: 10,
                              onTap: i == 0
                                  ? null
                                  : () => ref
                                      .read(tvSessionProvider.notifier)
                                      .moveHomeSection(i, up: true),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.keyboard_arrow_up_rounded,
                                  color: i == 0
                                      ? AppColors.textSecondary
                                          .withValues(alpha: 0.35)
                                      : AppColors.cyan,
                                ),
                              ),
                            ),
                            FocusTile(
                              borderRadius: 10,
                              onTap: i >= sections.length - 1
                                  ? null
                                  : () => ref
                                      .read(tvSessionProvider.notifier)
                                      .moveHomeSection(i, up: false),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: i >= sections.length - 1
                                      ? AppColors.textSecondary
                                          .withValues(alpha: 0.35)
                                      : AppColors.cyan,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: TvGlass(
              radius: 14,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tv_rounded,
                        size: 16,
                        color: AppColors.cyan,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Home Preview',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const TvPill(
                        'LIVE',
                        tone: TvPillTone.success,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    TvPlatformProfile.pc ? 'Previewing Home Screen Layout' : 'Previewing TV Home Screen Layout',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const AppLogo(height: 22, alignToStart: true),
                              const Spacer(),
                              Text(
                                profileName,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            height: 78,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.cyan.withValues(alpha: 0.28),
                                  AppColors.magenta.withValues(alpha: 0.22),
                                ],
                              ),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const TvPill(
                                  'FEATURED HERO PINNED',
                                  tone: TvPillTone.magenta,
                                  compact: true,
                                ),
                                Flexible(
                                  child: Text(
                                    sections.isEmpty
                                        ? AppBrand.name
                                        : copy.homeSectionLabel(sections.first),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.cyan,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '▶ Watch Now',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ListView.separated(
                              itemCount: sections.length.clamp(0, 5),
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                return TvPreviewRailSkeleton(
                                  title: copy.homeSectionLabel(sections[i]),
                                  rowIndex: i + 1,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TvStatusFooter(
                    left: 'Profile: $profileName',
                    right: 'Synced',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
