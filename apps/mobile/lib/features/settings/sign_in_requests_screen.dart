import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_controller.dart';
import '../../widgets/action_feedback.dart';
import 'security_detail_scaffold.dart';

/// Settings → Sign-in requests (6 Nov). Every signed-in device of the account
/// can see and answer new sign-in requests here — the way out when the
/// pop-up or the push notification did not arrive.
class SignInRequestsScreen extends ConsumerStatefulWidget {
  const SignInRequestsScreen({super.key});

  @override
  ConsumerState<SignInRequestsScreen> createState() =>
      _SignInRequestsScreenState();
}

class _SignInRequestsScreenState extends ConsumerState<SignInRequestsScreen> {
  bool _loading = false;
  String? _busyId;
  List<LoginChallengeDto> _pending = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  AppCopy get _copy => AppCopy.ofLanguage(ref.read(sessionProvider).language);

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final list = await ref
          .read(sessionProvider.notifier)
          .pendingLoginChallenges();
      if (!mounted) return;
      setState(() => _pending = list.where((c) => c.isPending).toList());
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: _copy.signInRequestsTitle,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _answer(LoginChallengeDto c, {required bool allow}) async {
    final copy = _copy;
    setState(() => _busyId = c.challengeId);
    try {
      final session = ref.read(sessionProvider.notifier);
      if (allow) {
        await session.allowLoginChallenge(c.challengeId);
      } else {
        await session.denyLoginChallenge(c.challengeId);
      }
      if (!mounted) return;
      ActionFeedback.snack(
        context,
        title: allow ? copy.signInAllowed : copy.signInDenied,
        message: c.deviceName ?? c.platform ?? '',
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.signInRequestsTitle,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(sessionProvider).language);
    return SecurityDetailScaffold(
      title: copy.signInRequestsTitle,
      subtitle: copy.signInRequestsSubtitle,
      helpTitle: copy.signInRequestsHelpTitle,
      helpBody: copy.signInRequestsHelpBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                copy.pendingSignInRequests(_pending.length),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (_loading)
                AppLoader.inline(size: 18)
              else
                IconButton(
                  onPressed: _refresh,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: AppColors.cyan,
                  ),
                ),
            ],
          ),
          if (_pending.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                copy.noSignInRequests,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final c in _pending)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0C101A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          (c.platform ?? '').contains('TV') ||
                                  c.platform == 'WEBOS' ||
                                  c.platform == 'TIZEN'
                              ? Icons.tv_rounded
                              : Icons.devices_rounded,
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
                              c.deviceName ?? c.platform ?? 'Device',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (c.platform != null)
                              Text(
                                c.platform!,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_busyId == c.challengeId)
                    Center(child: AppLoader.button(size: 28))
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busyId != null
                                ? null
                                : () => _answer(c, allow: false),
                            child: Text(
                              copy.denySignIn,
                              style: TextStyle(
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: _busyId != null
                                ? null
                                : () => _answer(c, allow: true),
                            child: Text(copy.allowSignIn),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
