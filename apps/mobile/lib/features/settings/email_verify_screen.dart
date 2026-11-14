import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_controller.dart';
import '../../widgets/action_feedback.dart';
import 'security_detail_scaffold.dart';

class EmailVerifyScreen extends ConsumerStatefulWidget {
  const EmailVerifyScreen({super.key});

  @override
  ConsumerState<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends ConsumerState<EmailVerifyScreen> {
  final _login = TextEditingController();
  final _code = TextEditingController();
  bool _resending = false;
  bool _verifying = false;

  @override
  void dispose() {
    _login.dispose();
    _code.dispose();
    super.dispose();
  }

  AppCopy get _copy =>
      AppCopy.ofLanguage(ref.read(sessionProvider).language);

  String _loginValue() {
    final typed = _login.text.trim();
    if (typed.isNotEmpty) return typed;
    return ref.read(sessionProvider).user?.email ?? '';
  }

  Future<void> _resend() async {
    final copy = _copy;
    final login = _loginValue();
    if (login.isEmpty) {
      await ActionFeedback.error(
        context,
        title: copy.missingLogin,
        message: copy.enterLoginFirst,
      );
      return;
    }
    setState(() => _resending = true);
    try {
      final msg =
          await ref.read(sessionProvider.notifier).resendEmailVerification(login);
      if (!mounted) return;
      await ActionFeedback.success(
        context,
        title: copy.codeSent,
        message: msg,
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.couldNotResend,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify() async {
    final copy = _copy;
    final login = _loginValue();
    if (login.isEmpty || _code.text.trim().isEmpty) {
      await ActionFeedback.error(
        context,
        title: copy.missingFields,
        message:
            '${copy.emailOrUsername} + ${copy.verificationCode}',
      );
      return;
    }
    setState(() => _verifying = true);
    try {
      await ref.read(sessionProvider.notifier).verifyEmail(
            login: login,
            code: _code.text.trim(),
          );
      if (!mounted) return;
      await ActionFeedback.success(
        context,
        title: copy.emailVerifiedShort,
        message: copy.emailConfirmedMsg,
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.verificationFailed,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    final copy = AppCopy.ofLanguage(session.language);
    final busy = _resending || _verifying;
    return SecurityDetailScaffold(
      title: copy.emailVerification,
      subtitle: copy.emailVerifyHint,
      badge: copy.emailBadge,
      helpTitle: copy.emailVerifyHelpTitle,
      helpBody: copy.emailVerifyHelpBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            user?.emailVerified == true
                ? copy.emailStatusVerified(user?.email ?? '')
                : copy.emailStatusUnverified,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: user?.emailVerified == true
                  ? AppColors.cyan
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _login,
            label: copy.emailOrUsername,
            hint: user?.email,
            prefix: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: _resending ? copy.loading : copy.resendCode,
            icon: Icons.send_rounded,
            filled: false,
            loading: _resending,
            onPressed: busy ? null : _resend,
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _code,
            label: copy.verificationCode,
            prefix: Icons.pin_rounded,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          NeonGlowBorder(
            child: PrimaryButton(
              label: _verifying ? copy.loading : copy.verifyEmail,
              icon: Icons.verified_rounded,
              loading: _verifying,
              onPressed: busy ? null : _verify,
            ),
          ),
        ],
      ),
    );
  }
}
