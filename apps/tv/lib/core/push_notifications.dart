import 'dart:async';
import 'package:domain/domain.dart' show AppBrand;
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:data/data.dart';
import 'package:design_system/design_system.dart' show AppCopy;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update.dart';
import 'app_update_provider.dart';
import 'tv_locale.dart' show tvUiLanguage;
import 'tv_session.dart';
import 'providers.dart' show top10Provider;
import '../features/home/tv_home_screen.dart' show tvHomeScrollProvider, tvJumpToTop10;

const kChannelGeneral = 'app_general';
const kChannelUpdates = 'app_updates';
const kChannelSecurity = 'app_security';

const _kTrayIcon = 'ic_notification_app';
const _kSmallIcon = 'ic_stat_notification';

final unreadNotificationsProvider = StateProvider<int>((ref) => 0);

/// Pending TV update banner (unread APP_UPDATE for platform=tv).
final tvUpdateBannerProvider = StateProvider<AppNotificationDto?>((ref) => null);

/// Local tray notifications, tap routing and the unread badge.
class PushNotifications {
  PushNotifications._();

  static final _local = FlutterLocalNotificationsPlugin();
  static bool _started = false;
  static ProviderContainer? _container;
  static GoRouter? _router;

  static Future<void> start({
    required ProviderContainer container,
    required GoRouter router,
  }) async {
    _container = container;
    _router = router;
    if (_started) {
      unawaited(refreshUnread());
      return;
    }
    _started = true;

    await _initLocalNotifications();
    await _createAndroidChannels();
    await _requestAndroidTrayPermission();
    unawaited(refreshUnread());
  }

  static Future<void> onAppResumed() async {
    unawaited(refreshUnread());
  }

  /// Kept for callers; there is no push token to register any more.
  static Future<void> syncToken() async {}

  /// Show [message] in the tray (and refresh the unread badge).
  static Future<void> show(PushMessage message) async {
    unawaited(refreshUnread());
    await _showTrayFromMessage(_local, message);
  }

  static Future<void> refreshUnread() async {
    final container = _container;
    if (container == null) return;
    if (!container.read(tvSessionProvider).loggedIn) {
      container.read(unreadNotificationsProvider.notifier).state = 0;
      container.read(tvUpdateBannerProvider.notifier).state = null;
      return;
    }
    try {
      final media = container.read(tvMediaRepositoryProvider);
      final n = await media.notifications.unreadCount();
      container.read(unreadNotificationsProvider.notifier).state = n;

      AppNotificationDto? update;
      final page = await media.notifications.list(limit: 20);
      for (final item in page.items) {
        final type = (item.dataType ?? item.kind).toUpperCase();
        if ((type == 'APP_UPDATE' || type == 'UPDATE') &&
            item.isUnread) {
          final platform =
              '${item.data['platform'] ?? 'tv'}'.toLowerCase();
          if (platform == 'mobile' || platform == 'phone') continue;
          update = item;
          break;
        }
      }
      container.read(tvUpdateBannerProvider.notifier).state = update;
    } catch (e) {
      debugPrint('[Push] TV unread failed: $e');
    }
  }

  static Future<void> _initLocalNotifications() async {
    const android =
        AndroidInitializationSettings('@drawable/ic_notification_app');
    await _local.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final map = jsonDecode(payload);
          if (map is Map) {
            unawaited(
              _handleData(Map<String, dynamic>.from(map), fromTap: true),
            );
          }
        } catch (_) {}
      },
    );
  }

  static Future<void> _createAndroidChannels() async {
    await _ensureAndroidChannels(_local);
  }

  static Future<void> _requestAndroidTrayPermission() async {
    if (!Platform.isAndroid) return;
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    try {
      final ok = await android.requestNotificationsPermission();
      debugPrint('[Push] TV POST_NOTIFICATIONS granted=$ok');
    } catch (e) {
      debugPrint('[Push] TV requestNotificationsPermission failed: $e');
    }
  }

  static Future<void> _handleData(
    Map<String, dynamic> data, {
    required bool fromTap,
  }) async {
    final router = _router;
    final container = _container;
    if (router == null || container == null) return;

    final type = '${data['type'] ?? ''}'.toUpperCase();
    final notificationId = '${data['notificationId'] ?? ''}'.trim();
    if (notificationId.isNotEmpty) {
      try {
        final left = await container
            .read(tvMediaRepositoryProvider)
            .notifications
            .markRead(notificationId);
        container.read(unreadNotificationsProvider.notifier).state = left;
      } catch (_) {}
    }

    // Friday Top 10 (Usman 12 Nov: MESSAGE with data.type TOP10): Home with
    // the focus on the new Top 10 row.
    if (type == 'TOP10') {
      if (!fromTap) return;
      container.invalidate(top10Provider);
      router.go('/home');
      try {
        await container.read(top10Provider.future);
      } catch (_) {}
      await tvJumpToTop10(container.read(tvHomeScrollProvider));
      return;
    }

    if (type == 'APP_UPDATE') {
      final platform = '${data['platform'] ?? 'tv'}'.toLowerCase();
      if (platform == 'mobile' || platform == 'phone') {
        if (fromTap) router.push('/inbox');
        return;
      }
      final remote = '${data['version'] ?? ''}'.trim();
      final info = await PackageInfo.fromPlatform();
      if (remote.isNotEmpty && isAppVersionNewer(remote, info.version)) {
        container.read(pendingUpdateProvider.notifier).state = AppUpdateInfo(
          currentVersion: info.version,
          currentBuild: int.tryParse(info.buildNumber) ?? 0,
          minBuild: (int.tryParse(info.buildNumber) ?? 0) + 1,
          latestVersion: remote,
          message: AppCopy.ofLanguage(tvUiLanguage).updateAvailableBody(remote),
          updateUrl: AppReleaseUrls.tvApk,
          required: false,
        );
        router.go('/update');
        return;
      }
    }

    final url = '${data['url'] ?? ''}'.trim();
    if (url.startsWith('https://')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    if (fromTap) router.push('/inbox');
  }
}

