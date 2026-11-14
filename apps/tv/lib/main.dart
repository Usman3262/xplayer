import 'package:data/data.dart' show FavoriteCategories;

import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart' show AppBrand;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/library_controller.dart';
import 'core/tv_catalog_sync.dart';
import 'core/tv_frame_stats.dart';
import 'core/tv_input_activity.dart';
import 'core/backend.dart';
import 'core/providers.dart';
import 'core/remote_config.dart';
import 'core/screen_record_protect.dart';
import 'core/tv_appearance.dart';
import 'core/tv_session.dart';
import 'core/tv_text_input.dart';
import 'core/tv_locale.dart';
import 'core/push_notifications.dart';
import 'widgets/maintenance_gate.dart';
import 'router/tv_router.dart';
import 'widgets/tv_reminder_banner.dart';
import 'widgets/focus_tile.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  AppLogo.decodeNearDisplaySize = true;
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
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  installTvTextInputKeyHandler();
  // TV is driven by the remote. Any pointer event (air mouse, touchpad
  // remote, a mouse over the emulator) switched Flutter to touch mode and
  // hid every focus ring, so the remote looked dead.
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  if (kProfileMode && DiagConfig.verboseApi) {
    // Opt-in only: every focus hop floods logcat during remote testing.
    FocusManager.instance.addListener(() {
      final f = FocusManager.instance.primaryFocus;
      Rect? r;
      try {
        r = f?.rect;
      } catch (_) {}
      debugPrint(
        '[FOCUS] ${f?.context?.widget.runtimeType} '
        '${r == null ? '-' : '${r.left.round()},${r.top.round()} ${r.width.round()}x${r.height.round()}'}',
      );
    });
  }
  unawaited(DeviceCapabilitiesStore.instance.ensureLoaded());
  binding.addPostFrameCallback((_) {
    unawaited(logDeviceStartupDiag());
  });
  // App name comes from /app.config via the native launcher label.
  final packageInfo = await PackageInfo.fromPlatform();
  AppBrand.init(packageInfo.appName);
  // Backend + admin config: cached config applies before the first frame
  // (instant, no network); the fresh one arrives in the background.
  await Backend.init();
  await RemoteConfigService.init(appVersion: packageInfo.version);
  runApp(const ProviderScope(child: TvRootApp()));
}

class TvRootApp extends ConsumerStatefulWidget {
  const TvRootApp({super.key});

  @override
  ConsumerState<TvRootApp> createState() => _TvRootAppState();
}

