import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_controller.dart';
import '../../widgets/auth_scaffold.dart';

class RecoveryLoginScreen extends ConsumerStatefulWidget {
  const RecoveryLoginScreen({super.key});

  @override
  ConsumerState<RecoveryLoginScreen> createState() =>
      _RecoveryLoginScreenState();
}

class _RecoveryLoginScreenState extends ConsumerState<RecoveryLoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).recoveryLogin(
            login: _login.text,
            password: _password.text,
            recoveryCode: _code.text,
          );
      if (!mounted) return;
      context.go('/profiles');
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
      title: copy.recoveryLoginTitle,
      subtitle: copy.recoveryLoginHint,
      badge: 'ACCOUNT RECOVERY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthField(
            controller: _login,
            label: copy.emailOrUsernameLabel,
            prefix: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 12),
          AuthField(
            controller: _password,
            label: copy.password,
            obscure: true,
            prefix: Icons.lock_outline_rounded,
          ),
          const SizedBox(height: 12),
          AuthField(
            controller: _code,
            label: copy.recoveryCodeLabel,
            prefix: Icons.key_rounded,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 18),
          NeonGlowBorder(
            child: PrimaryButton(
              label: copy.recoverySignIn,
              icon: Icons.login_rounded,
              loading: _loading,
              onPressed: _loading ? null : _submit,
            ),
          ),
        ],
      ),
    );
  }
}
