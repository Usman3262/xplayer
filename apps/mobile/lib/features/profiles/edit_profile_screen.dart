import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_controller.dart';
import 'kids_pin.dart';
import '../../widgets/main_app_bar.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  /// Avatar picked but not saved yet (client 21 Oct A11: there was no Save).
  String? _pending;
  bool _saving = false;

  String get id => widget.id;

  Future<void> _saveAvatar(String profileId) async {
    final token = _pending;
    if (token == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(sessionProvider.notifier).setProfileAvatar(profileId, token);
      if (!mounted) return;
      setState(() => _pending = null);
      final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(copy.profileSaved)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppAlerts.clean(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final profile = session.profiles.where((p) => p.id == id).firstOrNull;
    final copy = AppCopy.ofLanguage(session.language);
    if (profile == null) {
      return Scaffold(body: Center(child: Text(copy.profileNotFound)));
    }

    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ProfileAvatar(initials: profile.initials, token: _pending ?? profile.avatar, size: 88),
          ),
          const SizedBox(height: 16),
          // Avatar picker: a tap previews, Save stores it on the profile
          // (client 21 Oct A11).
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final a in kProfileAvatars)
                GestureDetector(
                  onTap: _saving ? null : () => setState(() => _pending = a.token == profile.avatar ? null : a.token),
                  child: ProfileAvatar(
                    initials: profile.initials,
                    token: a.token,
                    size: 52,
                    selected: (_pending ?? profile.avatar) == a.token,
                  ),
                ),
            ],
          ),
          if (_pending != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: copy.cancel,
                    icon: Icons.close_rounded,
                    filled: false,
                    onPressed: _saving ? null : () => setState(() => _pending = null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: copy.save,
                    icon: Icons.check_rounded,
                    loading: _saving,
                    onPressed: _saving ? null : () => _saveAvatar(profile.id),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Center(
            child: Text(
              profile.name,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
            ),
          ),
          const SizedBox(height: 20),
          // Every row works (client 23 Oct #3: they were display-only).
          _tile(
            icon: Icons.badge_outlined,
            title: copy.profileDisplayName,
            value: profile.name,
            onTap: _busy ? null : () => _rename(profile.id, profile.name, copy),
          ),
          _switch(
            icon: Icons.child_care_rounded,
            title: copy.profileKidsMode,
            subtitle: copy.profileKidsModeHint,
            value: profile.isKids,
            onChanged: _busy ? null : (v) => _run(copy, () => ref.read(sessionProvider.notifier).setProfileKids(profile.id, v)),
          ),
          _switch(
            icon: Icons.lock_outline_rounded,
            title: copy.profileLock,
            subtitle: session.parentalPinEnabled ? copy.profileLockHint : copy.profileLockNeedsPin,
            value: profile.hasPin,
            onChanged: _busy ? null : (v) => _setLock(profile.id, v, copy),
          ),
          _tile(
            icon: Icons.language_rounded,
            title: copy.language,
            subtitle: copy.profileAppLanguageHint,
            value: AppLocale.isArabic(session.language) ? 'العربية' : 'English',
            onTap: () => context.push('/settings/language'),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: profile.isActive ? copy.profileActiveNow : copy.profileSwitchTo,
            filled: !profile.isActive,
            onPressed: profile.isActive
                ? null
                : () async {
                    final ok = await openProfileWithKidsPin(context, ref, profile);
                    if (ok && context.mounted) Navigator.pop(context);
                  },
          ),
        ],
      ),
    );
  }

  bool _busy = false;

  Future<void> _run(AppCopy copy, Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) AppAlerts.toastSuccess(context, title: copy.profileSaved, message: '');
    } catch (e) {
      if (mounted) AppAlerts.toastFailure(context, title: copy.failed, message: kidsPinErrorText(e, copy));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setLock(String profileId, bool locked, AppCopy copy) async {
    final session = ref.read(sessionProvider.notifier);
    if (locked && !ref.read(sessionProvider).parentalPinEnabled) {
      AppAlerts.toastAttention(context, title: copy.profileLock, message: copy.profileLockNeedsPin);
      context.push('/settings/parental');
      return;
    }
    // Turning the lock off needs the PIN, so a child cannot unlock a profile.
    if (!locked) {
      final pin = await askKidsPin(context, copy);
      if (pin == null || !mounted) return;
      try {
        await ref.read(authRepositoryProvider).verifyParentalPin(pin);
      } catch (e) {
        if (mounted) AppAlerts.toastFailure(context, title: copy.profileLock, message: kidsPinErrorText(e, copy));
        return;
      }
    }
    if (!mounted) return;
    await _run(copy, () => session.setProfileLocked(profileId, locked));
  }

  Future<void> _rename(String profileId, String current, AppCopy copy) async {
    final c = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(copy.profileDisplayName),
        content: TextField(controller: c, autofocus: true, maxLength: 64),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(copy.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(copy.save)),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.isEmpty || name == current || !mounted) return;
    await _run(copy, () => ref.read(sessionProvider.notifier).renameProfile(profileId, name));
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppColors.cyan),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: TextStyle(color: AppColors.textSecondary)),
            Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _switch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.cyan,
        secondary: Icon(icon, color: AppColors.cyan),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ),
    );
  }
}
