import 'dart:convert';
import 'dart:io';

import 'package:data/data.dart';

/// Credentials for opt-in live panel tests. Nothing here is committed:
/// `env/test_panels.json` and `neo-channel-tester.html` are git-ignored.
///
///   XPLAYER_LIVE_TESTS=1                 turn live tests on
///   XPLAYER_LIVE_PANEL=trial | neo       which line (default: trial)
///
/// Keep live runs rare: panels rate-limit and IP-block busy clients
/// (Neo blocked this PC on 2026-11-15 after repeated get.php calls).
XtreamCredentials? livePanel() {
  if (Platform.environment['XPLAYER_LIVE_TESTS'] != '1') return null;
  final which = Platform.environment['XPLAYER_LIVE_PANEL'] ?? 'trial';
  if (which == 'neo') {
    final f = File('../../neo-channel-tester.html');
    if (!f.existsSync()) return null;
    final html = f.readAsStringSync();
    String v(String id) => RegExp('id="$id" value="([^"]*)"').firstMatch(html)!.group(1)!;
    return XtreamCredentials(server: v('host'), username: v('username'), password: v('password'));
  }
  final f = File('../../env/test_panels.json');
  if (!f.existsSync()) return null;
  final p = (jsonDecode(f.readAsStringSync()) as Map)[which];
  if (p is! Map) return null;
  return XtreamCredentials(
    server: '${p['server']}',
    username: '${p['username']}',
    password: '${p['password']}',
  );
}

const liveSkip = 'live panel test: set XPLAYER_LIVE_TESTS=1 (+ XPLAYER_LIVE_PANEL=trial|neo)';

/// Stalker line from `env/test_panels.json` → "stalker": {portal, mac}.
StalkerCredentials? liveStalker() {
  if (Platform.environment['XPLAYER_LIVE_TESTS'] != '1') return null;
  final f = File('../../env/test_panels.json');
  if (!f.existsSync()) return null;
  final p = (jsonDecode(f.readAsStringSync()) as Map)['stalker'];
  if (p is! Map || '${p['portal']}'.isEmpty) return null;
  return StalkerCredentials(portal: '${p['portal']}', mac: '${p['mac']}');
}
