import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_log.dart';
import '../../core/app_update.dart';
import '../../core/app_update_provider.dart';
import '../../core/launch_sound.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _navigated = false;
  bool _nativeRemoved = false;
  late final Future<AppUpdateInfo> _updateCheck;
  bool _animDone = false;
  bool _stingStarted = false;

  @override
  void initState() {
    super.initState();
    _updateCheck = checkAppUpdate();
    AppLog.action('splash.init');
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    if (!mounted) return;
    // Start sound ASAP — don't wait for image decode.
    _startSting();
    // Reveal Flutter UI immediately; precache in background so low-end
    // phones are not stuck on native splash decoding large brand PNGs.
    _removeNativeSplash();
    unawaited(_precacheBrand());
    unawaited(_prefetchHome());
  }

  /// Start loading Home while the 1.8–3.2 s brand animation plays; Home's
  /// first request used to wait for the animation to end (19 Oct, live
  /// server). Only for a signed-in session with a profile.
  Future<void> _prefetchHome() async {
    final until = DateTime.now().add(const Duration(seconds: 4));
    while (mounted && !ref.read(sessionProvider).bootstrapped) {
      if (DateTime.now().isAfter(until)) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    if (!session.isLoggedIn || session.activeProfileId == null) return;
    AppLog.action('splash.prefetch_home');
    ref.read(homeFeedProvider.future).ignore();
    ref
        .read(catalogRepositoryProvider)
        .getCategories(MediaKind.live)
        .ignore();
  }

  Future<void> _precacheBrand() async {
    if (!mounted) return;
    try {
      final low =
          DeviceCapabilitiesStore.instance.current?.tier == DeviceTier.low;
      final jobs = <Future<void>>[
        precacheImage(
          const AssetImage(
            AppAssets.wordmark,
            package: AppAssets.package,
          ),
          context,
        ),
        precacheImage(
          const AssetImage(
            AppAssets.logoLockup,
            package: AppAssets.package,
          ),
          context,
        ),
        precacheImage(
          const AssetImage(
            AppAssets.logoLockupRtl,
            package: AppAssets.package,
          ),
          context,
        ),
      ];
      // Heavy mark PNG is optional on LOW — SVG mark is used on splash.
      if (!low) {
        jobs.add(
          precacheImage(
            const AssetImage(
              AppAssets.logoMark,
              package: AppAssets.package,
            ),
            context,
          ),
        );
      }
      await Future.wait(jobs).timeout(const Duration(seconds: 2));
    } catch (e) {
      AppLog.info('Splash', 'precache skipped: $e');
    }
  }

  void _startSting() {
    if (_stingStarted) return;
    _stingStarted = true;
    AppLog.action('splash.play_sting');
    // Fire-and-forget; player survives this route via launch_sound holder.
    playAppLaunchSting();
  }

  void _removeNativeSplash() {
    if (_nativeRemoved) return;
    _nativeRemoved = true;
    AppLog.action('splash.native_removed');
    FlutterNativeSplash.remove();
  }

  void _onAnimComplete() {
    AppLog.action('splash.anim_complete');
    _animDone = true;
    _tryGoNext();
  }

  Future<void> _tryGoNext() async {
    if (_navigated || !mounted || !_animDone) return;
    final session = ref.read(sessionProvider);
    if (!session.bootstrapped) {
      Future<void>.delayed(const Duration(milliseconds: 80), _tryGoNext);
      return;
    }
    _navigated = true;
    _removeNativeSplash();

    try {
      final update = await _updateCheck;
      if (!mounted) return;
      if (update.required) {
        AppLog.nav('splash→update');
        ref.read(pendingUpdateProvider.notifier).state = update;
        context.go('/update');
        return;
      }
      if (update.offerUpdate && (update.updateUrl ?? '').isNotEmpty) {
        ref.read(optionalUpdateProvider.notifier).state = update;
      }
    } catch (e) {
      AppLog.info('Splash', 'update check skipped: $e');
    }

    if (!mounted) return;
    final next = !session.onboardingDone
        ? '/onboarding'
        : !session.isLoggedIn
        ? '/auth/welcome'
        : !session.profileSelected
        ? '/profiles'
        : '/home';
    AppLog.nav('splash→next', to: next);
    context.go(next);
    // Client 18 Oct #4: started without internet → straight to downloads.
    if (session.offline && next == '/home') context.push('/downloads');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Task #143 #1: smaller launch mark (was ~22% / up to 140).
    final markH = (size.shortestSide * 0.16).clamp(72.0, 110.0);
    // Wordmark stays much smaller than the mark (client brand feedback).
    final wordH = (size.shortestSide * 0.028).clamp(12.0, 18.0);

    ref.listen(sessionProvider.select((s) => s.bootstrapped), (_, ready) {
      if (ready) _tryGoNext();
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.15),
                radius: 1.1,
                colors: [Color(0xFF0A1520), Color(0xFF000000)],
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: AppSplashBrand(
                markHeight: markH,
                wordmarkHeight: wordH,
                duration:
                    DeviceCapabilitiesStore.instance.current?.tier ==
                        DeviceTier.low
                    ? const Duration(milliseconds: 1800)
                    : const Duration(milliseconds: 3200),
                onFirstFrame: _removeNativeSplash,
                onComplete: _onAnimComplete,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: SafeArea(
              top: false,
              child: Center(
                child: Container(
                  width: 128,
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: LinearGradient(
                      colors: [AppColors.cyan, AppColors.magenta],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
