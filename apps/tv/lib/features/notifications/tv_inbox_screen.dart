import 'dart:async';
import 'package:domain/domain.dart' show AppBrand;

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_update.dart';
import '../../core/app_update_provider.dart';
import '../../core/providers.dart' show top10Provider;
import '../../core/push_notifications.dart';
import '../home/tv_home_screen.dart' show tvHomeScrollProvider, tvJumpToTop10;
import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_page_header.dart';
import '../../widgets/tv_ui.dart';

final tvInboxProvider = FutureProvider.autoDispose<NotificationsPage>((ref) {
  return ref.watch(tvMediaRepositoryProvider).notifications.list(limit: 40);
});

class TvInboxScreen extends ConsumerWidget {
  const TvInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final page = ref.watch(tvInboxProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(
                children: [
                  FocusTile(
                    onTap: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/home');
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TvPageHeader(title: copy.notifications),
                  ),
                ],
              ),
            ),
            Expanded(
              child: page.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        copy.couldNotLoadNotifications,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      TvButton(
                        primary: true,
                        label: copy.retry,
                        onTap: () => ref.invalidate(tvInboxProvider),
                      ),
                    ],
                  ),
                ),
                data: (data) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ref.read(unreadNotificationsProvider.notifier).state =
                        data.unreadCount;
                  });
                  if (data.items.isEmpty) {
                    return Center(
                      child: Text(
                        copy.noNotificationsYet,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 18,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(36, 8, 36, 24),
                    itemCount: data.items.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: data.unreadCount > 0
                              ? FocusTile(
                                  onTap: () async {
                                    final left = await ref
                                        .read(tvMediaRepositoryProvider)
                                        .notifications
                                        .markAllRead();
                                    ref
                                        .read(
                                          unreadNotificationsProvider.notifier,
                                        )
                                        .state = left;
                                    ref.invalidate(tvInboxProvider);
                                    unawaited(PushNotifications.refreshUnread());
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Text(
                                      copy.markAllRead,
                                      style: TextStyle(
                                        color: AppColors.cyan,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        );
                      }
                      return _TvInboxTile(item: data.items[i - 1]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvInboxTile extends ConsumerWidget {
  const _TvInboxTile({required this.item});

  final AppNotificationDto item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = item.isUnread;
    return FocusTile(
      borderRadius: 14,
      onTap: () => unawaited(_open(context, ref)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: unread ? const Color(0xFF12181F) : const Color(0xFF0A0D11),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: unread
                ? AppColors.cyan.withValues(alpha: 0.35)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              item.kind == 'UPDATE'
                  ? Icons.system_update_alt_rounded
                  : Icons.mail_outline_rounded,
              color: unread ? AppColors.cyan : AppColors.textSecondary,
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    try {
      final left = await ref
          .read(tvMediaRepositoryProvider)
          .notifications
          .markRead(item.id);
      ref.read(unreadNotificationsProvider.notifier).state = left;
      ref.invalidate(tvInboxProvider);
      unawaited(PushNotifications.refreshUnread());
    } catch (_) {}

    final type = (item.dataType ?? item.kind).toUpperCase();
    // Friday Top 10 (Usman 12 Nov): Home with the focus on the Top 10 row.
    if (type == 'TOP10') {
      ref.invalidate(top10Provider);
      final scroll = ref.read(tvHomeScrollProvider);
      if (context.mounted) context.go('/home');
      try {
        await ref.read(top10Provider.future);
      } catch (_) {}
      await tvJumpToTop10(scroll);
      return;
    }
    if (type.contains('UPDATE')) {
      final remote = '${item.data['version'] ?? ''}'.trim();
      final info = await PackageInfo.fromPlatform();
      if (remote.isNotEmpty && isAppVersionNewer(remote, info.version)) {
        ref.read(pendingUpdateProvider.notifier).state = AppUpdateInfo(
          currentVersion: info.version,
          currentBuild: int.tryParse(info.buildNumber) ?? 0,
          minBuild: (int.tryParse(info.buildNumber) ?? 0) + 1,
          latestVersion: remote,
          message: item.body.isNotEmpty
              ? item.body
              : 'A new version of ${AppBrand.name} ($remote) is available.',
          updateUrl: (item.linkUrl ?? '').trim().isNotEmpty
              ? item.linkUrl
              : AppReleaseUrls.tvApk,
          required: false,
        );
        // On top of the inbox, so Back returns here.
        if (context.mounted) context.push('/update');
        return;
      }
    }

    final url = (item.linkUrl ?? '').trim();
    if (url.startsWith('https://')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}
