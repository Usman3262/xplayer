import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_controller.dart';
import '../../widgets/auth_scaffold.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.initialToken});

  final String? initialToken;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  late final TextEditingController _token;
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(text: widget.initialToken ?? '');
  }

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).resetPassword(
            token: _token.text,
            newPassword: _password.text,
          );
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Set new password',
      subtitle: 'Paste the reset token from your email, then choose a new password.',
      badge: 'PASSWORD RESET',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_done) ...[
            const Text(
              'Password updated. Sign in with your new password.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Back to Sign In',
              onPressed: () => context.go('/auth/login'),
            ),
          ] else ...[
            AuthField(
              controller: _token,
              label: 'Reset token',
              prefix: Icons.token_rounded,
            ),
            const SizedBox(height: 12),
            AuthField(
              controller: _password,
              label: 'New password',
              obscure: true,
              prefix: Icons.lock_outline_rounded,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 18),
            NeonGlowBorder(
              child: PrimaryButton(
                label: 'Update password',
                icon: Icons.check_rounded,
                loading: _loading,
                onPressed: _loading ? null : _submit,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