class _TvRootAppState extends ConsumerState<TvRootApp>
    with WidgetsBindingObserver {
  Timer? _deviceHeartbeatTimer;
  Timer? _unreadPollTimer;
  bool _pushBootstrapped = false;

  Timer? _uiLog;
  late final TvCatalogSync _catalogSync = TvCatalogSync(ref);

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // Global theme (AppThemeConfig): a new theme rebuilds the whole app.
    AppThemeConfig.revision.addListener(_onThemeChanged);
    WidgetsBinding.instance.addObserver(this);
    TvInputActivity.ensureStarted();
    _catalogSync.start();
    _uiLog = TvFrameStats.instance.startUiLog(() {
      try {
        return ref
            .read(tvRouterProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path;
      } catch (_) {
        return '-';
      }
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
      router: ref.read(tvRouterProvider),
    );
  }

  @override
  void dispose() {
    _deviceHeartbeatTimer?.cancel();
    _unreadPollTimer?.cancel();
    _uiLog?.cancel();
    _catalogSync.dispose();
    WidgetsBinding.instance.removeObserver(this);
    AppThemeConfig.revision.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _pulseDeviceHeartbeat() async {
    // Real installed version (was a stale '5.1.33' constant).
    final info = await PackageInfo.fromPlatform();
    await ref
        .read(tvSessionProvider.notifier)
        .sendDeviceHeartbeat(appVersion: info.version);
  }

  DateTime? _pausedAt;
  static const _reloadListsAfter = Duration(minutes: 30);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pausedAt ??= DateTime.now();
    if (state == AppLifecycleState.resumed) {
      unawaited(_catalogSync.check());
      applyPendingCatalogUpdate(ref);
      // Lists reload only after a long time away (client 2 Nov: content
      // too slow); catalog changes still come through the version check.
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
    ref.listen<bool>(tvSessionProvider.select((s) => s.loggedIn), (prev, next) {
      if (next == true) {
        unawaited(PushNotifications.syncToken());
        unawaited(PushNotifications.refreshUnread());
      }
    });
    final router = ref.watch(tvRouterProvider);
    final language = ref.watch(tvLanguageProvider);
    ref.watch(screenRecordProtectProvider);
    final appearance = ref.watch(tvAppearanceProvider);
    final accents = appearance.accents;
    final lang = AppLocale.resolve(language);
    final rtl = AppLocale.isRtl(language);
    final base = buildAppTheme();
    final themed = base.copyWith(
      scaffoldBackgroundColor: accents.$3,
      colorScheme: base.colorScheme.copyWith(
        primary: accents.$1,
        secondary: accents.$2,
      ),
      visualDensity: VisualDensity.comfortable,
      textTheme: _tvTextTheme(base.textTheme),
    );
    // Task #143 #7: EN + AR only (Urdu removed).
    final materialLocale = lang == AppLang.ar
        ? const Locale('ar')
        : const Locale('en');
    return MaterialApp.router(
      key: ValueKey(
        'tv-lang-$language-rtl-$rtl-theme-${appearance.name}-${AppThemeConfig.revision.value}',
      ),
      title: '${AppBrand.name} TV',
      debugShowCheckedModeBanner: false,
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
      theme: themed,
      builder: (context, child) {
        return Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: MaintenanceGate(
            child: ScreenRecordGuard(
              child: TvReminderBanner(
                onWatch: (id) => router.push('/player/$id?kind=live'),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      routerConfig: router,
      // Web (LG webOS) only: Flutter's web defaults map the arrows to
      // scrolling, which wins on every scrolling page, so the remote could
      // not move between buttons (details: Play -> My List). Android TV
      // keeps its defaults (null).
      shortcuts: kIsWeb ? _webRemoteShortcuts : null,
      actions: <Type, Action<Intent>>{
        ...WidgetsApp.defaultActions,
        DirectionalFocusIntent: _TvDirectionalFocusAction(),
      },
    );
  }
}

/// The Android arrow / OK mappings on top of the web defaults.
final Map<ShortcutActivator, Intent> _webRemoteShortcuts = {
  ...WidgetsApp.defaultShortcuts,
  const SingleActivator(LogicalKeyboardKey.arrowLeft):
      const DirectionalFocusIntent(TraversalDirection.left),
  const SingleActivator(LogicalKeyboardKey.arrowRight):
      const DirectionalFocusIntent(TraversalDirection.right),
  const SingleActivator(LogicalKeyboardKey.arrowUp):
      const DirectionalFocusIntent(TraversalDirection.up),
  const SingleActivator(LogicalKeyboardKey.arrowDown):
      const DirectionalFocusIntent(TraversalDirection.down),
  const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
};

/// Arrow keys on plain buttons (dialogs, settings) use the same
/// history-free move as [FocusTile].
class _TvDirectionalFocusAction extends Action<DirectionalFocusIntent> {
  @override
  void invoke(DirectionalFocusIntent intent) {
    final node = FocusManager.instance.primaryFocus;
    if (node == null) return;
    if (!intent.ignoreTextFields && node.context?.widget is EditableText) {
      return;
    }
    tvMoveFocus(node, intent.direction);
  }
}

TextTheme _tvTextTheme(TextTheme base) {
  TextStyle sized(TextStyle? style, double fontSize) {
    return (style ?? const TextStyle()).copyWith(fontSize: fontSize);
  }

  return base.copyWith(
    // TV canvas is 960x540 logical px; these read well from the sofa
    // without the oversized look of the first TV builds.
    displayLarge: sized(base.displayLarge, 34),
    headlineMedium: sized(base.headlineMedium, 24),
    titleLarge: sized(base.titleLarge, 18),
    titleMedium: sized(base.titleMedium, 15),
    bodyLarge: sized(base.bodyLarge, 15),
    // Default text is white on TV. The shared theme's grey (#9AA3B2) was
    // inherited by every title without its own colour (hero titles,
    // channel names) and was hard to read from the sofa (client 19 Oct).
    // Secondary text already sets textSecondary explicitly.
    bodyMedium: sized(
      base.bodyMedium,
      14,
    ).copyWith(color: AppColors.textPrimary),
    labelLarge: sized(base.labelLarge, 13),
  );
}
