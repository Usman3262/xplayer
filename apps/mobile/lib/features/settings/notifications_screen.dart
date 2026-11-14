import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/push_notifications.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final copy = AppCopy.ofLanguage(session.language);
    final enabled = session.notificationsEnabled;
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            copy.notifications,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 8),
          Text(
            copy.notificationsDeviceHint,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          if (enabled)
            FutureBuilder<bool?>(
              future: PushNotifications.osAllowsNotifications(),
              builder: (context, snap) => snap.data == false
                  ? ListTile(
                      leading: Icon(Icons.notifications_off_rounded,
                          color: AppColors.live),
                      title: Text(copy.notificationsBlocked),
                      subtitle: Text(copy.notificationsBlockedHint),
                      trailing: const Icon(Icons.open_in_new_rounded),
                      onTap: PushNotifications.openOsNotificationSettings,
                    )
                  : const SizedBox.shrink(),
            ),
          SwitchListTile(
            title: Text(copy.pushNotifications),
            subtitle: Text(copy.pushNotificationsHint),
            value: enabled,
            activeThumbColor: AppColors.cyan,
            onChanged: (v) {
              ref.read(sessionProvider.notifier).setNotifications(v);
              AppAlerts.toastAttention(
                context,
                title: copy.savedOnDevice,
                message: v
                    ? '${copy.pushNotifications}: ${copy.enabled}'
                    : '${copy.pushNotifications}: ${copy.off}',
              );
            },
          ),
          // "Email alerts (Soon)" and "VIP priority chat" were shown here with
          // nothing behind them; store review rejects placeholder features
          // (Apple 2.1), so only working settings are listed (E1, 12 Nov).
        ],
      ),
    );
  }
}
