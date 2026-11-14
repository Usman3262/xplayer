import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_action_feedback.dart';
import 'tv_security_scaffold.dart';

class TvSessionsScreen extends ConsumerStatefulWidget {
  const TvSessionsScreen({super.key});

  @override
  ConsumerState<TvSessionsScreen> createState() => _TvSessionsScreenState();
}

class _TvSessionsScreenState extends ConsumerState<TvSessionsScreen> {
  bool _loading = true;
  String? _error;
  List<SessionRecordDto> _sessions = const [];
  String? _currentId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(tvAuthRepositoryProvider);
      final list = await auth.listSessions();
      final tokens = await auth.tokenStore.read();
      if (!mounted) return;
      setState(() {
        _sessions =
            list.where((s) => s.status.toUpperCase() == 'ACTIVE').toList();
        _currentId = tokens?.sessionId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    return TvSecurityScaffold(
      title: copy.sessionsTitle,
      subtitle: copy.sessionsSubtitle,
      helpBody: copy.sessionsHelpBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                copy.activeSessionsCount(_sessions.length),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (_loading)
                AppLoader.inline(size: 18)
              else
                FocusTile(
                  borderRadius: 10,
                  onTap: _load,
                  child: Icon(Icons.refresh_rounded,
                      color: AppColors.cyan),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: _sessions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final s = _sessions[i];
                final current = s.id == _currentId;
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C101A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.status,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              copy.lastUsed(s.lastUsedAt ?? 'Unknown'),
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            if (current)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: TechBadge(
                                  copy.currentSession,
                                  compact: true,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!current)
                        FocusTile(
                          borderRadius: 10,
                          onTap: () async {
                            final ok = await TvActionFeedback.confirm(
                              context,
                              title: copy.revokeThisSession,
                              message: copy.revokeSessionMessage,
                              confirmLabel: copy.revoke,
                              destructive: true,
                            );
                            if (!ok || !context.mounted) return;
                            try {
                              await ref
                                  .read(tvAuthRepositoryProvider)
                                  .revokeSession(s.id);
                              await _load();
                              if (!context.mounted) return;
                              TvActionFeedback.toast(
                                context,
                                tone: AppAlertTone.success,
                                title: copy.sessionRevoked,
                                message: copy.deviceSignedOut,
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              await TvActionFeedback.error(
                                context,
                                title: copy.revokeFailed,
                                message: TvActionFeedback.clean(e),
                              );
                            }
                          },
                          child: Icon(
                            Icons.block_rounded,
                            color: AppColors.danger,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          FocusTile(
            borderRadius: 12,
            onTap: () async {
              final ok = await TvActionFeedback.confirm(
                context,
                title: copy.signOutEverywhere,
                message: copy.signOutAllMessage,
                confirmLabel: copy.signOutAllLabel,
                destructive: true,
              );
              if (ok != true) return;
              try {
                await ref.read(tvAuthRepositoryProvider).logoutAll();
                await ref.read(tvSessionProvider.notifier).logout();
                if (!context.mounted) return;
                TvActionFeedback.toast(
                  context,
                  tone: AppAlertTone.success,
                  title: copy.signedOutTitle,
                  message: copy.allSessionsRevoked,
                );
                if (context.mounted) context.go('/login');
              } catch (e) {
                if (!context.mounted) return;
                await TvActionFeedback.error(
                  context,
                  title: copy.signOutFailed,
                  message: TvActionFeedback.clean(e),
                );
              }
            },
            child: PrimaryButton(
              label: copy.signOutAllDevices,
              icon: Icons.logout_rounded,
              color: AppColors.danger,
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}
