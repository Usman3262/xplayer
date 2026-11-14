import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_controller.dart';
import '../../widgets/auth_scaffold.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _sent = false;
  bool _loading = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final msg =
          await ref.read(sessionProvider.notifier).forgotPassword(_email.text);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _message = msg;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Recover access',
      subtitle: 'We will email reset instructions if the account exists.',
      badge: 'ACCOUNT RECOVERY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_sent) ...[
            AuthField(
              controller: _email,
              label: 'Email or username',
              keyboardType: TextInputType.emailAddress,
              prefix: Icons.mail_outline_rounded,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 18),
            NeonGlowBorder(
              child: PrimaryButton(
                label: 'Send reset instructions',
                icon: Icons.send_rounded,
                loading: _loading,
                onPressed: _loading ? null : _submit,
              ),
            ),
            TextButton(
              onPressed: () => context.push('/auth/reset'),
              child: const Text('Already have a reset token?'),
            ),
            TextButton(
              onPressed: () => context.push('/auth/recovery'),
              child: const Text('MFA recovery login'),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.cyan.withValues(alpha: 0.45),
                ),
                color: AppColors.cyan.withValues(alpha: 0.08),
              ),
              child: Text(
                _message ??
                    'If the account exists, reset instructions were sent.',
                style: const TextStyle(height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Enter reset token',
              onPressed: () => context.push('/auth/reset'),
            ),
            const SizedBox(height: 10),
            PrimaryButton(
              label: 'Back to Sign In',
              onPressed: () => context.go('/auth/login'),
            ),
          ],
        ],
      ),
    );
  }
}