Future<void> _ensureAndroidChannels(
  FlutterLocalNotificationsPlugin plugin,
) async {
  if (!Platform.isAndroid) return;
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (android == null) return;
  await android.createNotificationChannel(
    const AndroidNotificationChannel(
      kChannelGeneral,
      'Messages',
      importance: Importance.high,
      playSound: true,
      showBadge: true,
    ),
  );
  await android.createNotificationChannel(
    const AndroidNotificationChannel(
      kChannelUpdates,
      'App updates',
      importance: Importance.high,
      playSound: true,
      showBadge: true,
    ),
  );
  await android.createNotificationChannel(
    const AndroidNotificationChannel(
      kChannelSecurity,
      'Sign-in requests',
      importance: Importance.max,
      playSound: true,
      showBadge: true,
    ),
  );
}

(String title, String body)? _titleBodyFromMessage(PushMessage message) {
  final data = message.data;
  final title = (_nonEmpty(message.title) ??
          data['title'] ??
          data['notificationTitle'] ??
          '')
      .toString()
      .trim();
  final body = (_nonEmpty(message.body) ??
          data['body'] ??
          data['message'] ??
          data['text'] ??
          '')
      .toString()
      .trim();
  if (title.isEmpty && body.isEmpty) return null;
  return (
    title.isNotEmpty ? title : AppBrand.name,
    body.isNotEmpty ? body : title,
  );
}

String? _nonEmpty(String s) => s.trim().isEmpty ? null : s;

String _channelForMessage(PushMessage message) {
  final type = '${message.data['type'] ?? ''}'.toUpperCase();
  return type == 'APP_UPDATE' ? kChannelUpdates : kChannelGeneral;
}

int _notifId(PushMessage message) {
  final raw = message.id ??
      '${message.data['notificationId'] ?? ''}${message.hashCode}';
  return raw.hashCode & 0x7fffffff;
}

/// Left circle = round app badge. No right largeIcon.
Future<void> _showTrayFromMessage(
  FlutterLocalNotificationsPlugin plugin,
  PushMessage message,
) async {
  final tb = _titleBodyFromMessage(message);
  if (tb == null) {
    debugPrint('[Push] TV no title/body for tray');
    return;
  }
  final channel = _channelForMessage(message);
  final id = _notifId(message);
  final payload = jsonEncode(message.data);

  final person = Person(
    name: AppBrand.name,
    key: 'app',
    icon: DrawableResourceAndroidIcon(_kTrayIcon),
  );

  Future<void> showMessaging() {
    return plugin.show(
      id: id,
      title: tb.$1,
      body: tb.$2,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          channel,
          importance: Importance.high,
          priority: Priority.high,
          icon: _kSmallIcon,
          color: const Color(0xFF000000),
          colorized: false,
          playSound: true,
          styleInformation: MessagingStyleInformation(
            person,
            conversationTitle: tb.$1,
            groupConversation: false,
            messages: <Message>[
              Message(tb.$2, DateTime.now(), null),
            ],
          ),
        ),
      ),
      payload: payload,
    );
  }

  Future<void> showPlain({required String icon}) {
    return plugin.show(
      id: id,
      title: tb.$1,
      body: tb.$2,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          channel,
          importance: Importance.high,
          priority: Priority.high,
          icon: icon,
          color: const Color(0xFF000000),
          colorized: false,
          playSound: true,
        ),
      ),
      payload: payload,
    );
  }

  try {
    await showMessaging();
  } catch (e) {
    debugPrint('[Push] TV messaging style failed: $e');
    try {
      await showPlain(icon: _kTrayIcon);
    } catch (e2) {
      try {
        await showPlain(icon: _kSmallIcon);
      } catch (e3) {
        debugPrint('[Push] TV tray show failed: $e3');
      }
    }
  }
}
