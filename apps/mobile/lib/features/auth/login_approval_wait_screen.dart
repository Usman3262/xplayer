import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_controller.dart';
import '../../widgets/auth_scaffold.dart';

/// Wait screen while a live primary phone Allow/Deny is pending.
/// Offers lost-primary recovery when Usman flags / poll fields allow it.
class LoginApprovalWaitScreen extends ConsumerStatefulWidget {
  const LoginApprovalWaitScreen({
    super.key,
    required this.challengeId,
    this.expiresAt,
    this.loginHint,
  });

  final String challengeId;
  final String? expiresAt;
  final String? loginHint;

  @override
  ConsumerState<LoginApprovalWaitScreen> createState() =>
      _LoginApprovalWaitScreenState();
}

class _LoginApprovalWaitScreenState
    extends ConsumerState<LoginApprovalWaitScreen> {
  bool _loading = true;
  String? _error;
  bool _showRecovery = false;
  bool _recoveryAvailable = false;
  List<String> _recoveryMethods = const [];

  final _userCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  String? _recoveryId;
  String _method = 'totp';
  bool _busy = false;
  bool _deviceLimit = false;

  @override
  void initState() {
    super.initState();
    final hint = widget.loginHint?.trim();
    if (hint != null && hint.isNotEmpty) _userCtrl.text = hint;
    WidgetsBinding.instance.addPostFrameCallback((_) => _wait());
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _wait() async {
    setState(() {
      _loading = true;
      _error = null;
      _showRecovery = false;
    });
    try {
      await ref.read(sessionProvider.notifier).completeLoginApproval(
            widget.challengeId,
            onStatus: (status) {
              if (!mounted) return;
              final offer = status.canOfferRecovery;
              if (offer != _recoveryAvailable ||
                  status.recoveryMethods.join() != _recoveryMethods.join()) {
                setState(() {
                  _recoveryAvailable = offer;
                  _recoveryMethods = status.recoveryMethods;
                  if (_recoveryMethods.isNotEmpty) {
                    _method = _recoveryMethods.first;
                  }
                });
              }
            },
          );
      if (!mounted) return;
      context.go('/profiles');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _startRecovery() async {
    final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
    final user = _userCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (user.isEmpty || password.isEmpty) {
      setState(() => _error = copy.primaryRecoveryBody);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final started = await ref.read(sessionProvider.notifier).startPrimaryRecovery(
            challengeId: widget.challengeId,
            usernameOrEmail: user,
            password: password,
          );
      if (!mounted) return;
      setState(() {
        _recoveryId = started.recoveryId;
        _recoveryMethods =
            started.methods.isNotEmpty ? started.methods : _recoveryMethods;
        if (_recoveryMethods.isNotEmpty) _method = _recoveryMethods.first;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _busy = false;
        _error = msg.contains('PRIMARY_UNREACHABLE') ||
                msg.toLowerCase().contains('no recovery')
            ? copy.primaryRecoverySupportHint
            : msg;
      });
    }
  }

  Future<void> _sendEmailOtp() async {
    final id = _recoveryId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .sendPrimaryRecoveryEmailOtp(recoveryId: id);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _completeRecovery() async {
    final id = _recoveryId;
    final code = _codeCtrl.text.trim();
    if (id == null || code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).completePrimaryRecovery(
            recoveryId: id,
            method: _method,
            code: code,
          );
      if (!mounted) return;
      context.go('/profiles');
    } on ApiException catch (e) {
      if (!mounted) return;
      final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
      setState(() {
        _busy = false;
        _deviceLimit = e.isDeviceLimit;
        _error = e.isDeviceLimit
            ? copy.deviceLimitReached
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _methodLabel(AppCopy copy, String method) {
    switch (method) {
      case 'recovery_code':
        return copy.primaryRecoveryMethodRecoveryCode;
      case 'email_otp':
        return copy.primaryRecoveryMethodEmailOtp;
      case 'totp':
      default:
        return copy.primaryRecoveryMethodTotp;
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(sessionProvider).language);
    return AuthScaffold(
      title: _showRecovery
          ? copy.primaryRecoveryTitle
          : copy.waitingForApprovalTitle,
      subtitle: _showRecovery
          ? copy.primaryRecoveryBody
          : copy.waitingForApprovalBody,
      badge: 'SECURE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading && !_showRecovery) ...[
            const SizedBox(height: 24),
            Center(child: AppLoader.inline(size: 36)),
            const SizedBox(height: 18),
            Text(
              copy.waitingForApprovalBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            // Always offer escape hatch (soft-lock prevention); poll may also
            // set recoveryAvailable / methods for richer complete flow.
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => setState(() {
                _showRecovery = true;
                _loading = false;
                _recoveryAvailable = true;
              }),
              child: Text(copy.waitingForApprovalLostDevice),
            ),
          ],
          if (_showRecovery) ...[
            Text(
              copy.waitingForApprovalClaimHint,
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _userCtrl,
              decoration: InputDecoration(labelText: copy.emailOrUsername),
              textInputAction: TextInputAction.next,
              enabled: _recoveryId == null && !_busy,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: copy.password),
              enabled: _recoveryId == null && !_busy,
            ),
            if (_recoveryId == null) ...[
              const SizedBox(height: 16),
              PrimaryButton(
                label: _busy ? '…' : copy.waitingForApprovalClaimAction,
                onPressed: _busy ? null : _startRecovery,
              ),
            ] else ...[
              const SizedBox(height: 14),
              if (_recoveryMethods.length > 1)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in _recoveryMethods)
                      ChoiceChip(
                        label: Text(_methodLabel(copy, m)),
                        selected: _method == m,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _method = m),
                      ),
                  ],
                )
              else
                Text(
                  _methodLabel(copy, _method),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              if (_method == 'email_otp') ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _sendEmailOtp,
                  child: Text(copy.primaryRecoverySendEmailOtp),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _codeCtrl,
                decoration: InputDecoration(
                  labelText: _methodLabel(copy, _method),
                ),
                keyboardType: TextInputType.visiblePassword,
                enabled: !_busy,
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: _busy ? '…' : copy.primaryRecoveryComplete,
                onPressed: _busy ? null : _completeRecovery,
              ),
            ],
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _showRecovery = false;
                        _recoveryId = null;
                        _error = null;
                      });
                      _wait();
                    },
              child: Text(copy.cancel),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            if (_deviceLimit)
              Text(
                copy.deviceLimitReachedTitle,
                style: TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            if (_deviceLimit) const SizedBox(height: 6),
            Text(
              _error!,
              style: TextStyle(color: AppColors.danger, height: 1.4),
            ),
            if (_deviceLimit) ...[
              const SizedBox(height: 10),
              Text(
                copy.deviceLimitReachedBody,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: copy.retry,
                onPressed: _busy
                    ? null
                    : () {
                        setState(() {
                          _error = null;
                          _deviceLimit = false;
                        });
                      },
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => context.go('/auth/login'),
                child: Text(copy.cancel),
              ),
            ] else if (!_showRecovery) ...[
              const SizedBox(height: 16),
              PrimaryButton(
                label: copy.tvQrRefresh,
                onPressed: _wait,
              ),
              TextButton(
                onPressed: () => context.go('/auth/login'),
                child: Text(copy.cancel),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _showRecovery = true;
                  _loading = false;
                  _error = null;
                  _deviceLimit = false;
                }),
                child: Text(copy.waitingForApprovalLostDevice),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
