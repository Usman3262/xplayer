import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart' show AppBrand;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).register(
            name: _name.text,
            email: _email.text,
            password: _password.text,
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
    return AuthScaffold(
      title: 'Join ${AppBrand.name}',
      subtitle: 'Create your profile. Fields are local until backend is live.',
      badge: 'NEW MEMBER',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthField(
            controller: _name,
            label: 'Full name',
            prefix: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 14),
          AuthField(
            controller: _email,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
            prefix: Icons.mail_outline_rounded,
          ),
          const SizedBox(height: 14),
          AuthField(
            controller: _password,
            label: 'Password',
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
              label: 'Create Account',
              color: AppColors.magenta,
              icon: Icons.rocket_launch_rounded,
              loading: _loading,
              onPressed: _loading ? null : _submit,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/auth/login'),
            child: Text(
              'Already have an account? Sign in',
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
