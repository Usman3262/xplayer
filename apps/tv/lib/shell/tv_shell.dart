import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tv_catalog_sync.dart' show TvContentUpdateBanner, applyPendingCatalogUpdate;
import '../core/tv_text_input.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/remote_config.dart';
import '../core/push_notifications.dart';
import '../features/search/tv_search_screen.dart';
import '../core/tv_live_zap.dart';
import '../core/tv_locale.dart';
import '../core/tv_session.dart';
import '../core/tv_clock.dart';
import '../core/tv_section_back.dart';
import '../widgets/focus_tile.dart';
import '../widgets/tv_ui.dart';
import '../widgets/tv_exit_guard.dart';
import '../widgets/tv_shell_scope.dart';

/// Figma TV chrome: top nav capsule (not left rail).
class TvShell extends ConsumerStatefulWidget {
  const TvShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  static const allDestinations = [
    (label: 'Home', path: '/home'),
    (label: 'Movies', path: '/movies'),
    (label: 'Series', path: '/series'),
    (label: 'Live TV', path: '/live'),
    (label: 'Sports', path: '/sports'),
    (label: 'Kids', path: '/kids'),
  ];

  @override
  ConsumerState<TvShell> createState() => _TvShellState();
}

class _TvShellState extends ConsumerState<TvShell> {
  late final List<FocusNode> _navNodes = List.generate(
    6,
    (i) => FocusNode(debugLabel: 'tv-top-nav-$i'),
  );
  final FocusScopeNode _navScope = FocusScopeNode(
    debugLabel: 'tv-nav-scope',
    traversalEdgeBehavior: TraversalEdgeBehavior.stop,
  );
  final FocusScopeNode _contentScope = FocusScopeNode(
    debugLabel: 'tv-content-scope',
    traversalEdgeBehavior: TraversalEdgeBehavior.stop,
  );

  @override
  void initState() {
    super.initState();
    tvFocusTopMenu = _focusSidebar;
    FocusManager.instance.addListener(_rememberFocus);
  }

  /// Sections visited before the current one (LG 6.1.14: Back in a section
  /// returns to the section visited before, on the card the user was on;
  /// Home asks to exit). The Android TV app always went back to Home.
  final List<int> _tabHistory = [];
  final Map<int, FocusNode> _lastFocusByBranch = {};
  bool _goingBack = false;

  void _rememberFocus() {
    final n = FocusManager.instance.primaryFocus;
    if (n == null || !n.ancestors.contains(_contentScope)) return;
    _lastFocusByBranch[widget.navigationShell.currentIndex] = n;
  }

  @override
  void didUpdateWidget(covariant TvShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final from = oldWidget.navigationShell.currentIndex;
    final to = widget.navigationShell.currentIndex;
    if (from == to) return;
    if (_goingBack) {
      _goingBack = false;
      return;
    }
    _tabHistory
      ..remove(from)
      ..add(from);
    _tabHistory.remove(to);
  }

