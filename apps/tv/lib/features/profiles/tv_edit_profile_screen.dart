import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';
import '../settings/tv_security_scaffold.dart';

/// Edit an existing TV profile: rename, kids, PIN, delete.
class TvEditProfileScreen extends ConsumerStatefulWidget {
  const TvEditProfileScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<TvEditProfileScreen> createState() =>
      _TvEditProfileScreenState();
}

class _TvEditProfileScreenState extends ConsumerState<TvEditProfileScreen> {
  AppCopy get _copy => AppCopy.ofLanguage(ref.read(tvLanguageProvider));

  String? _error;
  bool _busy = false;

  /// Avatar picked but not saved yet (client 21 Oct A11: there was no Save).
  String? _pending;

  Future<void> _saveAvatar(String profileId) async {
    final token = _pending;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(tvSessionProvider.notifier).updateProfile(id: profileId, avatar: token);
      if (mounted) setState(() => _pending = null);
    } catch (e) {
      if (mounted) setState(() => _error = AppAlerts.clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(TvProfile profile) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: profile.name),
    );
    if (name == null || name.trim().isEmpty || name.trim() == profile.name) {
      return;
    }
    await _run(
      () => ref.read(tvSessionProvider.notifier).updateProfile(
            id: profile.id,
            name: name,
          ),
    );
  }

  Future<void> _toggleKids(TvProfile profile) async {
    await _run(
      () => ref.read(tvSessionProvider.notifier).updateProfile(
            id: profile.id,
            isKids: !profile.isKids,
          ),
    );
  }

  Future<void> _setOrChangePin(TvProfile profile) async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _SetPinDialog(
        title: profile.hasPin ? _copy.pinChangeTitle : _copy.pinSetTitle,
      ),
    );
    if (pin == null) return;
    await _run(
      () => ref.read(tvSessionProvider.notifier).setProfilePin(profile.id, pin),
    );
  }

  Future<void> _clearPin(TvProfile profile) async {
    await _run(
      () => ref.read(tvSessionProvider.notifier).clearProfilePin(profile.id),
    );
  }

  Future<void> _delete(TvProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(_copy.removeProfileTitle(profile.name)),
        content: Text(_copy.removeProfileBody),
        actions: [
          // Cancel takes the focus, as in the other "remove" dialogs (it
          // was on Remove: one OK deleted the profile).
          FocusTile(
            autofocus: true,
            onTap: () => Navigator.pop(ctx, false),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_copy.cancel),
            ),
          ),
          FocusTile(
            onTap: () => Navigator.pop(ctx, true),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _copy.remove,
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(tvSessionProvider.notifier).removeProfile(profile.id);
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/profiles');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(tvLanguageProvider);
    final copy = AppCopy.ofLanguage(language);
    final session = ref.watch(tvSessionProvider);
    final profile =
        session.profiles.where((p) => p.id == widget.id).firstOrNull;

    if (profile == null) {
      return TvSecurityScaffold(
        title: copy.manageProfiles,
        subtitle: copy.profileNotFound,
        child: Center(child: Text(copy.profileNotFound)),
      );
    }

    final isActive = session.activeProfileId == profile.id;
    final rows = <(String, String, VoidCallback?)>[
      (
        copy.profileDisplayName,
        profile.name,
        _busy ? null : () => _rename(profile),
      ),
      (
        copy.kidsProfile,
        profile.isKids ? copy.enabled : copy.off,
        _busy ? null : () => _toggleKids(profile),
      ),
      (
        copy.pinLock,
        profile.hasPin ? copy.pinSet : copy.pinNotSet,
        _busy ? null : () => _setOrChangePin(profile),
      ),
      if (profile.hasPin)
        (
          copy.pinRemove,
          copy.pinRemoveHint,
          _busy ? null : () => _clearPin(profile),
        ),
      (
        copy.profileStatus,
        isActive ? copy.profileActive : copy.profileInactive,
        null,
      ),
      (
        copy.profileRemoveRow,
        copy.profileRemoveRowHint,
        _busy ? null : () => _delete(profile),
      ),
    ];

    return TvSecurityScaffold(
      title: profile.name,
      subtitle: copy.manageProfiles,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: profile.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: profile.color, width: 2),
              ),
              child: ProfileAvatarFace(initials: profile.initials, token: _pending ?? profile.avatar, color: profile.color, fontSize: 24, radius: 18),
            ),
          ),
          const SizedBox(height: 14),
          // Avatar picker: OK on a tile previews it, Save (below, once
          // something is picked) stores it on the profile (client 21 Oct A11).
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: kProfileAvatars.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final a = kProfileAvatars[i];
                return FocusTile(
                  borderRadius: 32,
                  onTap: _busy
                      ? null
                      : () => setState(() => _pending = a.token == profile.avatar ? null : a.token),
                  child: ProfileAvatar(
                    initials: profile.initials,
                    token: a.token,
                    size: 56,
                    selected: (_pending ?? profile.avatar) == a.token,
                  ),
                );
              },
            ),
          ),
          if (_pending != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AvatarButton(label: copy.cancel, onTap: _busy ? null : () => setState(() => _pending = null)),
                const SizedBox(width: 14),
                _AvatarButton(
                  label: _busy ? copy.saving : copy.save,
                  primary: true,
                  onTap: _busy ? null : () => _saveAvatar(profile.id),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: AppColors.danger),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final row = rows[i];
                final danger = row.$1 == copy.profileRemoveRow;
                return FocusTile(
                  autofocus: i == 0,
                  borderRadius: 14,
                  focusScale: 1.0,
                  onTap: row.$3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.$1,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: danger ? AppColors.danger : null,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            row.$2,
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: danger
                                  ? AppColors.danger
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(tvUiLanguage);
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(copy.renameProfile),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(labelText: copy.profileDisplayName),
          onSubmitted: (v) {
            if (v.trim().isEmpty) return;
            Navigator.pop(context, v);
          },
        ),
      ),
      actions: [
        FocusTile(
          onTap: () => Navigator.pop(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(copy.cancel),
          ),
        ),
        FocusTile(
          autofocus: true,
          onTap: () {
            if (_controller.text.trim().isEmpty) return;
            Navigator.pop(context, _controller.text);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              copy.save,
              style: TextStyle(color: AppColors.cyan),
            ),
          ),
        ),
      ],
    );
  }
}

