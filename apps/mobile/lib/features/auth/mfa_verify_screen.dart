import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_controller.dart';
import '../../widgets/auth_scaffold.dart';

class MfaVerifyScreen extends ConsumerStatefulWidget {
  const MfaVerifyScreen({super.key, required this.challengeId});

  final String challengeId;

  @override
  ConsumerState<MfaVerifyScreen> createState() => _MfaVerifyScreenState();
}

class _MfaVerifyScreenState extends ConsumerState<MfaVerifyScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).verifyMfa(
            mfaChallengeId: widget.challengeId,
            code: _code.text,
          );
      if (!mounted) return;
      context.go('/profiles');
    } on LoginApprovalRequiredException catch (e) {
      if (!mounted) return;
      final q = StringBuffer(
        'challenge=${Uri.encodeComponent(e.challengeId)}',
      );
      if (e.expiresAt != null && e.expiresAt!.isNotEmpty) {
        q.write('&expires=${Uri.encodeComponent(e.expiresAt!)}');
      }
      context.go('/auth/login-approval?$q');
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(sessionProvider).language);
    return AuthScaffold(
      title: copy.mfaCodeTitle,
      subtitle: copy.mfaCodeHint,
      badge: 'MFA',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthField(
            controller: _code,
            label: copy.mfaCodeLabel,
            keyboardType: TextInputType.number,
            prefix: Icons.security_rounded,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 18),
          NeonGlowBorder(
            child: PrimaryButton(
              label: copy.mfaVerifyContinue,
              icon: Icons.verified_user_rounded,
              loading: _loading,
              onPressed: _loading || widget.challengeId.isEmpty ? null : _submit,
            ),
          ),
          TextButton(
            onPressed: () => context.push('/auth/recovery'),
            child: Text(copy.mfaUseRecoveryCode),
          ),
        ],
      ),
    );
  }
}
