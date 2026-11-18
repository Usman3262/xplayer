import 'dart:async';

import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'backend.dart';
import 'panels.dart';

/// The signed-in user's library ↔ the account (Phase 8.1 / 8.2). Guests:
/// nothing leaves the phone. Signed in: one sync when the account appears
/// (the first one uploads the guest library), when the app comes back, and
/// 30 s after a change (several taps → one sync).
class LibraryCloud {
  LibraryCloud._();

  static LibrarySync? _sync;
  static Timer? _later;

  /// The library screens reload when titles came from the account.
  static VoidCallback? onPulled;

  static void init() {
    LibraryStore.onChanged = () => syncSoon();
    AccountService.user.addListener(() {
      if (AccountService.signedIn) unawaited(syncNow());
    });
    if (AccountService.signedIn) unawaited(syncNow());
  }

  static void syncSoon([Duration after = const Duration(seconds: 30)]) {
    if (!AccountService.signedIn) return;
    _later?.cancel();
    _later = Timer(after, () => unawaited(syncNow()));
  }

  static Future<void> syncNow() async {
    final client = Backend.client;
    final user = AccountService.user.value;
    final panel = PanelsService.manager.primary;
    if (client == null || user == null || panel == null) return;
    try {
      final key = await PanelsService.manager.panelKey(panel.id);
      if (key == null) return;
      final prefs = await SharedPreferences.getInstance();
      _sync ??= LibrarySync(
        store: LibraryStore(prefs),
        prefs: prefs,
        rpc: (fn, params) async => await client.rpc(fn, params: params),
      );
      final r = await _sync!.sync(key, user.id);
      if (r.pulled > 0) onPulled?.call();
    } catch (e) {
      // Offline / server busy: the library stays on the phone; next time.
      Diag.event('LIBRARY', 'account sync failed: ${e.runtimeType}');
    }
  }
}
