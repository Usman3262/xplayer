import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/account.dart';
import '../../core/session_controller.dart';
import '../../widgets/auth_scaffold.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(AppCopy copy) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final needsConfirm = await AccountService.signUp(
        _email.text,
        _password.text,
        displayName: _name.text,
      );
      if (!mounted) return;
      if (needsConfirm) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(copy.accountCheckEmail), duration: const Duration(seconds: 6)),
        );
        context.go('/auth/login');
      } else {
        context.go('/home');
      }
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.error.text(copy));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(sessionProvider.select((s) => s.language)));
    return AuthScaffold(
      title: copy.registerTitle,
      subtitle: copy.registerSubtitle,
      badge: copy.newMemberBadge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthField(
            controller: _name,
            label: copy.fieldFullName,
            prefix: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 14),
          AuthField(
            controller: _email,
            label: copy.fieldEmail,
            keyboardType: TextInputType.emailAddress,
            prefix: Icons.mail_outline_rounded,
          ),
          const SizedBox(height: 14),
          AuthField(
            controller: _password,
            label: copy.fieldPassword,
            obscure: true,
            prefix: Icons.lock_outline_rounded,
          ),
          const SizedBox(height: 18),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: AppColors.danger)),
            const SizedBox(height: 10),
          ],
          NeonGlowBorder(
            color: AppColors.magenta,
            enabled: !_loading,
            child: PrimaryButton(
              key: const Key('register-submit'),
              label: copy.accountCreate,
              color: AppColors.magenta,
              icon: Icons.rocket_launch_rounded,
              loading: _loading,
              onPressed: _loading ? null : () => _submit(copy),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/auth/login'),
            child: Text(
              copy.accountSignInLink,
              style: TextStyle(
                color: AppColors.cyan,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
