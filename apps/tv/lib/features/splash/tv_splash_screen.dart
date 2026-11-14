import 'package:data/data.dart' show TvPlatformProfile;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_update.dart';
import '../../core/app_update_provider.dart';
import '../../core/launch_sound.dart';
import '../../core/tv_session.dart';

class TvSplashScreen extends ConsumerStatefulWidget {
  const TvSplashScreen({super.key});

  @override
  ConsumerState<TvSplashScreen> createState() => _TvSplashScreenState();
}

class _TvSplashScreenState extends ConsumerState<TvSplashScreen> {
  bool _navigated = false;
  bool _animDone = false;
  bool _stingStarted = false;
  late final Future<AppUpdateInfo> _updateCheck;

  @override
  void initState() {
    super.initState();
    _updateCheck = checkAppUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _stingStarted) return;
      _stingStarted = true;
      // Slow TVs (LG webOS): the first frames reach the screen late, so the
      // sting played before the logo animation was visible (client 26 Oct
      // "sound starts before the picture"). Wait until frames are flowing.
      // Start with the animation's first drawn frame. (Waiting 3 frames +
      // 350 ms made it play after the splash on the client's TV, 26 Oct #2.)
      if (TvPlatformProfile.lowPowerUi) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      playAppLaunchSting();
    });
  }

  void _onAnimComplete() {
    _animDone = true;
    _tryGoNext();
  }

  Future<void> _tryGoNext() async {
    if (_navigated || !mounted || !_animDone) return;
    final session = ref.read(tvSessionProvider);
    if (!session.bootstrapped) return;

    _navigated = true;

    AppUpdateInfo? optional;
    try {
      // A slow update check must not keep the splash on screen.
      final update = await _updateCheck.timeout(const Duration(milliseconds: 1500));
      if (!mounted) return;
      if (update.required) {
        ref.read(pendingUpdateProvider.notifier).state = update;
        context.go('/update');
        return;
      }
      if (update.offerUpdate && (update.updateUrl ?? '').isNotEmpty) {
        optional = update;
      }
    } catch (_) {}

    if (!mounted) return;
    if (!session.loggedIn) {
      context.go('/login');
    } else if (!session.profileSelected) {
      context.go('/profiles');
    } else {
      context.go('/home');
      // Client 18 Oct #4: started without internet → straight to downloads.
      if (session.offline) {
        context.push('/downloads');
      } else if (optional != null) {
        // Client 23 Oct: a new version is published → tell the user once per
        // version (Back closes it; the update screen opens the download).
        final prefs = await SharedPreferences.getInstance();
        const key = 'tv_update_offered_version';
        if (prefs.getString(key) != optional.latestVersion && mounted) {
          await prefs.setString(key, optional.latestVersion);
          ref.read(pendingUpdateProvider.notifier).state = optional;
          if (mounted) context.push('/update');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Task #143 #1: smaller launch mark.
    final markH = (size.shortestSide * 0.14).clamp(88.0, 128.0);
    // Wordmark stays much smaller than the mark (client brand feedback).
    final wordH = (size.shortestSide * 0.025).clamp(14.0, 20.0);

    ref.listen(tvSessionProvider.select((s) => s.bootstrapped), (_, ready) {
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
                center: Alignment(0, -0.1),
                radius: 1.05,
                colors: [Color(0xFF0A1520), Color(0xFF000000)],
              ),
            ),
          ),
          Center(
            child: AppSplashBrand(
              // Shorter opening (client 1 Nov #1, 2 Nov #1: "far too long");
              // same animated lines around the logo, 3.2 s → 2.2 s.
              duration: const Duration(milliseconds: 2200),
              markHeight: markH,
              wordmarkHeight: wordH,
              onComplete: _onAnimComplete,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 150,
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: LinearGradient(
                      colors: [AppColors.cyan, AppColors.magenta],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TechBadge(TvPlatformProfile.splashBadge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