  /// After Back to [branch]: the card the user had there, else its first item.
  void _restoreFocusIn(int branch) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final n = _lastFocusByBranch[branch];
      if (n != null && n.context != null && n.canRequestFocus) {
        n.requestFocus();
      } else {
        _focusContent();
      }
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_rememberFocus);
    if (tvFocusTopMenu == _focusSidebar) tvFocusTopMenu = null;
    for (final n in _navNodes) {
      n.dispose();
    }
    _navScope.dispose();
    _contentScope.dispose();
    super.dispose();
  }

  Future<void> _onSystemBack() async {
    // The Back that closed the player (or its duplicate) must not also leave
    // Live/Sports for Home.
    if (tvBackSuppressed()) return;
    if (tvSectionBack?.call() ?? false) return;
    final shell = widget.navigationShell;
    if (shell.currentIndex != 0) {
      // The section visited before (as on LG), else Home.
      var prev = 0;
      while (_tabHistory.isNotEmpty) {
        final b = _tabHistory.removeLast();
        if (b != shell.currentIndex) {
          prev = b;
          break;
        }
      }
      _goingBack = true;
      shell.goBranch(prev);
      _restoreFocusIn(prev);
      return;
    }
    _tabHistory.clear();
    if (!mounted) return;
    await confirmTvExit(context, ref);
  }

  List<(String label, int branch)> _navItems(AppCopy copy) {
    final sportsOn = ref.watch(sportsEnabledProvider).valueOrNull ?? false;
    // Admin feature switches (remote config); the nav's design stays the same.
    bool on(String flag) => ref.watch(featureEnabledProvider(flag));
    return [
      (copy.home, 0),
      if (on('movies')) (copy.movies, 1),
      if (on('series')) (copy.series, 2),
      if (on('live_tv')) (copy.liveTv, 3),
      if (sportsOn) (copy.sports, 4),
      if (on('kids')) (copy.kids, 5),
    ];
  }

  void _focusSidebar() {
    final copy = AppCopy.ofLanguage(ref.read(tvLanguageProvider));
    final items = _navItems(copy);
    final branch = widget.navigationShell.currentIndex;
    var visible = 0;
    for (var i = 0; i < items.length; i++) {
      if (items[i].$2 == branch) {
        visible = i;
        break;
      }
    }
    _navScope.requestFocus();
    _navNodes[visible.clamp(0, _navNodes.length - 1)].requestFocus();
  }

  void _focusContent() {
    _contentScope.requestFocus();
    final existing = _contentScope.focusedChild;
    if (existing != null) {
      existing.requestFocus();
      return;
    }
    final first =
        ReadingOrderTraversalPolicy().findFirstFocus(_contentScope);
    first?.requestFocus();
  }

  void _goVisible(int visibleIndex) {
    final copy = AppCopy.ofLanguage(ref.read(tvLanguageProvider));
    final items = _navItems(copy);
    if (visibleIndex < 0 || visibleIndex >= items.length) return;
    final branch = items[visibleIndex].$2;
    // Waiting new content loads with the section being opened.
    if (branch != widget.navigationShell.currentIndex) applyPendingCatalogUpdate(ref);
    widget.navigationShell.goBranch(
      branch,
      initialLocation: branch == widget.navigationShell.currentIndex,
    );
  }

  int _selectedVisible(List<(String label, int branch)> items) {
    final branch = widget.navigationShell.currentIndex;
    for (var i = 0; i < items.length; i++) {
      if (items[i].$2 == branch) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    // Only what the top bar shows: watching the whole session rebuilt the
    // shell on every heartbeat / poll (TCL lag 21 Oct).
    final (profileInitials, avatarToken, isVip, loggedIn) = ref.watch(tvSessionProvider.select(
      (s) => (s.activeProfile?.initials ?? '', s.activeProfile?.avatar, s.isVip, s.loggedIn),
    ));
    // Chosen avatar in the top bar (client 21 Oct A11); none = initials.
    final avatarStyle = avatarStyleFor(avatarToken);
    final initials = profileInitials;
    final avatar = initials.isEmpty ? 'CK' : initials;
    final navItems = _navItems(copy);
    final selected = _selectedVisible(navItems);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 1280;
    final tight = width < 1100;
    final logoH = tight ? 26.0 : (compact ? 28.0 : 32.0);
    final navPadH = tight ? 10.0 : (compact ? 12.0 : 16.0);
    final navFont = tight ? 11.0 : 13.0;
    final barPad = tight
        ? const EdgeInsets.fromLTRB(16, 12, 16, 8)
        : const EdgeInsets.fromLTRB(36, 18, 36, 8);
    // Settings hub has its own header (back + SYSTEM SETTINGS). Hide shell
    // top nav so logo/nav/profile are not duplicated above it.
    final loc = GoRouterState.of(context).uri.path;
    final hideShellChrome = loc.startsWith('/settings');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onSystemBack();
      },
      child: TvShellScope(
        focusSidebar: _focusSidebar,
        focusContent: _focusContent,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Column(
            children: [
            if (!hideShellChrome)
            FocusScope(
              node: _navScope,
              child: SafeArea(
              bottom: false,
              child: Padding(
                padding: barPad,
                child: Row(
                  children: [
                    // Brand on start edge: left in LTR, right in RTL.
                    AppLogo(height: logoH, alignToStart: true),
                    SizedBox(width: tight ? 12 : 28),
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: FocusTraversalGroup(
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: tight ? double.infinity : 720,
                            ),
                            padding: const EdgeInsets.all(4),
                            // Glass menu container (Figma TV top bar).
                            decoration: TvGlassStyle.surface(
                              radius: BorderRadius.circular(999),
                            ),
                            // Never overflow: scroll if pills wider than slot.
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0; i < navItems.length; i++)
                                    FocusTile(
                                      focusNode: _navNodes[i],
                                      borderRadius: 999,
                                      focusScale: 1.0,
                                      // The blue current tab: glass focus
                                      // (client 12 Nov).
                                      glassFocus: selected == i,
                                      downToContent: true,
                                      onTap: () => _goVisible(i),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 140),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: navPadH,
                                          vertical: tight ? 8 : 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected == i
                                              ? AppColors.cyan
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          navItems[i].$1,
                                          style: TextStyle(
                                            color: selected == i
                                                ? Colors.black
                                                : Colors.white,
                                            fontWeight: AppFonts.control(
                                              FontWeight.w800,
                                            ),
                                            fontSize: navFont,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: tight ? 6 : 8),
                    if (loggedIn)
                      _TopIcon(
                        icon: Icons.notifications_none_rounded,
                        compact: tight,
                        badge: ref.watch(unreadNotificationsProvider),
                        onTap: () => context.push('/inbox'),
                      ),
                    if (loggedIn) SizedBox(width: tight ? 6 : 8),
                    FocusTile(
                      borderRadius: 999,
                      downToContent: true,
                      onTap: () {
                        final next =
                            AppLocale.next(ref.read(tvLanguageProvider));
                        ref.read(tvLanguageProvider.notifier).setLanguage(next);
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: tight ? 8 : 10,
                          vertical: tight ? 6 : 8,
                        ),
                        child: AppLanguageToggle(
                          language: ref.watch(tvLanguageProvider),
                          minimal: true,
                          onChanged: (v) => ref
                              .read(tvLanguageProvider.notifier)
                              .setLanguage(v),
                        ),
                      ),
                    ),
                    SizedBox(width: tight ? 6 : 8),
                    _TopIcon(
                      icon: Icons.search_rounded,
                      compact: tight,
                      onTap: () => context.go(
                        TvSearchScreen.searchPathFor(
                          GoRouterState.of(context).matchedLocation,
                        ),
                      ),
                    ),
                    // Clock always shown (client 5 Nov: "the clock at the top was
                    // removed"). It was hidden below 1100 px wide, and Android TV
                    // reports 960, so it never showed; it also never ticked.
                    const SizedBox(width: 12),
                    const _TvClockPill(),
                    SizedBox(width: tight ? 8 : 14),
                    FocusTile(
                      borderRadius: 22,
                      downToContent: true,
                      onTap: () => context.go('/my-account'),
                      // VIP pill centred under the avatar, inside the tile
                      // (it hung off the corner and the focus clip cut it to
                      // "VI", client 21 Oct). Same style as the profile card.
                      child: SizedBox(
                        width: tight ? 40 : 44,
                        height: (tight ? 36 : 40) + (isVip ? 8 : 0),
                        child: Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            Container(
                              width: tight ? 36 : 40,
                              height: tight ? 36 : 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: avatarStyle == null
                                    ? const LinearGradient(
                                        colors: [Color(0xFF1A2A3A), Color(0xFF0A1018)],
                                      )
                                    : LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: avatarStyle.colors,
                                      ),
                                border: Border.all(
                                  color: isVip ? AppColors.gold : AppColors.border,
                                  width: 1.4,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: avatarStyle == null
                                  ? Text(
                                      avatar,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    )
                                  : avatarStyle.asset != null
                                      // Illustrated face (point 37).
                                      ? ClipOval(child: avatarImage(avatarStyle, tight ? 36 : 40))
                                      : Icon(avatarStyle.icon, size: tight ? 20 : 22, color: Colors.white),
                            ),
                            if (isVip)
                              Positioned(
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.gold,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFF0A1018), width: 1),
                                  ),
                                  child: const Text(
                                    'VIP',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 8,
                                      height: 1.1,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
            Expanded(
              child: FocusScope(
                node: _contentScope,
                // Buttons and other non-tile controls: Up at the top edge of
                // the page goes to the top menu (tiles handle this themselves).
                onKeyEvent: (node, event) {
                  if (hideShellChrome) return KeyEventResult.ignored;
                  if (event is! KeyDownEvent ||
                      event.logicalKey != LogicalKeyboardKey.arrowUp) {
                    return KeyEventResult.ignored;
                  }
                  final primary = FocusManager.instance.primaryFocus;
                  if (tvMoveFocus(primary, TraversalDirection.up)) {
                    return KeyEventResult.handled;
                  }
                  final ctx = primary?.context;
                  if (ctx != null) {
                    tvEscapeUpFrom(ctx, _focusSidebar);
                  } else {
                    _focusSidebar();
                  }
                  return KeyEventResult.handled;
                },
                child: Stack(
                  children: [
                    Positioned.fill(child: widget.navigationShell),
                    if (!hideShellChrome)
                      const PositionedDirectional(top: 8, end: 36, child: TvContentUpdateBanner()),
                  ],
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

class _TopIcon extends StatelessWidget {
  const _TopIcon({
    required this.icon,
    required this.onTap,
    this.color,
    this.compact = false,
    this.badge = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final bool compact;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final s = compact ? 36.0 : 40.0;
    return FocusTile(
      borderRadius: 22,
      downToContent: true,
      onTap: onTap,
      // Glass circle (Figma TV top bar search button). The unread dot sits
      // inside the circle: as a Badge it hung over the corner and the
      // tile's rounded clip cut it into a red blob (TCL 21 Oct).
      child: Container(
        width: s,
        height: s,
        decoration: TvGlassStyle.surface(
          radius: BorderRadius.circular(s / 2),
          circle: true,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: compact ? 20 : 22, color: color),
            if (badge > 0)
              Positioned(
                top: s * 0.16,
                right: s * 0.18,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: AppColors.live,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Glass clock pill in the top bar (Figma TV top bar), 24 h, updated each minute.
class _TvClockPill extends StatefulWidget {
  const _TvClockPill();

  @override
  State<_TvClockPill> createState() => _TvClockPillState();
}

class _TvClockPillState extends State<_TvClockPill> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = tvClockNow(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: TvGlassStyle.surface(radius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 16, color: AppColors.cyan.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }
}
