import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> cfg(int v, {String primary = '#E11D2E', bool sports = true}) => {
      'version': v,
      'unchanged': false,
      'settings': {'auth.mode': 'optional', 'config.refresh_interval_s': 120},
      'flags': {'sports': sports},
      'theme': {'primary': primary},
      'home': {'sections': [], 'banners': [], 'top10': []},
      'onboarding': [],
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  RemoteConfigRepository repo(ConfigFetcher f) =>
      RemoteConfigRepository(platform: 'android', appVersion: '1.0.0', fetch: f, timeout: const Duration(milliseconds: 300));

  test('fresh install: empty, then server config applied and cached', () async {
    final r = repo((_) async => cfg(5));
    expect((await r.loadCached()).version, 0);
    expect(await r.refresh(), isTrue);
    expect(r.current.value.version, 5);
    expect(r.current.value.theme['primary'], '#E11D2E');

    // Next start: cache applies instantly, no network.
    final r2 = repo((_) async => throw StateError('offline'));
    expect((await r2.loadCached()).version, 5);
  });

  test('sends known version; "unchanged" keeps the current config', () async {
    Map<String, dynamic>? sent;
    var call = 0;
    final r = repo((p) async {
      call++;
      sent = p;
      return call == 1 ? cfg(7) : {'version': 7, 'unchanged': true};
    });
    await r.refresh();
    expect(await r.refresh(), isFalse);
    expect(sent!['p_known_version'], 7);
    expect(sent!['p_platform'], 'android');
    expect(r.current.value.version, 7);
  });

  test('invalid reply, network error and timeout keep the last valid config', () async {
    var mode = 'ok';
    final r = repo((_) async {
      switch (mode) {
        case 'junk':
          return 'not json object';
        case 'error':
          throw const SocketException('down');
        case 'slow':
          await Future<void>.delayed(const Duration(seconds: 2));
          return cfg(99);
        default:
          return cfg(3);
      }
    });
    await r.refresh();
    for (final m in ['junk', 'error', 'slow']) {
      mode = m;
      expect(await r.refresh(), isFalse, reason: m);
      expect(r.current.value.version, 3, reason: m);
    }
  });

  test('never goes backwards to an older version', () async {
    var v = 10;
    final r = repo((_) async => cfg(v));
    await r.refresh();
    v = 8;
    expect(await r.refresh(), isFalse);
    expect(r.current.value.version, 10);
  });

  test('concurrent refresh calls share one request', () async {
    var calls = 0;
    final gate = Completer<void>();
    final r = repo((_) async {
      calls++;
      await gate.future;
      return cfg(2);
    });
    final a = r.refresh();
    final b = r.refresh();
    gate.complete();
    await Future.wait([a, b]);
    expect(calls, 1);
  });

  test('a new version replaces flags/theme (admin turned sports off)', () async {
    var reply = cfg(1);
    final r = repo((_) async => reply);
    await r.refresh();
    expect(r.current.value.isEnabled('sports'), isTrue);
    reply = cfg(2, sports: false, primary: '#3B82F6');
    expect(await r.refresh(), isTrue);
    expect(r.current.value.isEnabled('sports'), isFalse);
    expect(r.current.value.theme['primary'], '#3B82F6');
  });

  // Real server through the same repository (skipped when env/app.json is absent).
  final env = File('../../env/app.json');
  test('LIVE: real get_app_config through the repository', () async {
    final e = jsonDecode(env.readAsStringSync()) as Map<String, dynamic>;
    final url = e['SUPABASE_URL'] as String;
    final key = e['SUPABASE_PUBLISHABLE_KEY'] as String;
    Future<Object?> fetch(Map<String, dynamic> p) async {
      final res = await http.post(
        Uri.parse('$url/rest/v1/rpc/get_app_config'),
        headers: {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/json'},
        body: jsonEncode(p),
      );
      return jsonDecode(res.body);
    }

    final r = RemoteConfigRepository(platform: 'tv', appVersion: '1.0.0', fetch: fetch);
    expect(await r.refresh(), isTrue);
    final c = r.current.value;
    expect(c.version, greaterThan(0));
    expect(c.theme['primary'], isNotNull);
    expect(c.panelTypes.map((p) => p.key), containsAll(['xtream', 'm3u', 'stalker']));
    expect(c.home.sections, isNotEmpty);
    expect(c.authMode, AuthMode.optional);
    // Second call with the known version: server answers "unchanged".
    expect(await r.refresh(), isFalse);
    expect(r.current.value.version, c.version);
  }, skip: env.existsSync() ? false : 'env/app.json not present', timeout: const Timeout(Duration(seconds: 30)));
}
