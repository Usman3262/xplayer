import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_action_feedback.dart';
import 'tv_security_scaffold.dart';

class TvChangePasswordScreen extends ConsumerStatefulWidget {
  const TvChangePasswordScreen({super.key});

  @override
  ConsumerState<TvChangePasswordScreen> createState() =>
      _TvChangePasswordScreenState();
}

class _TvChangePasswordScreenState
    extends ConsumerState<TvChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;

  AppCopy get _copy =>
      AppCopy.ofLanguage(ref.read(tvLanguageProvider));

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final copy = _copy;
    if (_current.text.isEmpty || _next.text.length < 8) {
      await TvActionFeedback.error(
        context,
        title: copy.checkFields,
        message: copy.passwordFieldsHint,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(tvAuthRepositoryProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      _current.clear();
      _next.clear();
      if (!mounted) return;
      await TvActionFeedback.success(
        context,
        title: copy.passwordUpdated,
        message: copy.passwordUpdatedMsg,
      );
    } catch (e) {
      if (!mounted) return;
      await TvActionFeedback.error(
        context,
        title: copy.updateFailed,
        message: TvActionFeedback.clean(e),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    return TvSecurityScaffold(
      title: copy.changePassword,
      subtitle: copy.changePasswordHint,
      helpBody: copy.changePasswordHelpBody,
      child: ListView(
        children: [
          AppTextField(
            controller: _current,
            label: copy.currentPassword,
            obscure: true,
            prefix: Icons.lock_outline_rounded,
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _next,
            label: copy.newPassword,
            obscure: true,
            prefix: Icons.lock_rounded,
          ),
          const SizedBox(height: 18),
          FocusTile(
            borderRadius: 12,
            onTap: _busy ? null : _submit,
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
