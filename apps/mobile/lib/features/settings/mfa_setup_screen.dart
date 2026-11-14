import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart' show AppBrand;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/session_controller.dart';
import '../../widgets/action_feedback.dart';
import 'security_detail_scaffold.dart';

class MfaSetupScreen extends ConsumerStatefulWidget {
  const MfaSetupScreen({super.key});

  @override
  ConsumerState<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

class _MfaSetupScreenState extends ConsumerState<MfaSetupScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _enrolling = false;
  bool _confirming = false;
  bool _disabling = false;
  bool _obscurePassword = true;
  String? _secret;
  String? _otpauthUrl;
  List<String>? _recoveryCodes;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _busy => _enrolling || _confirming || _disabling;

  AppCopy get _copy =>
      AppCopy.ofLanguage(ref.read(sessionProvider).language);

  Future<void> _enroll() async {
    setState(() {
      _enrolling = true;
      _recoveryCodes = null;
    });
    try {
      final enroll = await ref.read(sessionProvider.notifier).enrollMfa();
      setState(() {
        _secret = enroll.secret;
        _otpauthUrl = enroll.otpauthUrl;
      });
      if (!mounted) return;
      ActionFeedback.snack(
        context,
        message: _copy.mfaEnrollSnack,
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: _copy.enrollmentFailed,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  Future<void> _confirm() async {
    final copy = _copy;
    if (_code.text.trim().length < 6) {
      await ActionFeedback.error(
        context,
        title: copy.codeRequired,
        message: copy.enterSixDigitCode,
      );
      return;
    }
    setState(() => _confirming = true);
    try {
      final codes =
          await ref.read(sessionProvider.notifier).confirmMfa(_code.text.trim());
      setState(() {
        _recoveryCodes = codes;
        _secret = null;
        _otpauthUrl = null;
        _code.clear();
      });
      if (!mounted) return;
      await ActionFeedback.success(
        context,
        title: copy.mfaEnabledLabel,
        message:
            'Save the recovery codes shown on this screen. They are displayed only once.',
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.failed,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _disable() async {
    final copy = _copy;
    if (_password.text.isEmpty) {
      await ActionFeedback.error(
        context,
        title: copy.mfaPasswordRequired,
        message: copy.mfaDisablePasswordHint,
      );
      return;
    }
    final ok = await ActionFeedback.confirm(
      context,
      title: copy.mfaDisableTitle,
      message: copy.mfaDisableBody,
      confirmLabel: copy.off,
      cancelLabel: copy.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _disabling = true);
    try {
      await ref.read(sessionProvider.notifier).disableMfa(_password.text);
      _password.clear();
      setState(() {
        _recoveryCodes = null;
        _secret = null;
        _otpauthUrl = null;
      });
      if (!mounted) return;
      await ActionFeedback.success(
        context,
        title: copy.mfaStatusOff,
        message: copy.mfaDisabledDone,
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.failed,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _disabling = false);
    }
  }

  String get _qrData {
    if (_otpauthUrl != null && _otpauthUrl!.isNotEmpty) return _otpauthUrl!;
    return 'otpauth://totp/${AppBrand.name}?secret=$_secret&issuer=${AppBrand.name}';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final enabled = session.user?.mfaEnabled == true;
    final copy = AppCopy.ofLanguage(session.language);
    final helpBody = '${copy.mfaHelpBody}\n\n${copy.mfaWrongCodeHint}';

    return SecurityDetailScaffold(
      title: copy.mfaTitle,
      subtitle: copy.mfaProtectHint,
      badge: copy.mfaBadge,
      helpTitle: copy.mfaHelpTitle,
      helpBody: helpBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            enabled ? copy.mfaStatusOn : copy.mfaStatusOff,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: enabled ? AppColors.cyan : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          if (!enabled) ...[
            NeonGlowBorder(
              child: PrimaryButton(
                label: _enrolling ? copy.loading : copy.startMfaEnrollment,
                icon: Icons.qr_code_2_rounded,
                loading: _enrolling,
                onPressed: _busy ? null : _enroll,
              ),
            ),
            if (_secret != null && _secret!.isNotEmpty) ...[
              const SizedBox(height: 20),
              AppFieldLabel(copy.scanThisQr),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.4),
                    ),
                  ),
                  child: QrImageView(
                    data: _qrData,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AppFieldLabel(copy.orEnterSecretManually),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C101A),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: SelectableText(
                  _secret!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _secret!));
                    ActionFeedback.snack(
                      context,
                      message: copy.secretCopied,
                      title: copy.success,
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(copy.copySecret),
                ),
              ),
              const SizedBox(height: 8),
              AppTextField(
                controller: _code,
                label: copy.authenticatorCode,
                prefix: Icons.security_rounded,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              NeonGlowBorder(
                child: PrimaryButton(
                  label: _confirming ? copy.updating : copy.confirmMfa,
                  icon: Icons.verified_user_rounded,
                  loading: _confirming,
                  onPressed: _busy ? null : _confirm,
                ),
              ),
            ],
          ] else ...[
            AppTextField(
              controller: _password,
              label: copy.passwordToDisableMfa,
              obscure: _obscurePassword,
              prefix: Icons.lock_outline_rounded,
              suffix: IconButton(
                onPressed: _busy
                    ? null
                    : () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            NeonGlowBorder(
              color: AppColors.danger,
              child: PrimaryButton(
                label: _disabling ? copy.updating : copy.disableMfa,
                icon: Icons.link_off_rounded,
                color: AppColors.danger,
                loading: _disabling,
                onPressed: _busy ? null : _disable,
              ),
            ),
          ],
          if (_recoveryCodes != null) ...[
            const SizedBox(height: 20),
            Text(
              copy.recoveryCodesSaveNow,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0C101A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final c in _recoveryCodes!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SelectableText(
                        c,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: _recoveryCodes!.join('\n')),
                );
                ActionFeedback.snack(
                  context,
                  message: copy.recoveryCodesCopied,
                  title: copy.success,
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text(copy.copyAllCodes),
            ),
          ],
        ],
      ),
    );
  }
}
