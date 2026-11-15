import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:domain/domain.dart' show AppBrand;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/login_screen.dart' show showSupportHelpSheet;

import '../../core/demo_mode.dart';
import '../../core/remote_config.dart';
import '../../core/providers.dart';
import '../../core/panels.dart';
import '../../core/session_controller.dart';
import '../../core/app_log.dart';
import '../../core/ui_sound.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/stream_session_tile.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Demo has no account: nothing to load from the server.
      if (ref.read(demoModeProvider)) return;
      ref
          .read(sessionProvider.notifier)
          .refreshDevicesAndSessions()
          .catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final demo = ref.watch(demoModeProvider);
    final user = session.user;
    final profile = session.activeProfile;
    final uiSounds = ref.watch(uiSoundProvider);
    final copy = AppCopy.ofLanguage(session.language);
    final deviceLimit = user?.deviceLimit ?? 5;
    final devicesLabel = copy.devicesOfLimit(
      session.devices.length,
      deviceLimit,
      session.sessions.length,
    );

    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: AppAtmosphere(
        intensity: 0.7,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    copy.settings,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                TechBadge(
                  'v${ref.watch(appVersionProvider).valueOrNull ?? ''}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            NeonTap(
              onTap: () {
                playUiTap(ref);
                context.push('/profiles');
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.10),
                      AppColors.surface.withValues(alpha: 0.94),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.10),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Column(
                      children: [
                        ProfileAvatar(
                          initials: profile?.initials ?? 'CK',
                          token: profile?.avatar,
                          size: 40,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ref.watch(demoModeProvider) ? 'DEMO' : 'VIP',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        user?.name ?? '${AppBrand.name} User',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _section(copy.sectionAccount, [
              _nav(
                context,
                ref,
                Icons.dns_rounded,
                copy.myPanels,
                value: '${ref.watch(panelsProvider).where((c) => c.enabled).length}',
                route: '/settings/panels',
              ),
              _nav(
                context,
                ref,
                Icons.people_alt_rounded,
                copy.profiles,
                value: copy.profilesActive(session.profiles.length),
                route: '/profiles/manage',
              ),
              _nav(
                context,
                ref,
                Icons.workspace_premium_rounded,
                copy.subscriptionPackage,
                value: ref
                    .watch(subscriptionsProvider)
                    .when(
                      data: (list) {
                        if (list.isEmpty) return '—';
                        final sub = list.first;
                        final end = DateTime.tryParse(sub.renewsAt ?? '');
                        final days = end?.difference(DateTime.now()).inDays;
                        return [
                          sub.packageName.isNotEmpty
                              ? sub.packageName
                              : sub.status.toUpperCase(),
                          if (days != null && days >= 0)
                            copy.daysRemaining(days),
                        ].join(' · ');
                      },
                      loading: () => '…',
                      error: (_, _) => '—',
                    ),
                route: '/settings/subscription',
                badge: true,
              ),
              _nav(
                context,
                ref,
                Icons.devices_rounded,
                copy.devicesSessions,
                value: devicesLabel,
                route: '/settings/devices',
              ),
              _nav(
                context,
                ref,
                Icons.verified_user_rounded,
                copy.signInRequestsTitle,
                subtitle: copy.signInRequestsSubtitle,
                route: '/settings/sign-in-requests',
              ),
              if (user != null)
                _nav(
                  context,
                  ref,
                  Icons.tv_rounded,
                  copy.pairTvTitle,
                  subtitle: copy.pairTvSubtitle,
                  route: '/settings/devices/pair-tv',
                ),
              _nav(
                context,
                ref,
                Icons.security_rounded,
                copy.security,
                value: user?.mfaEnabled == true ? copy.mfaOn : copy.passwordMfa,
                route: '/settings/security',
              ),
            ]),
            _section(copy.sectionPlayback, [
              // Server playback lease status: account only.
              if (!demo) StreamSessionTile(copy: copy),
              _nav(
                context,
                ref,
                Icons.high_quality_rounded,
                copy.playbackPrefs,
                value: session.playbackQuality == 'Auto'
                    ? copy.qualityAuto
                    : session.playbackQuality,
                route: '/settings/playback',
              ),
              // "Audio & Subtitles" removed (client 20 Oct); tracks stay
              // switchable in the player.
              _switchRow(
                icon: Icons.play_circle_outline_rounded,
                title: copy.autoplay,
                value: session.autoplay,
                onChanged: (v) {
                  playUiTap(ref);
                  ref.read(sessionProvider.notifier).setAutoplay(v);
                },
              ),
              // Screen capture protection: owner-only in the Control Panel (client 27 Oct).
            ]),
            _section(copy.sectionLookSound, [
              if (ref.watch(featureEnabledProvider('diagnostics')))
                _nav(
                  context,
                  ref,
                  Icons.speed_rounded,
                  copy.connectionDiagnostic,
                  subtitle: copy.connectionDiagnosticHint,
                  route: '/settings/diagnostic',
                ),
              if (ref.watch(featureEnabledProvider('theme_presets')))
                _nav(
                  context,
                  ref,
                  Icons.palette_rounded,
                  copy.appearanceThemes,
                  subtitle: copy.appliesAcross,
                  route: '/settings/appearance',
                ),
              _switchRow(
                icon: Icons.volume_up_rounded,
                iconColor: AppColors.magenta,
                title: copy.uiSounds,
                subtitle: copy.uiSoundsHint,
                value: uiSounds,
                onChanged: (v) =>
                    ref.read(uiSoundProvider.notifier).setEnabled(v),
              ),
            ]),
            // Developer tool: debug builds only (client builds showed it).
            if (kDebugMode)
              _section(copy.sectionLabTesting, [
                _nav(
                  context,
                  ref,
                  Icons.animation_rounded,
                  copy.splashPreview,
                  subtitle: copy.splashPreviewHint,
                  route: '/settings/lab/splash-preview',
                ),
              ]),
            _section(copy.sectionPersonalization, [
              _nav(
                context,
                ref,
                Icons.person_rounded,
                copy.myAccount,
                value: copy.personalHub,
                route: '/my-account',
              ),
              _nav(
                context,
                ref,
                Icons.collections_bookmark_rounded,
                copy.libraryHub,
                subtitle: copy.libraryHubHint,
                route: '/library',
              ),
              _nav(
                context,
                ref,
                Icons.bookmark_rounded,
                copy.watchLater,
                value: copy.savedTitles,
                route: '/library?tab=watchlater',
              ),
              _nav(
                context,
                ref,
                Icons.local_fire_department_rounded,
                copy.newAndPopular,
                value: copy.trendingComing,
                route: '/new',
              ),
              _nav(
                context,
                ref,
                Icons.child_care_rounded,
                copy.kids,
                value: copy.familyTitles,
                route: '/kids',
              ),
              _nav(
                context,
                ref,
                Icons.dashboard_customize_rounded,
                copy.customizeHome,
                value: copy.configure,
                route: '/settings/customize-home',
                badge: true,
              ),
            ]),
            _section(copy.sectionExtras, [
              _nav(
                context,
                ref,
                Icons.download_rounded,
                copy.downloads,
                value: copy.downloadsOffline,
                route: '/downloads',
              ),
            ]),
            _section(copy.application, [
              _nav(
                context,
                ref,
                Icons.language_rounded,
                copy.language,
                value: AppLocale.normalize(session.language),
                route: '/settings/language',
              ),
              _nav(
                context,
                ref,
                Icons.notifications_rounded,
                copy.notifications,
                value: session.notificationsEnabled ? copy.enabled : copy.off,
                route: '/settings/notifications',
              ),
              if (ref.watch(featureEnabledProvider('parental_controls')))
                _nav(
                  context,
                  ref,
                  Icons.lock_rounded,
                  copy.parental,
                  value: session.parentalPinEnabled ? copy.pinSet : copy.off,
                  route: '/settings/parental',
                ),
            ]),
            _section(copy.support, [
              _SettingsRow(
                icon: Icons.help_outline_rounded,
                title: copy.helpSupport,
                showChevron: true,
                onTap: () {
                  playUiTap(ref);
                  showSupportHelpSheet(context, copy);
                },
              ),
              _nav(
                context,
                ref,
                Icons.info_outline_rounded,
                copy.about,
                value: 'v${ref.watch(appVersionProvider).valueOrNull ?? ''}',
                route: '/settings/about',
              ),
              if (demo)
                _nav(
                  context,
                  ref,
                  Icons.copyright_rounded,
                  copy.demoCredits,
                  route: demoCreditsRoute,
                ),
            ]),
            const SizedBox(height: 8),
            // Demo: leave the demo and sign in (same place as Sign out).
            if (demo)
              OutlinedButton.icon(
                onPressed: () {
                  playUiTap(ref);
                  exitDemo(ref);
                  context.go('/auth/welcome');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.cyan,
                  side: BorderSide(color: AppColors.cyan),
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.login_rounded),
                label: Text(copy.exitDemoSignIn),
              )
            else
              OutlinedButton.icon(
                onPressed: () async {
                  playUiTap(ref);
                  final ok = await ActionFeedback.confirm(
                    context,
                    title: copy.signOutConfirmTitle,
                    message: copy.signOutConfirmMessage,
                    confirmLabel: copy.signOutShort,
                    cancelLabel: copy.cancel,
                    destructive: true,
                  );
                  if (!ok || !context.mounted) return;
                  await ref.read(sessionProvider.notifier).signOut();
                  if (context.mounted) context.go('/auth/welcome');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.danger),
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.logout),
                label: Text(copy.signOut),
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.cyan,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              fontSize: 12,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.08),
                AppColors.surface.withValues(alpha: 0.94),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: AppColors.cyan.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: Column(children: children),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _nav(
    BuildContext context,
    WidgetRef ref,
    IconData icon,
    String title, {
    String? subtitle,
    String? value,
    required String route,
    bool badge = false,
  }) {
    return _SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      value: value,
      badge: badge,
      showChevron: true,
      onTap: () {
        playUiTap(ref);
        AppLog.tap('settings.nav', data: {'route': route, 'title': title});
        context.push(route);
      },
    );
  }

  Widget _switchRow({
    required IconData icon,
    Color? iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _SettingsRow(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      showChevron: false,
      trailing: Transform.scale(
        scale: 0.88,
        alignment: Alignment.centerRight,
        child: Switch.adaptive(
          value: value,
          activeThumbColor: AppColors.cyan,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// One layout for every settings row: icon · title(+1-line hint) · value/control.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.iconColor,
    this.subtitle,
    this.value,
    this.badge = false,
    this.showChevron = true,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final String? value;
  final bool badge;
  final bool showChevron;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;
    final hasValue = value != null && value!.trim().isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            NeonGlowIcon(icon, size: 24, color: iconColor ?? AppColors.cyan),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.2,
                    ),
                  ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (hasValue) ...[
              const SizedBox(width: 8),
              badge
                  ? TechBadge(value!, compact: true)
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 108),
                      child: Text(
                        value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ] else if (showChevron) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 22,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
