import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_update.dart';
import '../../core/app_update_provider.dart';
import '../../core/providers.dart' show top10JumpProvider, top10Provider;
import '../../core/push_notifications.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

final inboxProvider = FutureProvider.autoDispose<NotificationsPage>((ref) {
  return ref.watch(mediaRepositoryProvider).notifications.list(limit: 40);
});

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(sessionProvider.select((s) => s.language));
    final copy = AppCopy.ofLanguage(language);
    final page = ref.watch(inboxProvider);

    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: page.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  copy.couldNotLoadNotifications,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(inboxProvider),
                  child: Text(copy.retry),
                ),
              ],
            ),
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
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Text(
                      copy.notifications,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                    const Spacer(),
                    if (data.unreadCount > 0)
                      TextButton(
                        onPressed: () async {
                          final left = await ref
                              .read(mediaRepositoryProvider)
                              .notifications
                              .markAllRead();
                          ref.read(unreadNotificationsProvider.notifier).state =
                              left;
                          ref.invalidate(inboxProvider);
                        },
                        child: Text(copy.markAllRead),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.cyan,
                  onRefresh: () async {
                    ref.invalidate(inboxProvider);
                    await ref.read(inboxProvider.future);
                    await PushNotifications.refreshUnread();
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: data.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final item = data.items[i];
                      return _InboxTile(item: item);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InboxTile extends ConsumerWidget {
  const _InboxTile({required this.item});

  final AppNotificationDto item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = item.isUnread;
    return Material(
      color: unread ? const Color(0xFF12181F) : const Color(0xFF0A0D11),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => unawaited(_open(context, ref)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                item.kind == 'UPDATE'
                    ? Icons.system_update_alt_rounded
                    : Icons.mail_outline_rounded,
                color: unread ? AppColors.cyan : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontWeight:
                            unread ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.35,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6, left: 8),
                  decoration: BoxDecoration(
                    color: AppColors.cyan,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    try {
      final left = await ref
          .read(mediaRepositoryProvider)
          .notifications
          .markRead(item.id);
      ref.read(unreadNotificationsProvider.notifier).state = left;
      ref.invalidate(inboxProvider);
    } catch (_) {}

    final type = (item.dataType ?? item.kind).toUpperCase();
    // Friday Top 10 (Usman 12 Nov): Home at the new Top 10 row.
    if (type == 'TOP10') {
      ref.invalidate(top10Provider);
      ref.read(top10JumpProvider.notifier).state++;
      if (context.mounted) context.go('/home');
      return;
    }
    if (type == 'APP_UPDATE' || type.contains('UPDATE')) {
      // A TV update notice never opens this app's update screen (client
      // 9 Nov: a phone showed "the TV app" and TV build 138).
      if ('${item.data['platform'] ?? ''}'.toLowerCase().contains('tv')) return;
      // The screen always shows this app's own latest build from the server,
      // even if a notice has no platform on it.
      try {
        final info = await checkAppUpdate();
        if (info.offerUpdate) {
          ref.read(pendingUpdateProvider.notifier).state = info;
          // On top of the inbox, so Back returns here.
          if (context.mounted) context.push('/update');
          return;
        }
      } catch (_) {}
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
