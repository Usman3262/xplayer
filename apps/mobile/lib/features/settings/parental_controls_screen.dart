import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';
import '../profiles/kids_pin.dart';

/// Kids PIN (one per account, on the server): set up, change / forgot PIN,
/// turn off. Every change needs the account password.
class ParentalControlsScreen extends ConsumerStatefulWidget {
  const ParentalControlsScreen({super.key});

  @override
  ConsumerState<ParentalControlsScreen> createState() => _ParentalControlsScreenState();
}

class _ParentalControlsScreenState extends ConsumerState<ParentalControlsScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(sessionProvider.notifier).refreshParentalPin();
  }

  Future<void> _setPin(AppCopy copy) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _PinForm(copy: copy, remove: false),
    );
    if (saved == true && mounted) AppAlerts.toastSuccess(context, title: copy.kidsPinTitle, message: copy.kidsPinSaved);
  }

  Future<void> _remove(AppCopy copy) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _PinForm(copy: copy, remove: true),
    );
    if (done == true && mounted) AppAlerts.toastSuccess(context, title: copy.kidsPinTitle, message: copy.kidsPinRemoved);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final copy = AppCopy.ofLanguage(session.language);
    final on = session.parentalPinEnabled;
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(copy.parentalControls, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(on ? Icons.lock_rounded : Icons.lock_open_rounded, color: on ? AppColors.cyan : AppColors.textSecondary),
            title: Text(copy.kidsPinTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(copy.kidsPinHint),
            trailing: Text(on ? copy.kidsPinIsOn : copy.off, style: TextStyle(color: on ? AppColors.cyan : AppColors.textSecondary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          PrimaryButton(label: on ? copy.kidsPinChange : copy.kidsPinSetUp, onPressed: () => _setPin(copy)),
          if (on) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), side: BorderSide(color: AppColors.danger), foregroundColor: AppColors.danger),
              onPressed: () => _remove(copy),
              child: Text(copy.kidsPinRemove),
            ),
          ],
          const SizedBox(height: 16),
          Text(copy.kidsPinPasswordHint, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }
}

class _PinForm extends ConsumerStatefulWidget {
  const _PinForm({required this.copy, required this.remove});
  final AppCopy copy;
  final bool remove;

  @override
  ConsumerState<_PinForm> createState() => _PinFormState();
}

class _PinFormState extends ConsumerState<_PinForm> {
  final _pin = TextEditingController();
  final _repeat = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _repeat.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final copy = widget.copy;
    if (!widget.remove) {
      if (_pin.text.length != 4) return setState(() => _error = copy.kidsPinFormat);
      if (_pin.text != _repeat.text) return setState(() => _error = copy.kidsPinMismatch);
    }
    if (_password.text.isEmpty) return setState(() => _error = copy.kidsPinWrongPassword);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = ref.read(sessionProvider.notifier);
      if (widget.remove) {
        await s.removeParentalPin(password: _password.text);
      } else {
        await s.setParentalPin(pin: _pin.text, password: _password.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = kidsPinErrorText(e, copy));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.remove ? copy.kidsPinRemove : copy.kidsPinTitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 14),
          if (!widget.remove) ...[
            kidsPinField(_pin, autofocus: true, label: copy.kidsPinNew),
            const SizedBox(height: 10),
            kidsPinField(_repeat, label: copy.kidsPinRepeat),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: widget.remove,
            decoration: InputDecoration(
              labelText: copy.kidsPinAccountPassword,
              filled: true,
              fillColor: AppColors.surfaceElevated,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 14),
          PrimaryButton(label: _busy ? copy.loading : copy.confirm, onPressed: _busy ? null : _submit),
        ],
      ),
    );
  }
}
