import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/profiles/kids_pin.dart' show kidsPinField;
import 'panels.dart';
import 'providers.dart';
import 'remote_config.dart';
import '../widgets/catalog_browse_screen.dart';

/// Adult (18+) section: hidden everywhere; the "Adult 18+" button opens it
/// after the PIN (panel PIN on Stalker/MAG, an XPlayer PIN on Xtream/M3U).
/// Admin: `content.adult_section` (button on/off), `content.adult_keywords`.
class AdultService {
  AdultService._();

  static final lock = AdultPinLock();

  /// Asks for the PIN (or lets the user create one). True = unlocked.
  static Future<bool> unlock(BuildContext context, WidgetRef ref) async {
    if (lock.isUnlocked) return true;
    final copy = AppCopy.ofLanguage(ref.read(panelUiLanguageProvider));
    final panelPin = await _panelPin();
    final hasAppPin = await lock.hasAppPin();
    if (!context.mounted) return false;

    if (panelPin == null && !hasAppPin) {
      // Xtream / M3U: the panel doesn't share its PIN → create an XPlayer PIN.
      final first = await _askPin(context, copy.adultPinCreateTitle, copy.adultPinCreateHint);
      if (first == null || !context.mounted) return false;
      final again = await _askPin(context, copy.adultPinCreateTitle, copy.adultPinRepeat);
      if (again == null || !context.mounted) return false;
      if (first != again) {
        _toast(context, copy.adultPinMismatch);
        return false;
      }
      await lock.setAppPin(first);
      Diag.event('ADULT', 'XPlayer adult PIN created');
      if (context.mounted) _toast(context, copy.adultPinSet);
      return true;
    }

    final pin = await _askPin(context, copy.adultPinTitle, panelPin != null ? copy.adultPinPanelHint : copy.adultPinAppHint);
    if (pin == null) return false;
    final r = await lock.verify(pin, panelPin: panelPin);
    Diag.event('ADULT', 'unlock ${r.name} (${panelPin != null ? 'panel PIN' : 'XPlayer PIN'})');
    if (!context.mounted) return r == AdultPinResult.ok;
    if (r == AdultPinResult.wrong) _toast(context, copy.adultPinWrong);
    if (r == AdultPinResult.locked) _toast(context, copy.adultPinLocked);
    return r == AdultPinResult.ok;
  }

  /// The Stalker portal's parental PIN (logs in if needed); null otherwise.
  static Future<String?> _panelPin() async {
    final panel = PanelsService.manager.primary;
    if (panel == null) return null;
    final adapter = await PanelsService.manager.adapterFor(panel.id);
    if (adapter is! StalkerAdapter) return null;
    if (adapter.parentalPin == null) {
      try {
        await adapter.authenticate();
      } catch (_) {
        // Offline: no panel PIN → the XPlayer PIN is used.
      }
    }
    return adapter.parentalPin;
  }

  /// Replaces any message on screen (a stale one must not delay "Wrong PIN").
  static void _toast(BuildContext context, String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  static Future<String?> _askPin(BuildContext context, String title, String hint) => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        builder: (_) => _PinSheet(title: title, hint: hint),
      );
}

class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.title, required this.hint});
  final String title;
  final String hint;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
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
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.lock_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
            ],
          ),
          const SizedBox(height: 6),
          Text(widget.hint, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
          const SizedBox(height: 14),
          kidsPinField(_pin, autofocus: true, onFull: _done),
        ],
      ),
    );
  }
}

/// Admin switch for the Adult section (default on).
final adultSectionOnProvider = Provider<bool>(
  (ref) => ref.watch(remoteConfigProvider).boolSetting('content.adult_section', true),
);

/// Show the "Adult 18+" button for [kind]: section on + panel has 18+.
final adultAvailableProvider = FutureProvider.autoDispose.family<bool, MediaKind>((ref, kind) async {
  if (!ref.watch(adultSectionOnProvider)) return false;
  final repo = ref.watch(catalogRepositoryProvider);
  if (repo is! PanelCatalogRepository) return false;
  return repo.hasAdult(kind);
});

/// "Adult 18+" button (top of Series). Hidden when not available.
class AdultButton extends ConsumerWidget {
  const AdultButton({super.key, required this.kind});
  final MediaKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(adultAvailableProvider(kind)).valueOrNull ?? false;
    if (!available) return const SizedBox.shrink();
    final copy = AppCopy.ofLanguage(ref.watch(panelUiLanguageProvider));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: const Key('adult-button'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
            shape: const StadiumBorder(),
          ),
          onPressed: () async {
            if (await AdultService.unlock(context, ref) && context.mounted) {
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdultBrowseScreen(kind: kind)));
            }
          },
          icon: const Icon(Icons.lock_outline_rounded, size: 18),
          label: Text(copy.adultButton, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

/// The normal browse screen, fed by the 18+ only view of the catalog.
class AdultBrowseScreen extends ConsumerWidget {
  const AdultBrowseScreen({super.key, required this.kind});
  final MediaKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(catalogRepositoryProvider);
    if (repo is! PanelCatalogRepository || !AdultService.lock.isUnlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }
    final copy = AppCopy.ofLanguage(ref.watch(panelUiLanguageProvider));
    return ProviderScope(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo.adultView())],
      child: CatalogBrowseScreen(kind: kind, eyebrow: copy.adultButton, sectionKey: 'adult_${kind.name}'),
    );
  }
}
