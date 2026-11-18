import 'package:data/data.dart' show FavoriteCategories;

import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart' show AppBrand;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/device_checkin.dart';
import 'core/library_cloud.dart';
import 'core/appearance_controller.dart';
import 'core/catalog_sync.dart';
import 'core/demo_mode.dart';
import 'core/library_controller.dart';
import 'core/downloads_controller.dart';
import 'core/backend.dart';
import 'core/providers.dart';
import 'core/account.dart';
import 'core/adult.dart';
import 'core/catalog.dart';
import 'core/remote_logs.dart';
import 'core/panels.dart';
import 'core/remote_config.dart';
import 'core/screen_record_protect.dart';
import 'core/session_controller.dart';
import 'widgets/maintenance_gate.dart';
import 'router/app_router.dart';
import 'core/orientation_policy.dart';
import 'core/push_notifications.dart';
import 'widgets/content_update_banner.dart';
import 'widgets/login_challenge_host.dart';
import 'widgets/reminder_banner.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Favourite channel categories (Live vs Sports split, client 21 Oct).
  unawaited(FavoriteCategories.load());
  final mkStart = DateTime.now();
  MediaKit.ensureInitialized();
  final mkMs = DateTime.now().difference(mkStart).inMilliseconds;
  if (kDebugMode || kProfileMode) {
    debugPrint(
      '[DEV] t=${DateTime.now().millisecondsSinceEpoch} MediaKit.ensureInitialized ms=$mkMs',
    );
  }
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  applyAppOrientations();
  // Kick device caps + image-cache caps ASAP so low-end UI does not thrash.
  unawaited(DeviceCapabilitiesStore.instance.ensureLoaded().then((c) {
    RemoteLogs.setModel('${c.brand} ${c.model}'.trim());
    Diag.event('APP', 'device ${c.brand} ${c.model}, android ${c.release} (sdk ${c.sdkInt}), tier ${c.tier.name}');
  }));
  widgetsBinding.addPostFrameCallback((_) {
    unawaited(logDeviceStartupDiag());
  });
  // App name comes from /app.config via the native launcher label.
  final packageInfo = await PackageInfo.fromPlatform();
  // Important log lines go to the server (support / remote testing).
  await RemoteLogs.start(appVersion: '${packageInfo.version}+${packageInfo.buildNumber}');
  Diag.event('APP', 'start ${packageInfo.version}+${packageInfo.buildNumber} '
      '(${kDebugMode ? 'debug' : 'release'}), install ${RemoteLogs.deviceId}');
  AppBrand.init(packageInfo.appName);
  // Backend + admin config: cached config applies before the first frame
  // (instant, no network); the fresh one arrives in the background.
  await Backend.init();
  AccountService.init();
  LibraryCloud.init(); // signed-in library ↔ account (Phase 8)
  DeviceCheckin.init(); // signed-in device ↔ account (8.3)
  await RemoteConfigService.init(appVersion: packageInfo.version);
  await PanelsService.init();
  runApp(const ProviderScope(child: MobileRootApp()));
}

class MobileRootApp extends ConsumerStatefulWidget {
  const MobileRootApp({super.key});

  @override
  ConsumerState<MobileRootApp> createState() => _MobileRootAppState();
}

