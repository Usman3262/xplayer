import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart' show AppBrand;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_action_feedback.dart';
import 'tv_security_scaffold.dart';

class TvMfaSetupScreen extends ConsumerStatefulWidget {
  const TvMfaSetupScreen({super.key});

  @override
  ConsumerState<TvMfaSetupScreen> createState() => _TvMfaSetupScreenState();
}

class _TvMfaSetupScreenState extends ConsumerState<TvMfaSetupScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _enrolling = false;
  bool _confirming = false;
  bool _disabling = false;
  bool _mfaOn = false;
  String? _secret;
  String? _otpauthUrl;
  List<String>? _recovery;

  AppCopy get _copy =>
      AppCopy.ofLanguage(ref.read(tvLanguageProvider));

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final me = await ref.read(tvAuthRepositoryProvider).me();
      if (mounted) setState(() => _mfaOn = me.mfaEnabled);
    } catch (_) {}
  }

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _busy => _enrolling || _confirming || _disabling;

  Future<void> _enroll() async {
    final copy = _copy;
    setState(() => _enrolling = true);
    try {
      final e = await ref.read(tvAuthRepositoryProvider).enrollMfa();
      setState(() {
        _secret = e.secret;
        _otpauthUrl = e.otpauthUrl;
      });
      if (!mounted) return;
      await TvActionFeedback.success(
        context,
        title: copy.success,
        message: copy.mfaEnrollSnack,
      );
    } catch (e) {
      if (!mounted) return;
      await TvActionFeedback.error(
        context,
        title: copy.enrollmentFailed,
        message: TvActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  Future<void> _confirm() async {
    final copy = _copy;
    if (_code.text.trim().length < 6) {
      await TvActionFeedback.error(
        context,
        title: copy.codeRequired,
        message: copy.enterSixDigitCode,
      );
      return;
    }
    setState(() => _confirming = true);
    try {
      final r = await ref
          .read(tvAuthRepositoryProvider)
          .confirmMfa(code: _code.text.trim());
      setState(() {
        _mfaOn = true;
        _recovery = r.recoveryCodes;
        _secret = null;
        _otpauthUrl = null;
        _code.clear();
      });
      if (!mounted) return;
      await TvActionFeedback.success(
        context,
        title: copy.mfaEnabledLabel,
        message:
            'Save the recovery codes shown on this screen.',
      );
    } catch (e) {
      if (!mounted) return;
      await TvActionFeedback.error(
        context,
        title: copy.failed,
        message: TvActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _disable() async {
    final copy = _copy;
    if (_password.text.isEmpty) {
      await TvActionFeedback.error(
        context,
        title: copy.mfaPasswordRequired,
        message: copy.mfaDisablePasswordHint,
      );
      return;
    }
    final ok = await TvActionFeedback.confirm(
      context,
      title: copy.mfaDisableTitle,
      message: copy.mfaDisableBody,
      confirmLabel: copy.disableMfa,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _disabling = true);
    try {
      await ref
          .read(tvAuthRepositoryProvider)
          .disableMfa(password: _password.text);
      _password.clear();
      setState(() {
        _mfaOn = false;
        _recovery = null;
      });
      if (!mounted) return;
      await TvActionFeedback.success(
        context,
        title: copy.mfaStatusOff,
        message: copy.mfaDisabledDone,
      );
    } catch (e) {
      if (!mounted) return;
      await TvActionFeedback.error(
        context,
        title: copy.failed,
        message: TvActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _disabling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final qr = (_otpauthUrl != null && _otpauthUrl!.isNotEmpty)
        ? _otpauthUrl!
        : (_secret == null
            ? null
            : 'otpauth://totp/${AppBrand.name}?secret=$_secret&issuer=${AppBrand.name}');

    return TvSecurityScaffold(
      title: copy.mfaTitle,
      subtitle: _mfaOn ? copy.mfaStatusOn : copy.mfaStatusOff,
      helpBody: '${copy.mfaHelpBody}\n\n${copy.mfaWrongCodeHint}',
      child: ListView(
        children: [
          if (!_mfaOn) ...[
            FocusTile(
              borderRadius: 12,
              onTap: _busy ? null : _enroll,
              child: PrimaryButton(
                label: _enrolling ? copy.loading : copy.startMfaEnrollment,
                icon: Icons.qr_code_2_rounded,
                loading: _enrolling,
                onPressed: _busy ? null : _enroll,
              ),
            ),
            if (qr != null) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    color: Colors.white,
                    child: QrImageView(data: qr, size: 160),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppFieldLabel(copy.orEnterSecretManually),
                        const SizedBox(height: 6),
                        SelectableText(
                          _secret ?? '',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _secret == null
                              ? null
                              : () => Clipboard.setData(
                                    ClipboardData(text: _secret!),
                                  ),
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: Text(copy.copySecret),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _code,
                label: copy.authenticatorCode,
                prefix: Icons.security_rounded,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              FocusTile(
                borderRadius: 12,
                onTap: _busy ? null : _confirm,
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
              obscure: true,
              prefix: Icons.lock_outline_rounded,
            ),
            const SizedBox(height: 12),
            FocusTile(
              borderRadius: 12,
              onTap: _busy ? null : _disable,
              child: PrimaryButton(
                label: _disabling ? copy.updating : copy.disableMfa,
                icon: Icons.link_off_rounded,
                color: AppColors.danger,
                loading: _disabling,
                onPressed: _busy ? null : _disable,
              ),
            ),
          ],
          if (_recovery != null) ...[
            const SizedBox(height: 16),
            Text(
              copy.recoveryCodesSaveNow,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            for (final c in _recovery!)
              SelectableText(c, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ],
      ),
    );
  }
}
