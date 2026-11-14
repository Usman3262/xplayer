import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library_controller.dart';
import '../../core/media_nav.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

class MyListScreen extends ConsumerWidget {
  const MyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myListProvider);
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: list.when(
        loading: () => AppShimmer.twoColumnCards(),
        error: (e, _) => AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: copy.couldNotLoad,
          actionLabel: copy.retry,
          onAction: () => ref.invalidate(myListProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return AppEmpty(
              title: copy.listEmptyTitle,
              subtitle: copy.listEmptySubtitle,
              icon: Icons.bookmark_add_outlined,
              actionLabel: copy.exploreTrending,
              onAction: () => context.go('/home'),
            );
          }

          return RefreshIndicator(
            color: AppColors.cyan,
            onRefresh: () async {
              await ref.read(libraryProvider.notifier).syncFromRemote();
            },
            child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  Text(
                    copy.myList,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  TechBadge(copy.itemsSaved(items.length)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.5),
                  ),
                  color: const Color(0xFF1A160E),
                ),
                child: Text(
                  copy.savedVipHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.gold,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ...items.map((item) {
                final inList = ref.watch(libraryProvider).contains(item.id);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 86,
                        height: 120,
                        child: RemoteImage(
                          url: item.posterUrl,
                          width: 86,
                          height: 120,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            if (item.progress != null) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: item.progress,
                                  minHeight: 4,
                                  backgroundColor: Colors.white12,
                                  color: AppColors.cyan,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: PrimaryButton(
                                    label: item.progress != null
                                        ? copy.resume
                                        : copy.watchNow,
                                    onPressed: () {
                                      // Resume → player; otherwise details-first
                                      // (Task #143 #12) so broken play IDs still
                                      // land on a usable screen (P1.9).
                                      if (item.progress != null) {
                                        openMediaPlayback(context, item);
                                      } else {
                                        openMediaBrowse(context, item);
                                      }
                                    },
                                  ),
                                ),
                                IconButton(
                                  tooltip: inList ? copy.remove : copy.add,
                                  onPressed: () => ref
                                      .read(libraryProvider.notifier)
                                      .toggleMyList(item.id, item: item),
                                  icon: Icon(
                                    inList
                                        ? Icons.bookmark_remove_outlined
                                        : Icons.bookmark_add_outlined,
                                    color: AppColors.cyan,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            ),
          );
        },
      ),
    );
  }
}
