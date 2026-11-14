import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_log.dart';
import '../core/demo_mode.dart';
import '../core/push_notifications.dart';
import '../core/remote_config.dart';
import '../core/session_controller.dart';
import '../core/ui_sound.dart';

class MainAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const MainAppBar({
    super.key,
    this.showBack = false,
    this.centerTitle = false,
  });

  final bool showBack;
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(78);

  void _goOnce(BuildContext context, String path) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc == path || loc.startsWith('$path/')) return;
    // Push so system/app-bar back returns toward Home instead of leaving the app.
    context.push(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final copy = AppCopy.ofLanguage(session.language);
    final profile = session.activeProfile;
    final initials = profile?.initials ?? 'CK';
    final isVip = session.user?.isVip ?? true;
    // Demo: the same pill reads DEMO instead of VIP
    final demo = ref.watch(demoModeProvider);

    return AppBar(
      toolbarHeight: 78,
      centerTitle: false,
      // Task #143 #11: visible Back control on details (icon only).
      leadingWidth: showBack ? 56 : 0,
      leading: showBack
          ? IconButton(
              tooltip: copy.playbackBack,
              onPressed: () {
                playUiTap(ref);
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
              icon: const AppBackIcon(size: 22),
            )
          : const SizedBox.shrink(),
      titleSpacing: showBack ? 0 : 12,
      title: const Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1,
        child: AppLogo(height: 32, alignToStart: true),
      ),
      actions: [
        if (session.isLoggedIn &&
            ref.watch(featureEnabledProvider('notification_inbox')))
          IconButton(
            tooltip: copy.notifications,
            onPressed: () {
              playUiTap(ref);
              AppLog.tap('app_bar.inbox');
              _goOnce(context, '/inbox');
            },
            icon: Badge(
              isLabelVisible: ref.watch(unreadNotificationsProvider) > 0,
              label: Text(
                '${ref.watch(unreadNotificationsProvider).clamp(1, 99)}',
                style: const TextStyle(fontSize: 10),
              ),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
        if (ref.watch(featureEnabledProvider('search')))
          IconButton(
            tooltip: copy.search,
            onPressed: () {
              playUiTap(ref);
              AppLog.tap('app_bar.search');
              // Search stays inside the section it is opened from; Home and
              // pages outside the tabs search everything.
              final tab = StatefulNavigationShell.maybeOf(context)
                  ?.currentIndex;
              final scope = switch (tab) {
                1 => 'movie',
                2 => 'series',
                3 => 'live',
                4 => 'sports',
                _ => null,
              };
              _goOnce(
                context,
                scope == null ? '/search' : '/search?scope=$scope',
              );
            },
            icon: const Icon(Icons.search_rounded),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 2),
          child: Center(
            child: AppLanguageToggle(
              language: session.language,
              minimal: true,
              onChanged: (v) {
                playUiTap(ref);
                AppLog.tap('app_bar.language');
                ref.read(sessionProvider.notifier).setLanguage(v);
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 4,
            end: 16,
            top: 6,
            bottom: 6,
          ),
          child: GestureDetector(
            onTap: () {
              playUiTap(ref);
              AppLog.tap('app_bar.profile');
              _goOnce(context, '/my-account');
            },
            onLongPress: () {
              playUiTap(ref);
              AppLog.tap('app_bar.profiles');
              _goOnce(context, '/profiles');
            },
            // VIP pill on the lower edge of the circle, as on TV (client 21
            // Oct: "inside the circle, exactly as on the TV version").
            child: SizedBox(
              width: 38,
              height: isVip ? 42 : 34,
              child: Stack(
                alignment: Alignment.topCenter,
                clipBehavior: Clip.none,
                children: [
                  // Chosen avatar shows on Home too (client 21 Oct A11);
                  // no avatar keeps the gold initials badge.
                  if (avatarStyleFor(profile?.avatar) != null)
                    ProfileAvatar(
                      initials: initials,
                      token: profile?.avatar,
                      size: 34,
                    )
                  else
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.gold, width: 1.4),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3A2A10), Color(0xFF1A1408)],
                        ),
                      ),
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  if (isVip)
                    Positioned(
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFF0A1018),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          demo ? 'DEMO' : 'VIP',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 7.5,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
