import 'package:data/data.dart' show AppSettingsDto;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings_controller.dart';

const _channelName = 'app/screen_secure';

/// Screen capture protection follows the Control Panel (client 27 Oct): on by
/// default, only the owner changes it; customers no longer get a switch (their
/// old personal choice is ignored).
final screenRecordProtectProvider =
    StateNotifierProvider<ScreenRecordProtectController, bool>((ref) {
  final controller =
      ScreenRecordProtectController(ref.read(appSettingsProvider).screenProtection);
  ref.listen<AppSettingsDto>(appSettingsProvider, (_, next) => controller.follow(next.screenProtection));
  return controller;
});

class ScreenRecordProtectController extends StateNotifier<bool> {
  ScreenRecordProtectController(bool initial) : super(initial) {
    apply(initial);
  }

  /// New value from the server.
  void follow(bool enabled) {
    if (!mounted) return;
    state = enabled;
    apply(enabled);
  }

  static const _channel = MethodChannel(_channelName);

  /// Android TV: FLAG_SECURE blacks / blocks capture of the window.
  Future<void> apply(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } catch (e) {
      debugPrint('[ScreenProtect][TV] apply($enabled) failed: $e');
    }
  }
}

/// Re-applies FLAG_SECURE on resume (OEM focus quirks).
class ScreenRecordGuard extends ConsumerStatefulWidget {
  const ScreenRecordGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ScreenRecordGuard> createState() => _ScreenRecordGuardState();
}

class _ScreenRecordGuardState extends ConsumerState<ScreenRecordGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final on = ref.read(screenRecordProtectProvider);
      ref.read(screenRecordProtectProvider.notifier).apply(on);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appSettingsProvider.notifier).refresh();
      final on = ref.read(screenRecordProtectProvider);
      ref.read(screenRecordProtectProvider.notifier).apply(on);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Touch provider so controller boots with the tree.
    ref.watch(screenRecordProtectProvider);
    return widget.child;
  }
}
