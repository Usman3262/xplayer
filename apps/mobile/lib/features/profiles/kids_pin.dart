import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/session_models.dart';
import '../../core/session_controller.dart';

/// Kids PIN (server, one per account): asked when leaving a Kids profile for
/// a non-Kids profile. Shared by the profile picker and Edit profile.
Future<bool> openProfileWithKidsPin(
  BuildContext context,
  WidgetRef ref,
  ViewingProfile profile,
) async {
  final session = ref.read(sessionProvider.notifier);
  final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
  await session.refreshParentalPin();
  if (!context.mounted) return false;
  String? pin;
  if (session.needsParentalPin(profile.id)) {
    pin = await askKidsPin(context, copy);
    if (pin == null) return false;
  }
  try {
    await session.selectProfile(profile.id, pin: pin);
    return true;
  } catch (e) {
    if (context.mounted) {
      AppAlerts.toastFailure(context, title: copy.kidsPinTitle, message: kidsPinErrorText(e, copy));
    }
    return false;
  }
}

String kidsPinErrorText(Object e, AppCopy copy) {
  if (e is ApiException) {
    if (e.isPinInvalid) return copy.kidsPinWrong(e.pinAttemptsLeft);
    if (e.isPinLocked) return copy.kidsPinLocked;
    if (e.isPasswordInvalid) return copy.kidsPinWrongPassword;
    if (e.isNetwork) return copy.kidsPinOffline;
    return e.message;
  }
  if (e is ParentalPinRequired) return copy.kidsPinEnterHint;
  return AppAlerts.clean(e);
}

/// 4-digit PIN entry; returns the PIN or null when cancelled.
Future<String?> askKidsPin(BuildContext context, AppCopy copy) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _KidsPinSheet(copy: copy),
  );
}

class _KidsPinSheet extends StatefulWidget {
  const _KidsPinSheet({required this.copy});
  final AppCopy copy;

  @override
  State<_KidsPinSheet> createState() => _KidsPinSheetState();
}

class _KidsPinSheetState extends State<_KidsPinSheet> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _done() {
    if (_pin.text.length == 4) Navigator.pop(context, _pin.text);
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
          Text(copy.kidsPinEnter, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 6),
          Text(copy.kidsPinEnterHint, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 14),
          kidsPinField(_pin, autofocus: true, onFull: _done),
          const SizedBox(height: 12),
          PrimaryButton(label: copy.confirm, onPressed: _done),
        ],
      ),
    );
  }
}

/// Obscured 4-digit field.
Widget kidsPinField(
  TextEditingController controller, {
  bool autofocus = false,
  String? label,
  VoidCallback? onFull,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
      textAlign: TextAlign.center,
      onChanged: (v) {
        if (v.length == 4) onFull?.call();
      },
      style: const TextStyle(letterSpacing: 12, fontWeight: FontWeight.w800, fontSize: 22),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surfaceElevated,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    ),
  );
}
