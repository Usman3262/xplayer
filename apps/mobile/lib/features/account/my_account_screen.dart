import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/library_controller.dart';
import '../home/home_screen.dart' show ContinueRow;
import '../../core/media_nav.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

/// Netflix-style “My Netflix” hub - personal library & account shortcuts.
/// Theme: APP Figma (cyan / magenta / black).
class MyAccountScreen extends ConsumerWidget {
  const MyAccountScreen({super.key});

  void _open(BuildContext context, MediaItem item) =>
      openMediaBrowse(context, item);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final copy = AppCopy.ofLanguage(session.language);
    final profile = session.activeProfile;
    final cw = ref.watch(continueWatchingProvider);
    final myList = ref.watch(myListItemsProvider);
    final reminders = ref.watch(libraryProvider).reminders;
    final liked = ref.watch(libraryProvider).liked;
    final history = ref.watch(historyProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: RefreshIndicator(
        color: AppColors.cyan,
        onRefresh: () async {
          await ref.read(libraryProvider.notifier).syncFromRemote();
          ref.invalidate(historyProvider);
          await ref.read(historyProvider.future);
        },
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              Text(
                copy.myAccount,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(width: 8),
              TechBadge(copy.personal, tone: BadgeTone.gold, compact: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            copy.myAccountHint,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          NeonTap(
            onTap: () => context.push('/profiles'),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  ProfileAvatar(initials: profile?.initials ?? 'CK', token: profile?.avatar, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.name ?? 'Profile',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile?.isKids == true
                              ? copy.kidsExperience
                              : copy.switchProfileManage,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.swap_horiz_rounded, color: AppColors.cyan),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _QuickRow(
            items: [
              _Quick(
                icon: Icons.bookmark_rounded,
                label: copy.myList,
                onTap: () => context.push('/library?tab=watchlater'),
              ),
              _Quick(
                icon: Icons.local_fire_department_rounded,
                label: copy.neu,
                onTap: () => context.push('/new'),
              ),
              _Quick(
                icon: Icons.settings_rounded,
                label: copy.settings,
                onTap: () => context.push('/settings'),
              ),
            ],
          ),
          if (cw.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionHeader(
              title: copy.continueWatching,
              actionLabel: copy.seeAll,
              onAction: () => context.push('/library?tab=continue'),
            ),
            // Client 25 Oct: landscape cards, as on Home.
            ContinueRow(items: cw),
          ],
          if (history.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionHeader(
              title: copy.history,
              actionLabel: copy.seeAll,
              onAction: () => context.push('/library?tab=history'),
            ),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: history.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final item = history[i];
                  return NeonTap(
                    onTap: () => _open(context, item),
                    child: SizedBox(
                      width: 110,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: RemoteImage(
                              url: item.posterUrl,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (myList.isNotEmpty) ...[
            SectionHeader(
              title: copy.myList,
              actionLabel: copy.seeAll,
              onAction: () => context.push('/library?tab=watchlater'),
            ),
            SizedBox(
              height: PosterCard.railHeightFor(),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: myList.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final item = myList[i];
                  return PosterCard(
                    title: item.displayTitle,
                    rating: item.posterRating,
                    imageUrl: item.posterUrl,
                    seed: item.posterSeed ?? i,
                    onTap: () => _open(context, item),
                  );
                },
              ),
            ),
          ],
          NeonTap(
            onTap: () => context.push('/downloads'),
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.download_for_offline_outlined, color: AppColors.cyan),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          copy.downloads,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          copy.downloadsOffline,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Downloads are live (client 17 Oct #4: this card still
                  // said "Soon").
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (reminders.isNotEmpty) ...[
            SectionHeader(
              title: copy.reminders,
              actionLabel: copy.seeAll,
              onAction: () => context.push('/library?tab=reminders'),
            ),
            SizedBox(
              height: PosterCard.railHeightFor(),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: reminders.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final item = reminders[i];
                  return PosterCard(
                    title: item.displayTitle,
                    rating: item.posterRating,
                    imageUrl: item.posterUrl,
                    badges: const ['REMIND'],
                    seed: item.posterSeed ?? i,
                    onTap: () => _open(context, item),
                  );
                },
              ),
            ),
          ],
          if (liked.isNotEmpty) ...[
            SectionHeader(title: copy.titlesYouLiked),
            SizedBox(
              height: PosterCard.railHeightFor(),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: liked.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final item = liked[i];
                  return PosterCard(
                    title: item.displayTitle,
                    rating: item.posterRating,
                    imageUrl: item.posterUrl,
                    seed: item.posterSeed ?? i,
                    onTap: () => _open(context, item),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          SectionHeader(title: copy.account),
          _LinkTile(
            icon: Icons.shield_moon_outlined,
            title: copy.parentalControls,
            onTap: () => context.push('/settings/parental'),
          ),
          _LinkTile(
            icon: Icons.devices_rounded,
            title: copy.devices,
            onTap: () => context.push('/settings/devices'),
          ),
          _LinkTile(
            icon: Icons.workspace_premium_rounded,
            title: copy.subscription,
            onTap: () => context.push('/settings/subscription'),
          ),
        ],
        ),
      ),
    );
  }
}

class _QuickRow extends StatelessWidget {
  const _QuickRow({required this.items});
  final List<_Quick> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final q in items) ...[
          Expanded(
            child: NeonTap(
              onTap: q.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Icon(q.icon, color: AppColors.cyan, size: 22),
                    const SizedBox(height: 6),
                    Text(
                      q.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (q != items.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _Quick {
  const _Quick({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.cyan),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}
