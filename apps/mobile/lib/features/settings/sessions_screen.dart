import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_controller.dart';
import '../../widgets/action_feedback.dart';
import 'security_detail_scaffold.dart';

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  bool _loading = false;
  bool _signingOutAll = false;
  String? _revokingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(silent: true));
  }

  AppCopy get _copy =>
      AppCopy.ofLanguage(ref.read(sessionProvider).language);

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    setState(() => _loading = true);
    final copy = _copy;
    try {
      await ref.read(sessionProvider.notifier).refreshDevicesAndSessions();
      if (!mounted || silent) return;
      ActionFeedback.snack(
        context,
        title: copy.sessionsTitle,
        message: copy.sessionsRefreshed,
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.couldNotLoadSessions,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(String id) async {
    final copy = _copy;
    final ok = await ActionFeedback.confirm(
      context,
      title: copy.revokeThisSession,
      message: copy.revokeSessionMessage,
      confirmLabel: copy.revoke,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _revokingId = id);
    try {
      await ref.read(sessionProvider.notifier).revokeSession(id);
      if (!mounted) return;
      ActionFeedback.snack(
        context,
        title: copy.sessionRevoked,
        message: copy.deviceSignedOut,
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.revokeFailed,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _revokingId = null);
    }
  }

  Future<void> _signOutAll() async {
    final copy = _copy;
    final ok = await ActionFeedback.confirm(
      context,
      title: copy.signOutEverywhere,
      message: copy.signOutAllMessage,
      confirmLabel: copy.signOutAllLabel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _signingOutAll = true);
    try {
      await ref.read(sessionProvider.notifier).signOutAll();
      if (!mounted) return;
      ActionFeedback.snack(
        context,
        title: copy.signedOutTitle,
        message: copy.allSessionsRevoked,
      );
      if (mounted) context.go('/auth/welcome');
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.signOutFailed,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _signingOutAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final copy = AppCopy.ofLanguage(session.language);
    final sessions = session.sessions
        .where((s) => s.status.toUpperCase() == 'ACTIVE')
        .toList();

    return SecurityDetailScaffold(
      title: copy.sessionsTitle,
      subtitle: copy.sessionsSubtitle,
      badge: copy.sessionsBadge,
      helpTitle: copy.aboutSessions,
      helpBody: copy.sessionsHelpBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                copy.activeSessionsCount(sessions.length),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (_loading)
                AppLoader.inline(size: 18)
              else
                IconButton(
                  onPressed: () => _refresh(),
                  icon: Icon(Icons.refresh_rounded,
                      color: AppColors.cyan),
                ),
            ],
          ),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                copy.noActiveSessions,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final s in sessions)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0C101A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.devices_rounded,
                      color: AppColors.cyan,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.status,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          copy.lastUsed(s.lastUsed),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if (s.isCurrent)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: TechBadge(copy.currentSession, compact: true),
                          ),
                      ],
                    ),
                  ),
                  if (!s.isCurrent)
                    _revokingId == s.id
                        ? SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(child: AppLoader.button(size: 28)),
                          )
                        : IconButton(
                            onPressed: _signingOutAll
                                ? null
                                : () => _revoke(s.id),
                            icon: Icon(
                              Icons.block_rounded,
                              color: AppColors.danger,
                            ),
                          ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          NeonGlowBorder(
            color: AppColors.danger,
            child: PrimaryButton(
              label: _signingOutAll ? copy.signingOut : copy.signOutAllDevices,
              icon: Icons.logout_rounded,
              color: AppColors.danger,
              loading: _signingOutAll,
              onPressed: (_loading || _signingOutAll || _revokingId != null)
                  ? null
                  : _signOutAll,
            ),
          ),
        ],
      ),
    );
  }
}
