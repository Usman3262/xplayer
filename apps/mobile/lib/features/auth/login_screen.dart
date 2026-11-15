import 'dart:io' show Platform;
import 'dart:ui';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/session_controller.dart';

/// Figma: the app Mobile Login (14:4569)
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _remember = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _showLoginHelp(BuildContext context, AppCopy copy) =>
      showSupportHelpSheet(context, copy);

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).login(
            email: _email.text.trim(),
            password: _password.text,
            rememberMe: _remember,
          );
      if (!mounted) return;
      context.go('/profiles');
    } on MfaRequiredException catch (e) {
      if (!mounted) return;
      context.push(
        '/auth/mfa?challenge=${Uri.encodeComponent(e.mfaChallengeId)}',
      );
    } on LoginApprovalRequiredException catch (e) {
      if (!mounted) return;
      final q = StringBuffer(
        'challenge=${Uri.encodeComponent(e.challengeId)}',
      );
      if (e.expiresAt != null && e.expiresAt!.isNotEmpty) {
        q.write('&expires=${Uri.encodeComponent(e.expiresAt!)}');
      }
      context.push('/auth/login-approval?$q');
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(sessionProvider.select((s) => s.language));
    final copy = AppCopy.ofLanguage(language);

    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LoginGlow(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      LoginRoundIconBtn(
                        icon: const AppBackIcon(
                          size: 18,
                          style: AppBackIconStyle.chevron,
                        ),
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            // There is no '/' route; the sign-in start page.
                            context.go('/auth/welcome');
                          }
                        },
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xE6111622),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.cyan,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '4K ULTRA HD',
                              style: TextStyle(
                                color: AppColors.cyan,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              '  •  ',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 10,
                              ),
                            ),
                            const Text(
                              'VIP',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Task #143 #5: TV login option in top bar (not below form).
                      LoginRoundIconBtn(
                        icon: const Icon(Icons.tv_rounded),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(copy.tvActivationSnack)),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      LoginRoundIconBtn(
                        icon: const Icon(Icons.help_outline_rounded),
                        onTap: () => _showLoginHelp(context, copy),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Center(
                  child: AppLogo(height: 44, alignToStart: false),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                            decoration: BoxDecoration(
                              color: const Color(0xCC111622),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  blurRadius: 50,
                                  offset: const Offset(0, 20),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  copy.welcomeBack,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.6,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  copy.signInContinue,
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                LoginFieldLabel(copy.emailOrUsername),
                                const SizedBox(height: 6),
                                LoginField(
                                  controller: _email,
                                  hint: copy.emailHint,
                                  prefix: Icons.person_outline_rounded,
                                  keyboardType: TextInputType.text,
                                ),
                                const SizedBox(height: 14),
                                LoginFieldLabel(copy.passwordLabel),
                                const SizedBox(height: 6),
                                LoginField(
                                  controller: _password,
                                  obscure: _obscure,
                                  prefix: Icons.lock_outline_rounded,
                                  suffix: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 18,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: Checkbox(
                                        value: _remember,
                                        onChanged: (v) => setState(
                                          () => _remember = v ?? true,
                                        ),
                                        activeColor: AppColors.cyan,
                                        checkColor: Colors.black,
                                        side: BorderSide(
                                          color: AppColors.cyan,
                                        ),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      copy.rememberMe,
                                      style: const TextStyle(
                                        color: Color(0xFFCBD5E1),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    _error!,
                                    style: TextStyle(
                                      color: AppColors.danger,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.cyan
                                            .withValues(alpha: 0.35),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: SizedBox(
                                    height: 52,
                                    child: FilledButton(
                                      onPressed: _loading ? null : _submit,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.cyan,
                                        foregroundColor: Colors.black,
                                        disabledBackgroundColor:
                                            AppColors.cyan,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: _loading
                                          ? Center(child: AppLoader.button())
                                          : Text(
                                              copy.signIn,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 16,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                // Task #143 #5: thank-you under form (subtle glow).
                                _ThankYouGlow(copy: copy),
                                const SizedBox(height: 10),
                                GestureDetector(
                                  onTap: () => _showLoginHelp(context, copy),
                                  child: Text(
                                    copy.needHelpSub,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.cyan,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      decoration: TextDecoration.underline,
                                      decorationColor: AppColors.cyan,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC0C101A),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 12,
                              color: AppColors.cyan,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                copy.sslBadge,
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      AppLanguageToggle(
                        language: language,
                        onChanged: (v) {
                          ref.read(sessionProvider.notifier).setLanguage(v);
                        },
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => context.push('/settings/terms'),
                            child: Text(
                              copy.termsOfService,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 10,
                                decoration: TextDecoration.underline,
                                decorationColor:
                                    Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                          Text(
                            ' · ',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 10,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => context.push('/settings/privacy'),
                            child: Text(
                              copy.privacyPolicy,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 10,
                                decoration: TextDecoration.underline,
                                decorationColor:
                                    Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        copy.rightsReserved,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LoginFieldLabel extends StatelessWidget {
  const LoginFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFCBD5E1),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
  }
}

class LoginField extends StatelessWidget {
  const LoginField({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.prefix,
    this.suffix,
    this.keyboardType,
    this.errorText,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final IconData? prefix;
  final Widget? suffix;
  final TextInputType? keyboardType;

  /// Shown under the field (panel form validation).
  final String? errorText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      autocorrect: false,
      enableSuggestions: !obscure && keyboardType != TextInputType.url,
      cursorColor: AppColors.cyan,
      style: TextStyle(
        color: Colors.white,
        fontSize: 14,
        letterSpacing: obscure ? 1.4 : 0,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.danger, width: 1.5),
        ),
        hintStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
        ),
        prefixIcon: prefix == null
            ? null
            : Icon(prefix, size: 18, color: const Color(0xFF94A3B8)),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF0C101A),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.cyan, width: 1.5),
        ),
      ),
    );
  }
}

class LoginRoundIconBtn extends StatelessWidget {
  const LoginRoundIconBtn({super.key, required this.icon, required this.onTap});
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          alignment: Alignment.center,
          child: IconTheme(
            data: const IconThemeData(size: 18, color: Colors.white),
            child: icon,
          ),
        ),
      ),
    );
  }
}

class LoginGlow extends StatelessWidget {
  const LoginGlow({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -48,
          left: -64,
          child: _orb(AppColors.cyan, 280, 0.12),
        ),
        Positioned(
          top: 240,
          right: -80,
          child: _orb(const Color(0xFFE024C3), 260, 0.08),
        ),
        Positioned(
          bottom: 40,
          left: 40,
          child: _orb(AppColors.cyan, 280, 0.08),
        ),
      ],
    );
  }

  static Widget _orb(Color c, double size, double a) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [c.withValues(alpha: a), c.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// Subtle cyan glow under the login form (Task #143 #5).
class _ThankYouGlow extends StatefulWidget {
  const _ThankYouGlow({required this.copy});

  final AppCopy copy;

  @override
  State<_ThankYouGlow> createState() => _ThankYouGlowState();
}

class _ThankYouGlowState extends State<_ThankYouGlow>
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
      builder: (context, child) {
        final a = 0.25 + (_c.value * 0.35);
        return Container(
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

/// Owns help-sheet controllers so they are not disposed while the route
/// exit animation still rebuilds the TextFields (hot reload / pop race).
class LoginHelpSheet extends ConsumerStatefulWidget {
  const LoginHelpSheet({
    required this.copy,
    required this.hostContext,
  });

  final AppCopy copy;
  final BuildContext hostContext;

  @override
  ConsumerState<LoginHelpSheet> createState() => LoginHelpSheetState();
}

class LoginHelpSheetState extends ConsumerState<LoginHelpSheet> {
  final _contact = TextEditingController();
  final _message = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _contact.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = _contact.text.trim();
    final m = _message.text.trim();
    if (c.isEmpty || m.isEmpty) {
      ScaffoldMessenger.of(widget.hostContext).showSnackBar(
        SnackBar(
          content: Text(widget.copy.helpContactAndIssueMissing),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    // Sent to the Control Panel support inbox; kept on the device only if
    // the server cannot be reached.
    var sent = false;
    try {
      final info = await PackageInfo.fromPlatform();
      await ref.read(authRepositoryProvider).sendSupportRequest(
            contact: c,
            message: m,
            platform: Platform.isIOS ? 'ios' : 'android',
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
    Navigator.pop(context);
    if (!widget.hostContext.mounted) return;
    ScaffoldMessenger.of(widget.hostContext).showSnackBar(
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.help_outline_rounded,
                  color: AppColors.cyan,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    copy.needHelpSub,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              copy.loginHelpBody,
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _contact,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: copy.helpContactLabel,
                filled: true,
                fillColor: AppColors.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _message,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: copy.helpDescribeIssue,
                filled: true,
                fillColor: AppColors.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: _submitting ? copy.loading : copy.helpSubmitRequest,
                onPressed: _submitting ? null : _submit,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(copy.gotIt),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Help / support form (contact + issue → Control Panel inbox), used on the
/// login screen and in Settings → Help & Support.
void showSupportHelpSheet(BuildContext context, AppCopy copy) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF111622),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => LoginHelpSheet(copy: copy, hostContext: context),
  );
}
