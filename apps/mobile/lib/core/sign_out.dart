import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account.dart';
import 'adult.dart';
import 'app_log.dart';
import 'demo_mode.dart';
import 'panels.dart';
import 'session_controller.dart';

/// Settings → Sign out: this device starts over at "Choose your panel".
/// Removes every saved panel (and its sealed credentials), signs out of the
/// app account, clears the old session tokens and leaves the demo. Each step
/// is independent, so one failing (e.g. offline) never blocks the others.
Future<void> signOutDevice(WidgetRef ref) async {
  AppLog.info('SignOut', 'device sign-out: panels + account + tokens');
  await clearDeviceState();
  try {
    await ref.read(sessionProvider.notifier).signOut();
  } catch (_) {}
  if (ref.read(demoModeProvider)) exitDemo(ref);
}

/// Panels (+ credentials) and the app account, without Riverpod (testable).
Future<void> clearDeviceState() async {
  final manager = PanelsService.manager;
  for (final c in [...manager.connections.value]) {
    try {
      await manager.remove(c.id);
    } catch (e) {
      AppLog.info('SignOut', 'panel remove failed: ${e.runtimeType}');
    }
  }
  try {
    await AccountService.signOut().timeout(const Duration(seconds: 3));
  } catch (_) {
    // Offline: the Supabase session is still cleared locally by signOut.
  }
  await AccountService.resetOffer();
  await AdultService.lock.clear(); // XPlayer adult PIN is per device owner
}
