import 'package:data/data.dart';
import 'package:domain/domain.dart' show AppBrand;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library_controller.dart';
import '../../core/providers.dart';
import '../../core/tv_locale.dart';
import '../../core/tv_media_nav.dart';
import '../../core/tv_session.dart';
import '../../widgets/content_rail.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_page_header.dart';
import '../../widgets/tv_poster.dart';
import '../../widgets/tv_ui.dart';

/// TV “My APP” personal hub — living-room card layout (Figma cyan theme).
class TvMyAccountScreen extends ConsumerWidget {
  const TvMyAccountScreen({super.key});

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    String? arabicTitle,
    required String seeAllLabel,
    required String tab,
    Color? accent,
  }) {
    return Row(
      children: [
        Expanded(
          child: TvSectionTitle(
            title,
            arabicTitle: arabicTitle,
            accent: accent,
          ),
        ),
        TvButton(
          label: seeAllLabel,
          icon: Icons.arrow_forward_ios_rounded,
          onTap: () => context.go('/my-list?tab=$tab'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final ar = AppCopy.ofLanguage('ar');
    final profile = ref.watch(tvSessionProvider).activeProfile;
    final cw = ref.watch(continueWatchingProvider);
    final myList = ref.watch(myListItemsProvider);
    final historyAsync = ref.watch(historyProvider);
    final history = historyAsync.valueOrNull ?? const [];
    final reminders = ref.watch(libraryProvider).reminders;
    final liked = ref.watch(libraryProvider).liked;
    final total =
        cw.length + myList.length + reminders.length + liked.length;

    return ListView(
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(36, 20, 36, 48),
      children: [
        TvPageHeader(
          title: copy.myAccount,
          arabicTitle: ar.myAccount,
          titleChip: total > 0 ? copy.titlesCount(total) : null,
          subtitle: copy.myAccountHint,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TechBadge(
                profile?.isKids == true ? copy.kids : copy.personal,
                tone: profile?.isKids == true
                    ? BadgeTone.magenta
                    : BadgeTone.gold,
                compact: true,
              ),
              const SizedBox(width: 10),
              TvButton(
                icon: Icons.switch_account_rounded,
                label: copy.switchProfileManage,
                onTap: () => context.go('/profiles'),
                escapeUpToSidebar: true,
              ),
            ],
          ),
        ),
        Wrap(
          spacing: TvUi.buttonGap,
          runSpacing: TvUi.buttonGap,
          children: [
            _HubCard(
              autofocus: true,
              escapeToSidebar: true,
              escapeUpToSidebar: true,
              label: copy.libraryHub,
              subtitle: copy.titlesCount(myList.length + cw.length),
              icon: Icons.bookmark_rounded,
              accent: AppColors.cyan,
              onTap: () => context.go('/my-list'),
            ),
            _HubCard(
              label: copy.history,
              subtitle: copy.titlesCount(history.length),
              icon: Icons.history_rounded,
              accent: AppColors.magenta,
              onTap: () => context.go('/my-list?tab=history'),
            ),
            _HubCard(
              label: copy.downloads,
              subtitle: copy.downloadsOffline,
              icon: Icons.download_rounded,
              accent: const Color(0xFFFFB020),
              onTap: () => context.push('/downloads'),
            ),
            _HubCard(
              label: copy.settings,
              subtitle: copy.account,
              icon: Icons.settings_rounded,
              accent: AppColors.cyan,
              onTap: () => context.go('/settings'),
            ),
          ],
        ),
        if (cw.isNotEmpty) ...[
          const SizedBox(height: TvUi.sectionGap),
          _sectionHeader(
            context,
            title: copy.continueWatching,
            arabicTitle: ar.continueWatching,
            seeAllLabel: copy.seeAll,
            tab: 'continue',
            accent: AppColors.cyan,
          ),
          const SizedBox(height: 12),
          // Client 25 Oct: landscape Continue Watching, as on Home.
          ContinueRail(
            title: copy.continueWatching,
            items: cw,
            showHeader: false,
          ),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: TvUi.sectionGap),
          _sectionHeader(
            context,
            title: copy.history,
            arabicTitle: ar.history,
            seeAllLabel: copy.seeAll,
            tab: 'history',
            accent: AppColors.cyan,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: TvPoster.railHeightFor(),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final item = history[i];
                return TvPoster.fromMedia(
                  item,
                  showProgress: true,
                  escapeToSidebar: i == 0,
                  onTap: () => openTvMedia(context, item),
                );
              },
            ),
          ),
        ],
        if (reminders.isNotEmpty) ...[
          const SizedBox(height: TvUi.sectionGap),
          _sectionHeader(
            context,
            title: copy.reminders,
            arabicTitle: ar.reminders,
            seeAllLabel: copy.seeAll,
            tab: 'reminders',
            accent: const Color(0xFFFFB020),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: TvPoster.railHeightFor(),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: reminders.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final item = reminders[i];
                return TvPoster.fromMedia(
                  item,
                  escapeToSidebar: i == 0,
                  onTap: () => openTvMedia(context, item),
                );
              },
            ),
          ),
        ],
        if (liked.isNotEmpty) ...[
          const SizedBox(height: TvUi.sectionGap),
          TvSectionTitle(
            copy.titlesYouLiked,
            arabicTitle: ar.titlesYouLiked,
            accent: AppColors.magenta,
            trailing: copy.titlesCount(liked.length),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: TvPoster.railHeightFor(),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: liked.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final item = liked[i];
                return TvPoster.fromMedia(
                  item,
                  escapeToSidebar: i == 0,
                  onTap: () => openTvMedia(context, item),
                );
              },
            ),
          ),
        ],
        if (myList.isNotEmpty) ...[
          const SizedBox(height: TvUi.sectionGap),
          _sectionHeader(
            context,
            title: copy.myList,
            arabicTitle: ar.myList,
            seeAllLabel: copy.seeAll,
            tab: 'watchlater',
            accent: AppColors.magenta,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: TvPoster.railHeightFor(),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: myList.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final item = myList[i];
                return TvPoster.fromMedia(
                  item,
                  escapeToSidebar: i == 0,
                  onTap: () => openTvMedia(context, item),
                );
              },
            ),
          ),
        ],
        if (cw.isEmpty &&
            myList.isEmpty &&
            reminders.isEmpty &&
            liked.isEmpty &&
            history.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: AppEmpty(
              title: copy.listEmptyTitle,
              subtitle: copy.listEmptySubtitle,
              icon: Icons.bookmark_add_outlined,
            ),
          ),
        const SizedBox(height: TvUi.sectionGap),
        Text(
          TvPlatformProfile.pc ? '${AppBrand.name} for Windows' : '${AppBrand.name} Living Room Experience',
          style: TvUi.meta.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.accent,
    this.autofocus = false,
    this.escapeToSidebar = false,
    this.escapeUpToSidebar = false,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color accent;
  final bool autofocus;
  final bool escapeToSidebar;
  final bool escapeUpToSidebar;

  @override
  Widget build(BuildContext context) {
    return FocusTile(
      autofocus: autofocus,
      escapeToSidebar: escapeToSidebar,
      escapeUpToSidebar: escapeUpToSidebar,
      borderRadius: 14,
      borderWidth: 2,
      focusScale: 1.03,
      onTap: onTap,
      child: TvGlass(
        radius: 14,
        tint: accent,
        padding: const EdgeInsets.fromLTRB(16, 14, 18, 14),
        child: SizedBox(
          width: 168,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvUi.meta.copyWith(fontSize: 11),
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
