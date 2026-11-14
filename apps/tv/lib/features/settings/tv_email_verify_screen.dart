import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_action_feedback.dart';
import 'tv_security_scaffold.dart';

class TvEmailVerifyScreen extends ConsumerStatefulWidget {
  const TvEmailVerifyScreen({super.key});

  @override
  ConsumerState<TvEmailVerifyScreen> createState() =>
      _TvEmailVerifyScreenState();
}

class _TvEmailVerifyScreenState extends ConsumerState<TvEmailVerifyScreen> {
  final _login = TextEditingController();
  final _code = TextEditingController();
  bool _resending = false;
  bool _verifying = false;
  bool? _verified;
  String? _email;

  AppCopy get _copy =>
      AppCopy.ofLanguage(ref.read(tvLanguageProvider));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await ref.read(tvAuthRepositoryProvider).me();
      if (!mounted) return;
      setState(() {
        _verified = me.emailVerified;
        _email = me.email;
        if ((me.email ?? '').isNotEmpty) {
          _login.text = me.email!;
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _login.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _busy => _resending || _verifying;

  Future<void> _resend() async {
    final copy = _copy;
    final login = _login.text.trim();
    if (login.isEmpty) {
      await TvActionFeedback.error(
        context,
        title: copy.missingLogin,
        message: copy.enterLoginFirst,
      );
      return;
    }
    setState(() => _resending = true);
    try {
      final msg = await ref
          .read(tvAuthRepositoryProvider)
          .resendEmailVerification(login: login);
      if (!mounted) return;
      await TvActionFeedback.success(
        context,
        title: copy.codeSent,
        message: msg,
      );
    } catch (e) {
      if (!mounted) return;
      await TvActionFeedback.error(
        context,
        title: copy.couldNotResend,
        message: TvActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify() async {
    final copy = _copy;
    final login = _login.text.trim();
    if (login.isEmpty || _code.text.trim().isEmpty) {
      await TvActionFeedback.error(
        context,
        title: copy.missingFields,
        message: '${copy.emailOrUsername} + ${copy.verificationCode}',
      );
      return;
    }
    setState(() => _verifying = true);
    try {
      await ref.read(tvAuthRepositoryProvider).verifyEmail(
            login: login,
            code: _code.text.trim(),
          );
      setState(() {
        _verified = true;
        _email = login;
      });
      if (!mounted) return;
      await TvActionFeedback.success(
        context,
        title: copy.emailVerifiedShort,
        message: copy.emailConfirmedMsg,
      );
    } catch (e) {
      if (!mounted) return;
      await TvActionFeedback.error(
        context,
        title: copy.verificationFailed,
        message: TvActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final subtitle = _verified == null
        ? copy.emailVerifyHint
        : (_verified!
            ? copy.emailStatusVerified(_email ?? '')
            : copy.emailStatusUnverified);
    return TvSecurityScaffold(
      title: copy.emailVerification,
      subtitle: subtitle,
      helpBody: copy.emailVerifyHelpBody,
      child: ListView(
        children: [
          AppTextField(
            controller: _login,
            label: copy.emailOrUsername,
            prefix: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          FocusTile(
            borderRadius: 12,
            onTap: _busy ? null : _resend,
            child: PrimaryButton(
              label: _resending ? copy.loading : copy.resendCode,
              icon: Icons.send_rounded,
              filled: false,
              loading: _resending,
              onPressed: _busy ? null : _resend,
            ),
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _code,
            label: copy.verificationCode,
            prefix: Icons.pin_rounded,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 14),
          FocusTile(
            borderRadius: 12,
            onTap: _busy ? null : _verify,
            child: PrimaryButton(
              label: _verifying ? copy.loading : copy.verifyEmail,
              icon: Icons.verified_rounded,
              loading: _verifying,
              onPressed: _busy ? null : _verify,
            ),
          ),
        ],
      ),
    );
  }
}
