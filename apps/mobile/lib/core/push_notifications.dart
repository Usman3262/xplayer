import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:data/data.dart';
import 'package:domain/domain.dart' show AppBrand;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update.dart';
import 'app_update_provider.dart';
import 'providers.dart' show top10JumpProvider, top10Provider;
import 'session_controller.dart';

/// Android notification channel ids.
const kChannelGeneral = 'app_general';
const kChannelUpdates = 'app_updates';
const kChannelSecurity = 'app_security';

/// Round app badge used in the notification shade.
const _kTrayIcon = 'ic_notification_app';
/// White status-bar silhouette (fallback small icon).
const _kSmallIcon = 'ic_stat_notification';

final unreadNotificationsProvider = StateProvider<int>((ref) => 0);

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
    if (kIsWeb) return;
    _container = container;
    _router = router;
    if (_started) {
      unawaited(refreshUnread());
      return;
    }
    _started = true;

    await _initLocalNotifications();
    await _createAndroidChannels();
    await _requestTrayPermission();
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
    await _showTray(_local, message);
  }

  static Future<void> refreshUnread() async {
    final container = _container;
    if (container == null) return;
    if (!container.read(sessionProvider).isLoggedIn) {
      container.read(unreadNotificationsProvider.notifier).state = 0;
      return;
    }
    try {
      final n = await container
          .read(mediaRepositoryProvider)
          .notifications
          .unreadCount();
      container.read(unreadNotificationsProvider.notifier).state = n;
    } catch (e) {
      debugPrint('[Push] unreadCount failed: $e');
    }
  }

  static Future<void> _initLocalNotifications() async {
    const android =
        AndroidInitializationSettings('@drawable/ic_notification_app');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final map = jsonDecode(payload);
          if (map is Map) {
            unawaited(
              _handleData(
                Map<String, dynamic>.from(map),
                fromTap: true,
              ),
            );
          }
        } catch (_) {}
      },
    );
  }

  static Future<void> _createAndroidChannels() async {
    await _ensureAndroidChannels(_local);
  }

  static Future<void>? _androidAsk;

  /// One permission prompt at a time, made once the app is on screen.
  static Future<void> _requestTrayPermission() =>
      _androidAsk ??= _askOnce();

  static Future<void> _askOnce() async {
    if (kIsWeb) return;
    if (Platform.isIOS) {
      try {
        await _local
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      } catch (e) {
        debugPrint('[Push] iOS requestPermissions failed: $e');
      }
      return;
    }
    if (!Platform.isAndroid) return;
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    try {
      if (await android.areNotificationsEnabled() == true) return;
      await Future<void>.delayed(const Duration(seconds: 2));
      for (var i = 0;
          i < 30 &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final ok = await android.requestNotificationsPermission();
      debugPrint('[Push] Android POST_NOTIFICATIONS granted=$ok');
    } catch (e) {
      debugPrint('[Push] requestNotificationsPermission failed: $e');
    }
  }

  /// False when this phone blocks the app's notifications (null = unknown).
  static Future<bool?> osAllowsNotifications() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return android?.areNotificationsEnabled();
    }
    try {
      final ios = _local.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final p = await ios?.checkPermissions();
      return p?.isEnabled;
    } catch (_) {
      return null;
    }
  }

  /// Open the phone's notification settings for this app.
  static Future<void> openOsNotificationSettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      await const MethodChannel('app/device')
          .invokeMethod<bool>('openNotificationSettings');
      return;
    }
    await launchUrl(Uri.parse('app-settings:'));
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
            .read(mediaRepositoryProvider)
            .notifications
            .markRead(notificationId);
        container.read(unreadNotificationsProvider.notifier).state = left;
      } catch (_) {}
    }

    switch (type) {
      case 'LOGIN_CHALLENGE':
        router.go('/home');
        return;
      // Friday Top 10 (Usman 12 Nov: MESSAGE with data.type TOP10): open
      // Home at the new Top 10 row.
      case 'TOP10':
        container.invalidate(top10Provider);
        container.read(top10JumpProvider.notifier).state++;
        router.go('/home');
        return;
      case 'APP_UPDATE':
        final platform = '${data['platform'] ?? 'mobile'}'.toLowerCase();
        if (platform.contains('tv')) {
          if (!fromTap) return;
          router.push('/inbox');
          return;
        }
        // This app's own latest build from the server, as the inbox does:
        // the iPhone gets its own store link, never the Android APK.
        AppUpdateInfo? update;
        try {
          final info = await checkAppUpdate();
          if (info.offerUpdate || info.required) update = info;
        } catch (_) {}
        if (update != null) {
          container.read(pendingUpdateProvider.notifier).state = update;
          router.go('/update');
        } else if (fromTap) {
          router.push('/inbox');
        }
        return;
      case 'MESSAGE':
      default:
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
}