class _MobileRootAppState extends ConsumerState<MobileRootApp>
    with WidgetsBindingObserver {
  Timer? _deviceHeartbeatTimer;
  Timer? _unreadPollTimer;
  bool _pushBootstrapped = false;

  late final CatalogSync _catalogSync = CatalogSync(ref);

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // Global theme (AppThemeConfig): a new theme rebuilds the whole app.
    AppThemeConfig.revision.addListener(_onThemeChanged);
    WidgetsBinding.instance.addObserver(this);
    _catalogSync.start();
    // Start the downloads controller with the app, not when a screen first
    // shows it: an interrupted download now continues after a restart
    // (client 21 Oct "downloads stopped"; it waited for the Downloads tab).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(sessionProvider).isLoggedIn) {
        ref.read(appDownloadsProvider);
      }
    });
    ref.listenManual(sessionProvider.select((s) => s.isLoggedIn), (_, logged) {
      if (logged) ref.read(appDownloadsProvider);
    });
    _deviceHeartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_pulseDeviceHeartbeat());
    });
    _unreadPollTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      unawaited(PushNotifications.refreshUnread());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_pulseDeviceHeartbeat());
      unawaited(_bootstrapPush());
    });
  }

  Future<void> _bootstrapPush() async {
    if (_pushBootstrapped) return;
    _pushBootstrapped = true;
    await PushNotifications.start(
      container: ProviderScope.containerOf(context),
      router: ref.read(routerProvider),
    );
  }

  @override
  void dispose() {
    _deviceHeartbeatTimer?.cancel();
    _unreadPollTimer?.cancel();
    _catalogSync.dispose();
    WidgetsBinding.instance.removeObserver(this);
    AppThemeConfig.revision.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _pulseDeviceHeartbeat() async {
    // Real installed version (was a stale '5.1.30' constant).
    final info = await PackageInfo.fromPlatform();
    await ref
        .read(sessionProvider.notifier)
        .sendDeviceHeartbeat(appVersion: info.version);
  }

  DateTime? _pausedAt;
  static const _reloadListsAfter = Duration(minutes: 30);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retest #24: refresh catalog when returning from background (CP sync).
    // Downloads continue by themselves after the OS stopped them in the
    // background (client 20 Oct).
    // Demo has no account and no downloads: never start the controller.
    final demo = ref.read(demoModeProvider);
    if (state == AppLifecycleState.paused) {
      CatalogService.pause(); // panel catalog sync continues on return
      AdultService.hide(); // 18+ needs the PIN again after leaving the app
      unawaited(RemoteLogs.flush());
      _pausedAt ??= DateTime.now();
      if (!demo) ref.read(appDownloadsProvider.notifier).appPaused();
    }
    if (state == AppLifecycleState.resumed) {
      CatalogService.resume();
      LibraryCloud.syncSoon(const Duration(seconds: 3));
      unawaited(DeviceCheckin.run());
      if (!demo) ref.read(appDownloadsProvider.notifier).appResumed();
      unawaited(_catalogSync.check());
      // Lists reload only after a long time away (client 2 Nov: content
      // too slow). Every return used to download all lists again, even
      // after Control Center or background playback; catalog changes are
      // still picked up by the version check above.
      final away = _pausedAt == null
          ? Duration.zero
          : DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (away >= _reloadListsAfter) {
        ref.invalidate(homeFeedProvider);
        ref.invalidate(moviesProvider);
        ref.invalidate(seriesProvider);
        ref.invalidate(liveChannelsProvider);
      }
      unawaited(ref.read(libraryProvider.notifier).syncFromRemote());
      unawaited(_pulseDeviceHeartbeat());
      unawaited(PushNotifications.onAppResumed());
      unawaited(RemoteConfigService.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    // New admin config (branding/flags) → rebuild; theme has its own listener.
    ref.watch(remoteConfigProvider);
    ref.listen<bool>(sessionProvider.select((s) => s.isLoggedIn), (prev, next) {
      if (next == true) {
        unawaited(PushNotifications.syncToken());
        unawaited(PushNotifications.refreshUnread());
      }
    });
    final router = ref.watch(routerProvider);
    final language = ref.watch(sessionProvider.select((s) => s.language));
    final lang = AppLocale.resolve(language);
    final rtl = AppLocale.isRtl(language);
    final appearance = ref.watch(appearanceProvider);
    final accents = appearance.accents;
    ref.watch(screenRecordProtectProvider);

    final base = buildAppTheme(arabic: rtl);
    final themed = base.copyWith(
      scaffoldBackgroundColor: accents.$3,
      colorScheme: base.colorScheme.copyWith(
        primary: accents.$1,
        secondary: accents.$2,
      ),
    );

    // Task #143 #7: EN + AR only (Urdu removed).
    final materialLocale = lang == AppLang.ar
        ? const Locale('ar')
        : const Locale('en');

    return MaterialApp.router(
      scaffoldMessengerKey: appMessengerKey,
      key: ValueKey(
        'lang-$language-rtl-$rtl-theme-${AppThemeConfig.revision.value}',
      ),
      title: AppBrand.name,
      debugShowCheckedModeBanner: false,
      theme: themed,
      locale: materialLocale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localeResolutionCallback: (device, supported) {
        if (lang == AppLang.ar) return const Locale('ar');
        return const Locale('en');
      },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: MaintenanceGate(
            child: ScreenRecordGuard(
              // Keep Allow/Deny polling alive on every route (profiles, settings…).
              child: LoginChallengeHost(
                child: ReminderBanner(
                  onWatch: (id) => router.push('/player/$id?kind=live'),
                  child: ContentUpdateBanner(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      routerConfig: router,
    );
  }
}
