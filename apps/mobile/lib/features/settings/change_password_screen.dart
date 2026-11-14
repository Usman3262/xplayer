import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_controller.dart';
import '../../widgets/action_feedback.dart';
import 'security_detail_scaffold.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;
  bool _obscureCurrent = true;
  bool _obscureNext = true;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  AppCopy get _copy =>
      AppCopy.ofLanguage(ref.read(sessionProvider).language);

  Future<void> _submit() async {
    final copy = _copy;
    if (_current.text.isEmpty || _next.text.length < 8) {
      await ActionFeedback.error(
        context,
        title: copy.checkFields,
        message: copy.passwordFieldsHint,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      _current.clear();
      _next.clear();
      if (!mounted) return;
      await ActionFeedback.success(
        context,
        title: copy.passwordUpdated,
        message: copy.passwordUpdatedMsg,
      );
    } catch (e) {
      if (!mounted) return;
      await ActionFeedback.error(
        context,
        title: copy.updateFailed,
        message: ActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(sessionProvider).language);
    return SecurityDetailScaffold(
      title: copy.changePassword,
      subtitle: copy.changePasswordHint,
      badge: copy.passwordBadge,
      helpTitle: copy.changePasswordHelpTitle,
      helpBody: copy.changePasswordHelpBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _current,
            label: copy.currentPassword,
            obscure: _obscureCurrent,
            prefix: Icons.lock_outline_rounded,
            suffix: IconButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _obscureCurrent = !_obscureCurrent),
              icon: Icon(
                _obscureCurrent
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _next,
            label: copy.newPassword,
            obscure: _obscureNext,
            prefix: Icons.lock_rounded,
            suffix: IconButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _obscureNext = !_obscureNext),
              icon: Icon(
                _obscureNext
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          NeonGlowBorder(
            child: PrimaryButton(
              label: _busy ? copy.updating : copy.updatePassword,
              icon: Icons.check_rounded,
              loading: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ),
        ],
      ),
    );
  }
}