Future<void> _ensureAndroidChannels(
  FlutterLocalNotificationsPlugin plugin,
) async {
  if (kIsWeb || !Platform.isAndroid) return;
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (android == null) return;
  await android.createNotificationChannel(
    const AndroidNotificationChannel(
      kChannelGeneral,
      'Messages',
      description: 'Control Panel messages',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    ),
  );
  await android.createNotificationChannel(
    const AndroidNotificationChannel(
      kChannelUpdates,
      'App updates',
      description: 'Update alerts',
      importance: Importance.high,
      playSound: true,
      showBadge: true,
    ),
  );
  await android.createNotificationChannel(
    const AndroidNotificationChannel(
      kChannelSecurity,
      'Sign-in requests',
      description: 'Primary-phone login approval',
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
  return switch (type) {
    'APP_UPDATE' => kChannelUpdates,
    'LOGIN_CHALLENGE' => kChannelSecurity,
    _ => kChannelGeneral,
  };
}

int _notifId(PushMessage message) {
  final raw = message.id ??
      '${message.data['notificationId'] ?? ''}${message.hashCode}';
  return raw.hashCode & 0x7fffffff;
}

/// Posts to the Android status bar / shade.
/// Left circle = round app badge ([ic_notification_app]). No right largeIcon.
Future<void> _showTray(
  FlutterLocalNotificationsPlugin plugin,
  PushMessage message,
) async {
  final tb = _titleBodyFromMessage(message);
  if (tb == null) {
    debugPrint('[Push] no title/body to show in tray');
    return;
  }
  final channel = _channelForMessage(message);
  final id = _notifId(message);
  final payload = jsonEncode(message.data);

  // Status bar = white silhouette (Android rule). Shade left circle = opaque
  // black launcher badge via Person avatar (avoids Samsung white ring around
  // colored smallIcon). No largeIcon → no right-side preview.
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
          channelDescription: AppBrand.name,
          importance: Importance.high,
          priority: Priority.high,
          icon: _kSmallIcon,
          color: const Color(0xFF000000),
          colorized: false,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.message,
          styleInformation: MessagingStyleInformation(
            person,
            conversationTitle: tb.$1,
            groupConversation: false,
            messages: <Message>[
              Message(tb.$2, DateTime.now(), null),
            ],
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
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
          channelDescription: AppBrand.name,
          importance: Importance.high,
          priority: Priority.high,
          icon: icon,
          color: const Color(0xFF000000),
          colorized: false,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.message,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  try {
    await showMessaging();
    debugPrint('[Push] tray shown id=$id (avatar badge)');
  } catch (e) {
    debugPrint('[Push] messaging style failed: $e');
    try {
      await showPlain(icon: _kTrayIcon);
      debugPrint('[Push] tray shown id=$id (plain badge)');
    } catch (e2) {
      try {
        await showPlain(icon: _kSmallIcon);
      } catch (e3) {
        debugPrint('[Push] tray show failed: $e3');
      }
    }
  }
}