class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog({required this.title});
  final String title;

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  String _pin = '';

  void _digit(String d) {
    if (_pin.length >= 4) return;
    setState(() => _pin += d);
    if (_pin.length == 4) {
      Navigator.pop(context, _pin);
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(tvUiLanguage);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit0): () => _digit('0'),
        const SingleActivator(LogicalKeyboardKey.digit1): () => _digit('1'),
        const SingleActivator(LogicalKeyboardKey.digit2): () => _digit('2'),
        const SingleActivator(LogicalKeyboardKey.digit3): () => _digit('3'),
        const SingleActivator(LogicalKeyboardKey.digit4): () => _digit('4'),
        const SingleActivator(LogicalKeyboardKey.digit5): () => _digit('5'),
        const SingleActivator(LogicalKeyboardKey.digit6): () => _digit('6'),
        const SingleActivator(LogicalKeyboardKey.digit7): () => _digit('7'),
        const SingleActivator(LogicalKeyboardKey.digit8): () => _digit('8'),
        const SingleActivator(LogicalKeyboardKey.digit9): () => _digit('9'),
        const SingleActivator(LogicalKeyboardKey.backspace): _backspace,
      },
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(widget.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                copy.pinEnterFour,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _pin.length;
                  return Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? AppColors.cyan : Colors.transparent,
                      border: Border.all(color: AppColors.cyan),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (final d in [
                    '1',
                    '2',
                    '3',
                    '4',
                    '5',
                    '6',
                    '7',
                    '8',
                    '9',
                    '←',
                    '0',
                  ])
                    FocusTile(
                      autofocus: d == '1',
                      onTap: () => d == '←' ? _backspace() : _digit(d),
                      child: Container(
                        width: 56,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            FocusTile(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(copy.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.label, this.onTap, this.primary = false});

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return FocusTile(
      borderRadius: 26,
      onTap: onTap,
      child: Container(
        height: 48,
        width: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? AppColors.cyan : AppColors.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: primary ? AppColors.cyan : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary ? Colors.black : AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
      ),
    );
  }
}
