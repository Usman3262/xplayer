import 'package:design_system/design_system.dart';

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_update.dart';
import '../core/app_update_provider.dart';
import '../core/in_app_update.dart';
import '../core/appearance_controller.dart';
import '../core/demo_mode.dart';
import '../core/providers.dart';
import '../core/remote_config.dart';
import '../core/session_controller.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _exitDialogOpen = false;
  bool _updateShown = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AppUpdateInfo?>(optionalUpdateProvider, (_, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferUpdate(next));
    }, fireImmediately: true);
  }

  /// "Update available" once per published version (client 23 Oct: release
  /// a version → users are told in the app; Update opens its page).
  Future<void> _maybeOfferUpdate(AppUpdateInfo? info) async {
    if (info == null || _updateShown || !mounted) return;
    // Demo (store review): no update prompt over the sample content.
    if (ref.read(demoModeProvider)) return;
    final url = (info.updateUrl ?? '').trim();
    if (url.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    const key = 'app_update_dismissed_version';
    if (prefs.getString(key) == info.latestVersion) return;
    if (!mounted) return;
    _updateShown = true;
    final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2A),
        title: Text(copy.updateAvailableTitle,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text(copy.updateAvailableBody(info.latestVersion),
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(copy.updateLater)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(copy.updateNow)),
        ],
      ),
    );
    await prefs.setString(key, info.latestVersion);
    if (go == true && mounted) await runInAppUpdate(context, info, isTv: false);
  }

  Future<void> _onSystemBack() async {
    final shell = widget.navigationShell;
    // Other tabs → always land on Home first.
    if (shell.currentIndex != 0) {
      shell.goBranch(0);
      return;
    }
    // Demo (client 4 Nov): Back on Home leaves the demo for the welcome
    // screen instead of closing the app.
    if (ref.read(demoModeProvider)) {
      exitDemo(ref);
      context.go('/auth/welcome');
      return;
    }
    if (_exitDialogOpen || !mounted) return;
    _exitDialogOpen = true;
    final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2A),
        title: Text(
          copy.exitAppTitle,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          copy.exitAppMessage,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(copy.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(copy.exitAppConfirm),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (leave == true) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sportsOn = ref.watch(sportsEnabledProvider).valueOrNull ?? false;
    // Admin feature switches (remote config); the bar's design stays the same.
    final moviesOn = ref.watch(featureEnabledProvider('movies'));
    final seriesOn = ref.watch(featureEnabledProvider('series'));
    final liveOn = ref.watch(featureEnabledProvider('live_tv'));
    final kidsOn = ref.watch(featureEnabledProvider('kids'));
    final idx = widget.navigationShell.currentIndex;
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    final appearance = ref.watch(appearanceProvider);
    final accents = appearance.accents;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onSystemBack();
      },
      child: Scaffold(
        body: AppAtmosphere(
          intensity: appearance.atmosphereIntensity,
          cyanAccent: accents.$1,
          magentaAccent: accents.$2,
          background: accents.$3,
          child: widget.navigationShell,
        ),
        // Frosted glass bar (client 17 Oct, same style as TV).
        bottomNavigationBar: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: AppGlass.bar,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      _NavItem(
                        icon: Icons.home_outlined,
                        activeIcon: Icons.home_rounded,
                        label: copy.home,
                        selected: idx == 0,
                        onTap: () {
                          if (idx == 0) return;
                          widget.navigationShell.goBranch(0);
                        },
                      ),
                      if (moviesOn)
                      _NavItem(
                        icon: Icons.movie_outlined,
                        activeIcon: Icons.movie_filter_rounded,
                        label: copy.movies,
                        selected: idx == 1,
                        onTap: () {
                          if (idx == 1) return;
                          widget.navigationShell.goBranch(1);
                        },
                      ),
                      if (seriesOn)
                      _NavItem(
                        icon: Icons.live_tv_outlined,
                        activeIcon: Icons.live_tv_rounded,
                        label: copy.series,
                        selected: idx == 2,
                        onTap: () {
                          if (idx == 2) return;
                          widget.navigationShell.goBranch(2);
                        },
                      ),
                      if (liveOn)
                      _NavItem(
                        icon: Icons.tv_outlined,
                        activeIcon: Icons.tv_rounded,
                        label: copy.liveTv,
                        selected: idx == 3,
                        onTap: () {
                          if (idx == 3) return;
                          widget.navigationShell.goBranch(3);
                        },
                      ),
                      // Sports when entitled; otherwise Kids in that slot
                      // (client 20 Oct).
                      if (sportsOn || kidsOn)
                      _NavItem(
                        icon: sportsOn
                            ? Icons.sports_soccer_outlined
                            : Icons.child_care_outlined,
                        activeIcon: sportsOn
                            ? Icons.sports_soccer
                            : Icons.child_care_rounded,
                        label: sportsOn ? copy.sports : copy.kids,
                        selected: idx == 4,
                        onTap: () {
                          if (idx == 4) return;
                          widget.navigationShell.goBranch(4);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.cyan : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Selected tab: glass pill behind the icon.
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 3,
                ),
                decoration: selected
                    ? AppGlass.surface(radius: BorderRadius.circular(999))
                    : const BoxDecoration(),
                child: Icon(
                  selected ? activeIcon : icon,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: AppFonts.control(
                    selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
