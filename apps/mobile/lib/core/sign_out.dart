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
  // Read everything from `ref` first: removing the panels sends the router
  // to "Choose your panel", which disposes the Settings screen (and its ref)
  // while this is still running (device crash 2026-11-15).
  final session = ref.read(sessionProvider.notifier);
  final demo = ref.read(demoModeProvider.notifier);
  if (demo.state) exitDemo(ref);
  await clearDeviceState();
  try {
    await session.signOut();
  } catch (_) {}
  demo.state = false;
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
  AdultService.hide();
  await AdultService.lock.clear(); // XPlayer adult PIN is per device owner
}
