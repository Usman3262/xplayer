import 'package:data/data.dart' show ApiException;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/tv_locale.dart';
import '../../core/tv_session.dart';
import '../../widgets/focus_tile.dart';

/// Netflix-style profile gate with real local profiles, PIN, and add.
class TvProfilesScreen extends ConsumerStatefulWidget {
  const TvProfilesScreen({super.key});

  @override
  ConsumerState<TvProfilesScreen> createState() => _TvProfilesScreenState();
}

class _TvProfilesScreenState extends ConsumerState<TvProfilesScreen> {
  String? _error;
  bool _manageMode = false;

  Future<void> _open(TvProfile profile) async {
    setState(() => _error = null);
    if (_manageMode) {
      if (!mounted) return;
      context.push('/profiles/edit/${profile.id}');
      return;
    }
    final session = ref.read(tvSessionProvider.notifier);
    await session.refreshKidsPin();
    if (!mounted) return;
    if (profile.hasPin || session.needsKidsPin(profile.id)) {
      final copy = AppCopy.ofLanguage(ref.read(tvLanguageProvider));
      final pin = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _TvPinDialog(
          profileName: profile.name,
          copy: copy,
        ),
      );
      if (pin == null) return;
      try {
        await ref.read(tvSessionProvider.notifier).selectProfile(
              profile.id,
              pin: pin,
            );
        if (!mounted) return;
        context.go('/home');
      } catch (e) {
        setState(() => _error = _pinError(e, copy));
      }
      return;
    }
    await ref.read(tvSessionProvider.notifier).selectProfile(profile.id);
    if (!mounted) return;
    context.go('/home');
  }

  static String _pinError(Object e, AppCopy copy) {
    if (e is ApiException) {
      if (e.isPinInvalid) return copy.kidsPinWrong(e.pinAttemptsLeft);
      if (e.isPinLocked) return copy.kidsPinLocked;
      if (e.isNetwork) return copy.kidsPinOffline;
      return e.message;
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _addProfile() async {
    final copy = AppCopy.ofLanguage(ref.read(tvLanguageProvider));
    final result = await showDialog<({String name, bool kids})>(
      context: context,
      builder: (_) => _AddProfileDialog(copy: copy),
    );
    if (result == null) return;
    try {
      await ref.read(tvSessionProvider.notifier).addProfile(
            name: result.name,
            kids: result.kids,
            withPin: result.kids,
          );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final session = ref.watch(tvSessionProvider);
    final profiles = session.profiles;

    if (!session.bootstrapped) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: AppLoading(label: copy.loading, auth: true),
      );
    }

    final showBack = context.canPop() || session.profileSelected;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                if (!showBack) return null;
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
                return null;
              },
            ),
          },
          child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
          child: Column(
            children: [
              Row(
                children: [
                  if (showBack) ...[
                    FocusTile(
                      autofocus: true,
                      borderRadius: 12,
                      borderWidth: 2,
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/home');
                        }
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: const AppBackIcon(
                          size: 20,
                          style: AppBackIconStyle.material,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  const Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AppLogo(height: 52, alignToStart: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                _manageMode ? copy.manageProfiles : copy.whosWatching,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26),
              ),
              const SizedBox(height: 8),
              Text(
                _manageMode ? copy.manageProfiles : copy.chooseProfile,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 36),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < profiles.length; i++) ...[
                          if (i > 0) const SizedBox(width: 22),
                          _ProfileCard(
                            profile: profiles[i],
                            autofocus: !showBack && i == 0,
                            manageMode: _manageMode,
                            kidsLabel: copy.kidsProfile,
                            onTap: () => _open(profiles[i]),
                          ),
                        ],
                        if (!_manageMode && profiles.length < 5) ...[
                          const SizedBox(width: 22),
                          _AddCard(
                            label: copy.addProfile,
                            subtitle: copy.profilesOfLimitActive(
                              profiles.length,
                            ),
                            onTap: _addProfile,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FocusTile(
                    onTap: () => setState(() {
                      _manageMode = !_manageMode;
                      _error = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                        color: AppColors.surface,
                      ),
                      child: Text(
                        _manageMode ? copy.confirm : copy.manageProfiles,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.onTap,
    required this.kidsLabel,
    this.autofocus = false,
    this.manageMode = false,
  });

  final TvProfile profile;
  final VoidCallback onTap;
  final String kidsLabel;
  final bool autofocus;
  final bool manageMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusTile(
            autofocus: autofocus,
            borderRadius: 18,
            borderWidth: 2.5,
            onTap: onTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: profile.color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 1,
                    ),
                  ),
                  child: ProfileAvatarFace(initials: profile.initials, token: profile.avatar, color: profile.color, fontSize: 40, radius: 18),
                ),
                if (profile.hasPin)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_rounded, size: 16),
                    ),
                  ),
                if (manageMode)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Icon(Icons.edit_rounded, color: AppColors.cyan),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            profile.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            profile.isKids ? kidsLabel : profile.maturity,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: profile.isKids ? AppColors.gold : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddCard extends StatelessWidget {
  const _AddCard({
    required this.onTap,
    required this.label,
    required this.subtitle,
  });
  final VoidCallback onTap;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusTile(
            borderRadius: 18,
            borderWidth: 2.5,
            onTap: onTap,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(Icons.add_rounded, size: 48, color: AppColors.cyan),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TvPinDialog extends StatefulWidget {
  const _TvPinDialog({required this.profileName, required this.copy});
  final String profileName;
  final AppCopy copy;

  @override
  State<_TvPinDialog> createState() => _TvPinDialogState();
}

class _TvPinDialogState extends State<_TvPinDialog> {
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
    final copy = widget.copy;
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
          title: Text('${copy.pinProtected} · ${widget.profileName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                copy.pinProtected,
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
                  for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '←', '0'])
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

class _AddProfileDialog extends StatefulWidget {
  const _AddProfileDialog({required this.copy});
  final AppCopy copy;

  @override
  State<_AddProfileDialog> createState() => _AddProfileDialogState();
}

class _AddProfileDialogState extends State<_AddProfileDialog> {
  final _controller = TextEditingController();
  bool _kids = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(copy.addProfile),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: copy.profileName,
              ),
              onSubmitted: (_) {
                if (_controller.text.trim().isEmpty) return;
                Navigator.pop(context, (name: _controller.text, kids: _kids));
              },
            ),
            const SizedBox(height: 12),
            FocusTile(
              onTap: () => setState(() => _kids = !_kids),
              child: Row(
                children: [
                  Icon(
                    _kids ? Icons.check_box : Icons.check_box_outline_blank,
                    color: AppColors.cyan,
                  ),
                  const SizedBox(width: 10),
                  Text(copy.kidsProfile),
                ],
              ),
            ),
          ],
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
            Navigator.pop(context, (name: _controller.text, kids: _kids));
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(copy.add, style: TextStyle(color: AppColors.cyan)),
          ),
        ),
      ],
    );
  }
}
