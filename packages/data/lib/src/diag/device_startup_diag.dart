import 'package:flutter/foundation.dart';

import '../device/device_capabilities_store.dart';
import '../remote/api_config.dart';
import 'diag.dart';
import 'network_diag.dart';

/// Emits `[DEV]` at app start via [DeviceCapabilitiesStore] (brief §9.2).
Future<void> logDeviceStartupDiag() async {
  if (!DiagConfig.isOn) return;
  try {
    final caps = await DeviceCapabilitiesStore.instance.ensureLoaded();
    final mode = kReleaseMode
        ? 'release'
        : (kProfileMode ? 'profile' : 'debug');
    Diag.dev('${caps.diagLine} build=$mode');
    final apiHost = Uri.tryParse(ApiConfig.fromEnvironment().baseUrl)?.host;
    Diag.net('ctx=startup apiHost=${apiHost ?? "?"} (no tokens logged)');
    await logNetworkDiagnostics(context: 'startup');
  } catch (e, st) {
    Diag.err('DEV startup failed', e, st);
  }
}
