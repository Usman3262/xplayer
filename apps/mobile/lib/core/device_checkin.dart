import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'backend.dart';
import 'panels.dart';
import 'remote_logs.dart';

/// Shows messages from outside a screen (e.g. "this device was signed out").
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Phase 8.3: a signed-in device tells the account it is here (model,
/// platform, app version, panel type — never panel logins). Sent after an
/// explicit sign-in and on app start / resume at most every 6 h. When the
/// user (Settings) or an admin signed this device out, it signs out here.
class DeviceCheckin {
  DeviceCheckin._();

  static const _lastKey = 'xp.device_checkin_at';
  static const every = Duration(hours: 6);

  static void init() {
    AccountService.onSignedIn = () => unawaited(run(signedIn: true));
    unawaited(run());
  }

  static Future<void> run({bool signedIn = false}) async {
    final client = Backend.client;
    final id = RemoteLogs.deviceId;
    if (client == null || id == null || !AccountService.signedIn) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_lastKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!signedIn && now - last < every.inMilliseconds) return;
      final caps = DeviceCapabilitiesStore.instance.current;
      final r = await client.rpc('device_checkin', params: {
        'p_device': {
          'id': id,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          if (caps != null) 'model': '${caps.brand} ${caps.model}'.trim(),
          if (caps != null) 'os': caps.release,
          'app': RemoteLogs.appVersion,
          'panel': ?PanelsService.manager.primary?.kind.name,
        },
        'p_signed_in': signedIn,
      });
      await prefs.setInt(_lastKey, now);
      if (r is Map && r['revoked'] == true) {
        Diag.event('ACCOUNT', 'this device was signed out from the account (Settings / admin): signing out here');
        await AccountService.signOut();
        final ctx = appMessengerKey.currentContext;
        if (ctx != null) {
          appMessengerKey.currentState
            ?..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              duration: const Duration(seconds: 8),
              content: Text(AppCopy.ofContext(ctx).accountDeviceSignedOut),
            ));
        }
      }
    } catch (e) {
      // Offline: try again next time; the account stays signed in.
      Diag.event('ACCOUNT', 'device check-in failed: ${e.runtimeType}');
    }
  }
}
