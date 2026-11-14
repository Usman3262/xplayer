import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/tv_clock.dart';
import '../../core/tv_demo_mode.dart';
import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_poster.dart';
import '../../widgets/tv_ui.dart';

/// TV login: QR + 6-digit code (WhatsApp Web style) or password fallback.
class TvLoginScreen extends ConsumerStatefulWidget {
  const TvLoginScreen({super.key});

  @override
  ConsumerState<TvLoginScreen> createState() => _TvLoginScreenState();
}

enum _TvLoginMode { qr, password, waitingApproval }

class _TvLoginScreenState extends ConsumerState<TvLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _usernameFocus = FocusNode(debugLabel: 'login-username');
  final _passwordFocus = FocusNode(debugLabel: 'login-password');
  final _qrRefreshFocus = FocusNode(debugLabel: 'login-qr-refresh');
  final _qrPasswordFocus = FocusNode(debugLabel: 'login-qr-to-password');
  final _signInFocus = FocusNode(debugLabel: 'login-sign-in');
  final _langFocus = FocusNode(debugLabel: 'login-lang');
  bool _remember = true;
  bool _obscure = true;
  bool _loading = false;
  bool _polling = false;
  String? _error;
  _TvLoginMode _mode = _TvLoginMode.qr;
  DeviceCodeDto? _deviceCode;
  String? _approvalChallengeId;
  bool _recoveryAvailable = false;
  bool _qrBootstrapped = false;
  /// Soft keyboard only after OK/Select on a field (D-pad focus must not open IME).
  FocusNode? _imeAllowedFor;
  /// Bumped to cancel an in-flight device-code poll when leaving QR mode.
  int _qrPollGen = 0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
    HardwareKeyboard.instance.addHandler(_onRemoteKeyLog);
    _usernameFocus.addListener(_onFieldFocusChanged);
    _passwordFocus.addListener(_onFieldFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startQr();
    });
  }

  @override
  void dispose() {
    _qrPollGen++;
    FocusManager.instance.removeListener(_onFocusChanged);
    HardwareKeyboard.instance.removeHandler(_onRemoteKeyLog);
    _usernameFocus.removeListener(_onFieldFocusChanged);
    _passwordFocus.removeListener(_onFieldFocusChanged);
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _qrRefreshFocus.dispose();
    _qrPasswordFocus.dispose();
    _signInFocus.dispose();
    _langFocus.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _hideIme() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _onFieldFocusChanged() {
    if (!mounted) return;
    for (final n in [_usernameFocus, _passwordFocus]) {
      if (n.hasFocus) {
        if (identical(_imeAllowedFor, n)) return;
        // Remote moved onto the field — keep focus, do not pop the keyboard.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !n.hasFocus) return;
          if (identical(_imeAllowedFor, n)) return;
          _hideIme();
        });
        return;
      }
    }
    // Left both fields — next Select must re-arm IME.
    _imeAllowedFor = null;
  }

  void _onFocusChanged() {
    // Focus chatter was flooding TV logs; keep silent in normal debug runs.
  }

  bool _onRemoteKeyLog(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final node = FocusManager.instance.primaryFocus;

    // OK on a text field: allow IME, then the global TV text handler opens it.
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (identical(node, _usernameFocus) || identical(node, _passwordFocus)) {
        _imeAllowedFor = node;
      }
    }
    return false;
  }

  void _focusQrActions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mode != _TvLoginMode.qr) return;
      _imeAllowedFor = null;
      _hideIme();
      if (_qrRefreshFocus.canRequestFocus) {
        _qrRefreshFocus.requestFocus();
      } else if (_qrPasswordFocus.canRequestFocus) {
        _qrPasswordFocus.requestFocus();
      }
    });
  }

  void _focusPasswordFields() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _imeAllowedFor = null;
      _hideIme();
      _usernameFocus.requestFocus();
    });
  }

  Future<void> _startQr() async {
    _qrPollGen++;
    setState(() {
      _loading = true;
      _error = null;
      _mode = _TvLoginMode.qr;
      _deviceCode = null;
    });
    try {
      final code =
          await ref.read(tvSessionProvider.notifier).beginDeviceCodeLogin();
      if (!mounted || _mode != _TvLoginMode.qr) return;
      setState(() {
        _deviceCode = code;
        _loading = false;
        _qrBootstrapped = true;
      });
      _focusQrActions();
      unawaited(_pollQr(code));
    } catch (e) {
      if (!mounted) return;
      // Backend flag off / not deployed → password login.
      setState(() {
        _loading = false;
        _mode = _TvLoginMode.password;
        _qrBootstrapped = true;
        _error = null;
      });
      _focusPasswordFields();
    }
  }

  Future<void> _pollQr(DeviceCodeDto code) async {
    final gen = ++_qrPollGen;
    if (mounted) setState(() => _polling = true);
    try {
      await ref.read(tvSessionProvider.notifier).completeDeviceCode(
            code,
            shouldContinue: () =>
                mounted && _mode == _TvLoginMode.qr && gen == _qrPollGen,
          );
      if (!mounted) return;
      context.go('/profiles');
    } catch (e) {
      if (!mounted) return;
      if (_isPollCancelled(e)) return;
      if (_mode != _TvLoginMode.qr) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
        _polling = false;
      });
    }
  }

  bool _isPollCancelled(Object e) {
    if (e is ApiException && e.code == 'CANCELLED') return true;
    final s = e.toString();
    return s.contains('CANCELLED') || s.contains('Cancelled');
  }

  Future<void> _signIn() async {
    _qrPollGen++;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(tvSessionProvider.notifier).login(
            email: _email.text,
            password: _password.text,
            rememberMe: _remember,
          );
      if (!mounted) return;
      context.go('/profiles');
    } on LoginApprovalRequiredException catch (e) {
      if (!mounted) return;
      _qrPollGen++;
      setState(() {
        _mode = _TvLoginMode.waitingApproval;
        _approvalChallengeId = e.challengeId;
        _loading = true;
        _error = null;
      });
      try {
        await ref.read(tvSessionProvider.notifier).completeLoginApproval(
              e.challengeId,
              onStatus: (status) {
                if (!mounted) return;
                if (status.canOfferRecovery != _recoveryAvailable) {
                  setState(() => _recoveryAvailable = status.canOfferRecovery);
                }
              },
            );
        if (!mounted) return;
        context.go('/profiles');
      } catch (err) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = err.toString().replaceFirst('Exception: ', '');
        });
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && _mode != _TvLoginMode.waitingApproval) {
        setState(() => _loading = false);
      }
    }
  }

  void _switchToPassword() {
    _qrPollGen++;
    setState(() {
      _mode = _TvLoginMode.password;
      _error = null;
      _polling = false;
    });
    _focusPasswordFields();
  }

  void _switchToQr() {
    setState(() {
      _mode = _TvLoginMode.qr;
      _error = null;
      _polling = false;
    });
    _focusQrActions();
    if (_deviceCode == null) {
      unawaited(_startQr());
    } else {
      unawaited(_pollQr(_deviceCode!));
    }
  }

  Future<void> _openPrimaryRecovery() async {
    final copy = AppCopy.ofLanguage(ref.read(tvLanguageProvider));
    final challengeId = _approvalChallengeId;
    if (challengeId == null) return;
    final userCtrl = TextEditingController(text: _email.text.trim());
    final passCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    String? recoveryId;
    var method = 'totp';
    var methods = <String>['totp', 'recovery_code', 'email_otp'];
    String? dialogError;
    var busy = false;
    var deviceLimit = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> start() async {
              setLocal(() {
                busy = true;
                dialogError = null;
                deviceLimit = false;
              });
              try {
                final started =
                    await ref.read(tvSessionProvider.notifier).startPrimaryRecovery(
                          challengeId: challengeId,
                          usernameOrEmail: userCtrl.text.trim(),
                          password: passCtrl.text,
                        );
                recoveryId = started.recoveryId;
                if (started.methods.isNotEmpty) {
                  methods = started.methods;
                  method = methods.first;
                }
                setLocal(() => busy = false);
              } catch (e) {
                setLocal(() {
                  busy = false;
                  dialogError = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            Future<void> complete() async {
              final id = recoveryId;
              if (id == null || codeCtrl.text.trim().isEmpty) return;
              setLocal(() {
                busy = true;
                dialogError = null;
                deviceLimit = false;
              });
              try {
                await ref.read(tvSessionProvider.notifier).completePrimaryRecovery(
                      recoveryId: id,
                      method: method,
                      code: codeCtrl.text.trim(),
                    );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                context.go('/profiles');
              } on ApiException catch (e) {
                setLocal(() {
                  busy = false;
                  deviceLimit = e.isDeviceLimit;
                  dialogError = e.isDeviceLimit
                      ? copy.deviceLimitReached
                      : e.message;
                });
              } catch (e) {
                setLocal(() {
                  busy = false;
                  dialogError = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            return Dialog(
              backgroundColor: const Color(0xFF0E121A),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        copy.primaryRecoveryTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        copy.primaryRecoveryBody,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (recoveryId == null) ...[
                        TextField(
                          controller: userCtrl,
                          decoration:
                              InputDecoration(labelText: copy.emailOrUsername),
                          enabled: !busy,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: passCtrl,
                          obscureText: true,
                          decoration: InputDecoration(labelText: copy.password),
                          enabled: !busy,
                        ),
                        const SizedBox(height: 14),
                        PrimaryButton(
                          label: busy ? '…' : copy.waitingForApprovalClaimAction,
                          onPressed: busy ? null : () => unawaited(start()),
                        ),
                      ] else ...[
                        Text(
                          method == 'recovery_code'
                              ? copy.primaryRecoveryMethodRecoveryCode
                              : method == 'email_otp'
                                  ? copy.primaryRecoveryMethodEmailOtp
                                  : copy.primaryRecoveryMethodTotp,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (methods.length > 1) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final m in methods)
                                ChoiceChip(
                                  label: Text(
                                    m == 'recovery_code'
                                        ? copy.primaryRecoveryMethodRecoveryCode
                                        : m == 'email_otp'
                                            ? copy.primaryRecoveryMethodEmailOtp
                                            : copy.primaryRecoveryMethodTotp,
                                  ),
                                  selected: method == m,
                                  onSelected: busy
                                      ? null
                                      : (_) => setLocal(() => method = m),
                                ),
                            ],
                          ),
                        ],
                        if (method == 'email_otp') ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final id = recoveryId;
                                    if (id == null) return;
                                    try {
                                      await ref
                                          .read(tvSessionProvider.notifier)
                                          .sendPrimaryRecoveryEmailOtp(
                                            recoveryId: id,
                                          );
                                    } catch (e) {
                                      setLocal(() {
                                        dialogError = e
                                            .toString()
                                            .replaceFirst('Exception: ', '');
                                      });
                                    }
                                  },
                            child: Text(copy.primaryRecoverySendEmailOtp),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextField(
                          controller: codeCtrl,
                          decoration: InputDecoration(
                            labelText: copy.primaryRecoveryMethodTotp,
                          ),
                          enabled: !busy,
                        ),
                        const SizedBox(height: 14),
                        PrimaryButton(
                          label: busy ? '…' : copy.primaryRecoveryComplete,
                          onPressed: busy ? null : () => unawaited(complete()),
                        ),
                      ],
                      if (dialogError != null) ...[
                        const SizedBox(height: 10),
                        if (deviceLimit)
                          Text(
                            copy.deviceLimitReachedTitle,
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        if (deviceLimit) const SizedBox(height: 4),
                        Text(
                          dialogError!,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                        if (deviceLimit) ...[
                          const SizedBox(height: 6),
                          Text(
                            copy.deviceLimitReachedBody,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              height: 1.35,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                      if (deviceLimit) ...[
                        const SizedBox(height: 12),
                        PrimaryButton(
                          label: copy.retry,
                          onPressed: busy
                              ? null
                              : () => setLocal(() {
                                    dialogError = null;
                                    deviceLimit = false;
                                  }),
                        ),
                      ],
                      TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                if (deviceLimit) _switchToPassword();
                              },
                        child: Text(copy.cancel),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    // Dispose after the dialog route has fully torn down (avoids TextField
    // rebuilds against disposed controllers during the exit animation).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      userCtrl.dispose();
      passCtrl.dispose();
      codeCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final language = ref.watch(tvLanguageProvider);
    final clock = tvClockNow(context);
    final h = MediaQuery.sizeOf(context).height;
    final compact = h < 720;
    final qrActive = _mode == _TvLoginMode.qr;
    final passwordActive = _mode == _TvLoginMode.password;

    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      // Keep the layout still when the TV keyboard opens. Resizing squeezed
      // both panes into the space above the keyboard: the password field was
      // pushed under the top bar and "Sign in with password" overlapped the
      // code digits (TCL). The fields sit above the keyboard anyway; the
      // keyboard's own Done/✓ key submits.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            TvUi.pageGutter,
            compact ? 12 : 18,
            TvUi.pageGutter,
            compact ? 10 : 14,
          ),
          child: Column(
            children: [
              _TopBar(clock: clock, copy: copy),
              SizedBox(height: compact ? 10 : 16),
              Expanded(
                child: _mode == _TvLoginMode.waitingApproval
                    ? Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: _WaitPane(
                            copy: copy,
                            compact: compact,
                            error: _error,
                            loading: _loading,
                            showRecovery: _recoveryAvailable,
                            onCancel: _switchToPassword,
                            onRecovery: () => unawaited(_openPrimaryRecovery()),
                          ),
                        ),
                      )
                    : FocusTraversalGroup(
                        policy: ReadingOrderTraversalPolicy(),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _QrPane(
                                copy: copy,
                                compact: compact,
                                loading: _loading && _deviceCode == null,
                                polling: _polling && _deviceCode != null,
                                code: _deviceCode,
                                error: qrActive ? _error : null,
                                highlighted: qrActive,
                                refreshFocus: _qrRefreshFocus,
                                passwordFocus: _qrPasswordFocus,
                                autofocusActions: qrActive,
                                onRefresh: _startQr,
                                onPassword: _switchToPassword,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 10 : 16,
                              ),
                              child: Column(
                                children: [
                                  const Expanded(
                                    child: VerticalDivider(
                                      width: 1,
                                      thickness: 1,
                                      color: Color(0x33FFFFFF),
                                    ),
                                  ),
                                  Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF111622),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.16,
                                        ),
                                      ),
                                    ),
                                    child: const Text(
                                      'OR',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  const Expanded(
                                    child: VerticalDivider(
                                      width: 1,
                                      thickness: 1,
                                      color: Color(0x33FFFFFF),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _SignInPane(
                                email: _email,
                                emailFocus: _usernameFocus,
                                password: _password,
                                passwordFocus: _passwordFocus,
                                signInFocus: _signInFocus,
                                obscure: _obscure,
                                remember: _remember,
                                loading: _loading && passwordActive,
                                error: passwordActive ? _error : null,
                                compact: compact,
                                copy: copy,
                                showQrToggle: _qrBootstrapped,
                                highlighted: passwordActive,
                                onToggleObscure: () =>
                                    setState(() => _obscure = !_obscure),
                                onToggleRemember: (v) =>
                                    setState(() => _remember = v),
                                onSignIn: _signIn,
                                onQr: _switchToQr,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              SizedBox(height: compact ? 6 : 10),
              Text(
                copy.mediaPlayerOnlyNotice,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: compact ? 6 : 10),
              _FooterBar(
                languageLabel: language,
                langFocus: _langFocus,
                onToggleLang: () =>
                    ref.read(tvLanguageProvider.notifier).toggle(),
                copy: copy,
                // Demo (client 5 Nov #30): the real app with sample content.
                onTryDemo: () {
                  ref.read(tvDemoModeProvider.notifier).state = true;
                  context.go('/home');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.clock, required this.copy});
  final String clock;
  final AppCopy copy;

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => TvHelpDialog(copy: copy),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const AppLogo(height: 36, alignToStart: true),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Text(
              TvPlatformProfile.pc ? 'WINDOWS PC' : 'LIVING ROOM TV',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.7,
              ),
            ),
          ),
          const Spacer(),
          FocusTile(
            borderRadius: 999,
            onTap: () => _showHelp(context),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.help_outline_rounded, size: 22),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.match,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  copy.sslBadge,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                clock,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterBar extends StatelessWidget {
  const _FooterBar({
    required this.languageLabel,
    required this.langFocus,
    required this.onToggleLang,
    required this.copy,
    this.onTryDemo,
  });

  final VoidCallback? onTryDemo;
  final String languageLabel;
  final FocusNode langFocus;
  final VoidCallback onToggleLang;
  final AppCopy copy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FooterChip(
                  icon: Icons.verified_user_outlined,
                  label: copy.sslBadge,
                  iconColor: AppColors.match,
                ),
                const SizedBox(width: 8),
                const _FooterChip(
                  icon: Icons.hd_outlined,
                  label: 'Ultra HD 4K HDR10+',
                ),
                const SizedBox(width: 8),
                const _FooterChip(
                  icon: Icons.spatial_audio_off_outlined,
                  label: 'Dolby Atmos',
                  iconColor: AppColors.magenta,
                ),
                const SizedBox(width: 8),
                FocusTile(
                  borderRadius: 999,
                  onTap: () => context.push('/legal/terms'),
                  child: _FooterChip(
                    icon: Icons.description_outlined,
                    label: copy.termsOfUse,
                  ),
                ),
                const SizedBox(width: 8),
                FocusTile(
                  borderRadius: 999,
                  onTap: () => context.push('/legal/privacy'),
                  child: _FooterChip(
                    icon: Icons.privacy_tip_outlined,
                    label: copy.privacyPolicy,
                  ),
                ),
                if (onTryDemo != null) ...[
                  const SizedBox(width: 8),
                  FocusTile(
                    borderRadius: 999,
                    onTap: onTryDemo!,
                    child: _FooterChip(
                      icon: Icons.play_circle_outline_rounded,
                      label: copy.tryDemo,
                      iconColor: AppColors.cyan,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        FocusTile(
          focusNode: langFocus,
          borderRadius: 999,
          onTap: onToggleLang,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.language, size: 15),
                const SizedBox(width: 6),
                Text(
                  languageLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QrPane extends StatelessWidget {
  const _QrPane({
    required this.copy,
    required this.compact,
    required this.loading,
    this.polling = false,
    required this.code,
    required this.error,
    required this.highlighted,
    required this.refreshFocus,
    required this.passwordFocus,
    required this.autofocusActions,
    required this.onRefresh,
    required this.onPassword,
  });

  final AppCopy copy;
  final bool compact;
  final bool loading;
  final bool polling;
  final DeviceCodeDto? code;
  final String? error;
  final bool highlighted;
  final FocusNode refreshFocus;
  final FocusNode passwordFocus;
  final bool autofocusActions;
  final VoidCallback onRefresh;
  final VoidCallback onPassword;

  @override
  Widget build(BuildContext context) {
    final qrSize = compact ? 132.0 : 168.0;
    final pin = (code?.code ?? '——————').padRight(6, '—');

    return TvGlass(
      radius: 18,
      tint: highlighted ? AppColors.cyan : null,
      padding: EdgeInsets.all(compact ? 14 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 12,
                  color: AppColors.cyan,
                ),
                const SizedBox(width: 6),
                Text(
                  copy.activateTv.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            copy.tvQrLoginTitle,
            style: TextStyle(
              fontSize: compact ? 20 : 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            copy.tvQrLoginHint,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.4,
              fontSize: 12,
            ),
          ),
          SizedBox(height: compact ? 12 : 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (code != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: code!.qrPayload,
                      size: qrSize,
                      backgroundColor: Colors.white,
                    ),
                  )
                else
                  Container(
                    width: qrSize,
                    height: qrSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: loading
                        ? AppLoader.inline(size: 28)
                        : const Icon(
                            Icons.qr_code_2_rounded,
                            size: 40,
                            color: AppColors.textSecondary,
                          ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        copy.tvQrLoginTitle.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0; i < 6; i++)
                            Container(
                              width: compact ? 28 : 34,
                              height: compact ? 36 : 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0C101A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.cyan.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                              child: Text(
                                pin[i],
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: compact ? 16 : 18,
                                  color: AppColors.cyan,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (code != null)
                        Row(
                          children: [
                            if (polling) ...[
                              AppLoader.inline(size: 18),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                copy.tvQrWaiting,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (error != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          error!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              FocusTile(
                focusNode: refreshFocus,
                autofocus: autofocusActions,
                borderRadius: 10,
                onTap: onRefresh,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.refresh_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text(copy.tvQrRefresh, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              FocusTile(
                focusNode: passwordFocus,
                borderRadius: 10,
                onTap: onPassword,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Text(
                    copy.tvPasswordInstead,
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WaitPane extends StatelessWidget {
  const _WaitPane({
    required this.copy,
    required this.compact,
    required this.error,
    required this.loading,
    required this.showRecovery,
    required this.onCancel,
    required this.onRecovery,
  });

  final AppCopy copy;
  final bool compact;
  final String? error;
  final bool loading;
  final bool showRecovery;
  final VoidCallback onCancel;
  final VoidCallback onRecovery;

  @override
  Widget build(BuildContext context) {
    return TvGlass(
      radius: 18,
      padding: EdgeInsets.all(compact ? 16 : 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            copy.waitingForApprovalTitle,
            style: TextStyle(
              fontSize: compact ? 20 : 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            copy.waitingForApprovalBody,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          if (loading) AppLoader.inline(size: 40),
          if (loading) const SizedBox(height: 8),
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 12),
          ],
          FocusTile(
            onTap: onRecovery,
            child: Text(
              copy.waitingForApprovalLostDevice,
              style: const TextStyle(
                color: AppColors.cyan,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onCancel,
            child: Text(copy.cancel),
          ),
        ],
      ),
    );
  }
}

class _SignInPane extends StatelessWidget {
  const _SignInPane({
    required this.email,
    required this.emailFocus,
    required this.password,
    required this.passwordFocus,
    required this.signInFocus,
    required this.obscure,
    required this.remember,
    required this.loading,
    required this.error,
    required this.compact,
    required this.copy,
    required this.showQrToggle,
    required this.highlighted,
    required this.onToggleObscure,
    required this.onToggleRemember,
    required this.onSignIn,
    required this.onQr,
  });

  final TextEditingController email;
  final FocusNode emailFocus;
  final TextEditingController password;
  final FocusNode passwordFocus;
  final FocusNode signInFocus;
  final bool obscure;
  final bool remember;
  final bool loading;
  final String? error;
  final bool compact;
  final AppCopy copy;
  final bool showQrToggle;
  final bool highlighted;
  final VoidCallback onToggleObscure;
  final ValueChanged<bool> onToggleRemember;
  final VoidCallback onSignIn;
  final VoidCallback onQr;

  @override
  Widget build(BuildContext context) {
    return TvGlass(
      radius: 18,
      tint: highlighted ? AppColors.cyan : null,
      padding: EdgeInsets.all(compact ? 14 : 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    copy.welcomeBack,
                    style: TextStyle(
                      fontSize: compact ? 20 : 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                // Task #143 #5: QR switch in header (not under the form).
                if (showQrToggle) ...[
                  FocusTile(
                    borderRadius: 10,
                    onTap: onQr,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        copy.tvQrInstead,
                        style: const TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    TvPlatformProfile.pc ? 'Keyboard' : 'TV Remote',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              copy.signInContinue,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            SizedBox(height: compact ? 12 : 16),
            Text(
              copy.username.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Color(0xFFCBD5E1),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: email,
              focusNode: emailFocus,
              keyboardType: TextInputType.text,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => passwordFocus.requestFocus(),
              style: const TextStyle(fontWeight: FontWeight.w600),
              cursorColor: AppColors.cyan,
              decoration: _fieldDecoration(
                prefix: Icons.person_outline_rounded,
                compact: compact,
              ),
            ),
            SizedBox(height: compact ? 10 : 12),
            Text(
              copy.passwordLabel,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Color(0xFFCBD5E1),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: password,
              focusNode: passwordFocus,
              obscureText: obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!loading) onSignIn();
              },
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
              cursorColor: AppColors.cyan,
              decoration: _fieldDecoration(
                prefix: Icons.lock_outline_rounded,
                compact: compact,
                suffix: IconButton(
                  onPressed: onToggleObscure,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  height: 36,
                  width: 36,
                  child: Checkbox(
                    value: remember,
                    onChanged: (v) => onToggleRemember(v ?? true),
                    activeColor: AppColors.cyan,
                    checkColor: Colors.black,
                  ),
                ),
                Text(copy.rememberMe, style: const TextStyle(fontSize: 13)),
              ],
            ),
            if (error != null) ...[
              Text(error!, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 6),
            ],
            SizedBox(height: compact ? 10 : 14),
            FocusTile(
              focusNode: signInFocus,
              borderRadius: 12,
              onTap: loading ? null : onSignIn,
              child: Container(
                width: double.infinity,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.cyan,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.35),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: loading
                    ? Center(child: AppLoader.button())
                    : Text(
                        copy.signIn,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            // Task #143 #5: thank-you under form with animated glow.
            _TvThankYouGlow(copy: copy),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    IconData? prefix,
    Widget? suffix,
    bool compact = false,
  }) {
    return InputDecoration(
      isDense: compact,
      prefixIcon: prefix == null
          ? null
          : Icon(prefix, color: AppColors.textSecondary, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFF0C101A),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 12 : 14,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
      ),
    );
  }
}

class _FooterChip extends StatelessWidget {
  _FooterChip({
    required this.icon,
    required this.label,
    this.iconColor = AppColors.cyan,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TvThankYouGlow extends StatefulWidget {
  const _TvThankYouGlow({required this.copy});

  final AppCopy copy;

  @override
  State<_TvThankYouGlow> createState() => _TvThankYouGlowState();
}

class _TvThankYouGlowState extends State<_TvThankYouGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final a = 0.25 + (_c.value * 0.35);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.cyan.withValues(alpha: a * 0.35),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Text(
            widget.copy.thankYouChoosingApp,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.cyan.withValues(alpha: 0.55 + a * 0.35),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        );
      },
    );
  }
}

class TvHelpDialog extends ConsumerStatefulWidget {
  const TvHelpDialog({required this.copy});
  final AppCopy copy;

  @override
  ConsumerState<TvHelpDialog> createState() => _TvHelpDialogState();
}

class _TvHelpDialogState extends ConsumerState<TvHelpDialog> {
  final _contact = TextEditingController();
  final _message = TextEditingController();

  @override
  void dispose() {
    _contact.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = _contact.text.trim();
    final m = _message.text.trim();
    if (c.isEmpty || m.isEmpty) return;
    // Sent to the Control Panel support inbox; kept on the TV only if the
    // server cannot be reached.
    var sent = false;
    try {
      final info = await PackageInfo.fromPlatform();
      await ref.read(tvAuthRepositoryProvider).sendSupportRequest(
            contact: c,
            message: m,
            platform: 'tv',
            appVersion: '${info.version} (${info.buildNumber})',
            language: widget.copy.lang.name,
          );
      sent = true;
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        const key = 'sub_help_tickets';
        final prev = prefs.getStringList(key) ?? <String>[];
        prev.add('${DateTime.now().toIso8601String()}|$c|$m');
        await prefs.setStringList(key, prev);
      } catch (_) {}
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          sent ? widget.copy.helpRequestSent : widget.copy.helpSavedOnDevice,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    return AlertDialog(
      backgroundColor: const Color(0xFF111622),
      title: Text(copy.needHelpSub),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.loginHelpBody,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _contact,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: copy.helpContactLabel,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _message,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: copy.helpDescribeIssue,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(copy.gotIt),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(copy.helpSubmitRequest),
        ),
      ],
    );
  }
}
