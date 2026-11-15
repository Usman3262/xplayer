import 'dart:math';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_panel.dart';

/// Test "vault": reversible, and obviously not plain text.
class FakeBox implements SecretBox {
  bool broken = false;
  @override
  Future<String?> seal(String plain) async => 'sealed:${plain.split('').reversed.join()}';
  @override
  Future<String?> open(String stored) async {
    if (broken) return null;
    return stored.startsWith('sealed:') ? stored.substring(7).split('').reversed.join() : stored;
  }
}

/// Adapter whose login result each test controls.
class FakeAdapter implements ProviderAdapter {
  FakeAdapter(this.creds, this.onAuth);
  final ProviderCredentials creds;
  final Future<ProviderAccount> Function(ProviderCredentials) onAuth;
  bool disposed = false;
  @override
  ProviderKind get kind => creds.kind;
  @override
  Future<ProviderAccount> authenticate() => onAuth(creds);
  @override
  void dispose() => disposed = true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const neo = XtreamCredentials(server: 'http://neo.tv:8080', username: 'alice', password: 's3cret!');
const trial = XtreamCredentials(server: 'http://x.trial.ru', username: 'bob', password: 'pw');
const mag = StalkerCredentials(portal: 'http://portal.ru/c/', mac: '00:1A:79:F0:06:3B');

void main() {
  late FakeBox box;
  late Map<String, Future<ProviderAccount> Function(ProviderCredentials)> logins;
  late List<FakeAdapter> made;
  late RemoteConfig config;
  final now = DateTime.utc(2026, 11, 15, 12);

  Future<ProviderAccount> ok(ProviderCredentials _) async =>
      ProviderAccount(status: ConnectionStatus.active, expiresAt: DateTime.utc(2026, 12, 1), maxConnections: 1);

  ConnectionManager manager() => ConnectionManager(
        store: ConnectionStore(secrets: box, random: Random(7)),
        createAdapter: (c) {
          final a = FakeAdapter(c, logins[c.safeLabel] ?? ok);
          made.add(a);
          return a;
        },
        config: () => config,
        clock: () => now,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    box = FakeBox();
    logins = {};
    made = [];
    config = RemoteConfig.empty;
  });

  test('connect saves the panel; first one is primary; status/expiry from the panel', () async {
    final m = manager();
    final c = await m.connect(neo);
    expect(c.kind, ProviderKind.xtream);
    expect(c.name, 'neo.tv');
    expect(c.status, ConnectionStatus.active);
    expect(c.expiresAt, DateTime.utc(2026, 12, 1));
    expect(c.maxConnections, 1);
    expect(c.isPrimary, isTrue);
    expect(m.primary!.id, c.id);
    final second = await m.connect(trial, name: '  Trial line ');
    expect(second.isPrimary, isFalse);
    expect(second.name, 'Trial line');
    expect(m.connections.value.first.id, c.id); // primary listed first
  });

  test('credentials are stored sealed, never in the panel list', () async {
    final m = manager();
    final c = await m.connect(neo);
    final prefs = await SharedPreferences.getInstance();
    final everything = prefs.getKeys().map((k) => '${prefs.get(k)}').join('\n');
    expect(everything, isNot(contains('s3cret!')));
    expect(prefs.getString('xp.panels.v1'), isNot(contains('alice')));
    final back = await ConnectionStore(secrets: box).loadCredentials(c.id) as XtreamCredentials;
    expect(back.password, 's3cret!');
  });

  test('failed login saves nothing and the adapter is closed', () async {
    logins['neo.tv'] = (_) async => throw const ProviderFailure(ProviderFailureKind.unauthorized);
    final m = manager();
    await expectLater(m.connect(neo), throwsA(isA<ProviderFailure>()));
    expect(m.connections.value, isEmpty);
    expect(made.single.disposed, isTrue);
    expect((await SharedPreferences.getInstance()).getKeys().where((k) => k.startsWith('xp.panel.cred.')), isEmpty);
  });

  test('same panel again updates instead of duplicating (case-insensitive user)', () async {
    final m = manager();
    final a = await m.connect(neo);
    final b = await m.connect(const XtreamCredentials(server: 'neo.tv:8080', username: 'ALICE', password: 'new-pass'));
    expect(b.id, a.id);
    expect(m.connections.value, hasLength(1));
    expect((await ConnectionStore(secrets: box).loadCredentials(a.id) as XtreamCredentials).password, 'new-pass');
  });

  test('admin limits: panel count and switched-off panel types', () async {
    config = RemoteConfig.tryParse({
      'version': 3,
      'settings': {'providers.max_connections': 1},
      'onboarding': [
        {'key': 'xtream', 'label': 'Xtream'},
        {'key': 'm3u', 'label': 'M3U'},
      ],
    })!;
    final m = manager();
    expect(m.allowedKinds, {ProviderKind.xtream, ProviderKind.m3u});
    await m.connect(neo);
    await expectLater(m.connect(trial),
        throwsA(isA<ProviderFailure>().having((f) => f.kind, 'kind', ProviderFailureKind.invalidInput)));
    await expectLater(m.connect(mag),
        throwsA(isA<ProviderFailure>().having((f) => f.kind, 'kind', ProviderFailureKind.unsupported)));
    await expectLater(m.test(mag), throwsA(isA<ProviderFailure>()));
    // Same panel again is an update, not a new one → allowed at the limit.
    await m.connect(neo);
  });

  test('test() logs in without saving', () async {
    final m = manager();
    final acc = await m.test(trial);
    expect(acc.status, ConnectionStatus.active);
    expect(m.connections.value, isEmpty);
    expect(made.single.disposed, isTrue);
  });

  test('recheck: expired / unreachable / back to active; never throws', () async {
    final m = manager();
    final c = await m.connect(neo);
    logins['neo.tv'] = (_) async => throw const ProviderFailure(ProviderFailureKind.expired);
    m.dispose(); // force a fresh adapter with the new login behaviour
    var r = await m.recheck(c.id);
    expect(r!.status, ConnectionStatus.expired);
    expect(r.lastFailure, 'expired');
    m.dispose();
    logins['neo.tv'] = (_) async => throw const ProviderFailure(ProviderFailureKind.timeout);
    r = await m.recheck(c.id);
    expect(r!.status, ConnectionStatus.temporarilyUnavailable);
    m.dispose();
    logins['neo.tv'] = ok;
    r = await m.recheck(c.id);
    expect(r!.status, ConnectionStatus.active);
    expect(r.lastFailure, isNull);
    expect(r.lastCheckedAt, now);
  });

  test('recheck when the vault can no longer open the credentials', () async {
    final m = manager();
    final c = await m.connect(neo);
    m.dispose();
    box.broken = true;
    final r = await m.recheck(c.id);
    expect(r!.status, ConnectionStatus.invalidConfiguration);
  });

  test('disable primary → next panel becomes primary; enable re-checks', () async {
    final m = manager();
    final a = await m.connect(neo);
    final b = await m.connect(trial);
    await m.setEnabled(a.id, false);
    expect(m.primary!.id, b.id);
    final disabled = m.connections.value.firstWhere((x) => x.id == a.id);
    expect(disabled.status, ConnectionStatus.disabled);
    expect(disabled.isPrimary, isFalse);
    await m.setEnabled(a.id, true);
    expect(m.connections.value.firstWhere((x) => x.id == a.id).status, ConnectionStatus.active);
    expect(m.primary!.id, b.id); // enabling doesn't steal primary
    await m.setPrimary(a.id);
    expect(m.primary!.id, a.id);
    expect(m.connections.value.where((x) => x.isPrimary), hasLength(1));
  });

  test('remove deletes credentials; primary moves on; rename', () async {
    final m = manager();
    final a = await m.connect(neo);
    final b = await m.connect(trial);
    await m.rename(b.id, 'Backup');
    await m.remove(a.id);
    expect(m.connections.value.single.name, 'Backup');
    expect(m.primary!.id, b.id);
    expect(await ConnectionStore(secrets: box).loadCredentials(a.id), isNull);
  });

  test('survives restart; corrupt saved list starts clean', () async {
    final first = manager();
    final a = await first.connect(neo);
    await first.markSynced(a.id);
    final again = manager();
    final list = await again.load();
    expect(list.single.id, a.id);
    expect(list.single.lastSyncAt, now);
    expect(list.single.isPrimary, isTrue);

    SharedPreferences.setMockInitialValues({'xp.panels.v1': '{not json'});
    expect(await manager().load(), isEmpty);
    SharedPreferences.setMockInitialValues({'xp.panels.v1': '[{"id":"x","kind":"enigma"}, {"id":"y","kind":"m3u","status":"weird"}]'});
    final odd = await manager().load();
    expect(odd.single.id, 'y');
    expect(odd.single.status, ConnectionStatus.pending);
  });

  test('device MAC: MAG prefix, created once, user can set their own', () async {
    final m = manager();
    final mac = await m.deviceMac();
    expect(mac, matches(RegExp(r'^00:1A:79:[0-9A-F]{2}:[0-9A-F]{2}:[0-9A-F]{2}$')));
    expect(await manager().deviceMac(), mac); // same after restart
    expect(await m.setDeviceMac('00-1a-79-aa-bb-cc'), '00:1A:79:AA:BB:CC');
    expect(await m.deviceMac(), '00:1A:79:AA:BB:CC');
    expect(await m.setDeviceMac('nope'), isNull);
    expect(await m.deviceMac(), '00:1A:79:AA:BB:CC');
  });

  test('Stalker panel: same portal + MAC is the same panel', () async {
    final m = manager();
    final a = await m.connect(mag);
    final b = await m.connect(const StalkerCredentials(portal: 'portal.ru/c', mac: '001a79f0063b'));
    expect(b.id, a.id);
  });

  test('registerProviderAdapters registers all three protocols', () {
    registerProviderAdapters(RemoteConfig.empty);
    for (final k in ProviderKind.values) {
      expect(ProviderAdapterFactory.supports(k), isTrue, reason: k.name);
    }
  });

  test('removing a panel runs the cleanup hook (its local catalog is deleted)', () async {
    final removed = <String>[];
    final m = ConnectionManager(
      store: ConnectionStore(secrets: box, random: Random(3)),
      createAdapter: (c) => FakeAdapter(c, ok),
      onRemoved: (id) async => removed.add(id),
    );
    final a = await m.connect(neo);
    await m.remove(a.id);
    expect(removed, [a.id]);
  });

  test('M3U get.php link refused (884) → same line connected via Xtream', () async {
    logins['pro.example'] = (c) async {
      if (c is M3uCredentials) throw const ProviderFailure(ProviderFailureKind.unsupported, 'HTTP 884');
      return ok(c);
    };
    final m = manager();
    final c = await m.connect(const M3uCredentials(
        url: 'https://pro.example/get.php?username=usman&password=pw1&type=m3u_plus&output=ts'), name: 'My line');
    expect(c.kind, ProviderKind.xtream);
    expect(c.name, 'My line');
    final saved = await ConnectionStore(secrets: box).loadCredentials(c.id) as XtreamCredentials;
    expect(saved.server, 'https://pro.example');
    expect(saved.username, 'usman');
    expect(saved.password, 'pw1');
  });

  test('a normal M3U link that fails is not turned into Xtream', () async {
    logins['lists.example'] = (_) async => throw const ProviderFailure(ProviderFailureKind.unsupported);
    await expectLater(manager().connect(const M3uCredentials(url: 'http://lists.example/my.m3u')),
        throwsA(isA<ProviderFailure>()));
  });

  test('xtreamFromPlaylistUrl', () {
    final x = xtreamFromPlaylistUrl('pro.example:8080/get.php?username=a&password=b&type=m3u_plus')!;
    expect(x.server, 'http://pro.example:8080');
    expect(xtreamFromPlaylistUrl('http://h/sub/get.php?username=a&password=b')!.server, 'http://h/sub');
    expect(xtreamFromPlaylistUrl('http://h/get.php?username=a'), isNull);
    expect(xtreamFromPlaylistUrl('http://h/list.m3u?username=a&password=b'), isNull);
  });

  // LIVE (opt-in): the user's real get.php link → real adapters → real server.
  final liveTrial = livePanel();
  test('LIVE: user M3U link (884 on the panel) ends up connected via Xtream', () async {
    registerProviderAdapters(RemoteConfig.empty);
    final t = liveTrial!;
    final link = 'https://pro.business-cloud-8.ru/get.php?'
        'username=${Uri.encodeQueryComponent(t.username)}&password=${Uri.encodeQueryComponent(t.password)}&type=m3u_plus&output=ts';
    final m = ConnectionManager(store: ConnectionStore(secrets: box));
    final c = await m.connect(M3uCredentials(url: link));
    // ignore: avoid_print
    print('LIVE m3u→xtream: saved as ${c.kind.name}, status ${c.status.name}, expires ${c.expiresAt}');
    expect(c.kind, ProviderKind.xtream);
    expect(c.status, ConnectionStatus.active);
    final a = (await m.adapterFor(c.id))!;
    final cats = await a.liveCategories();
    expect(cats, isNotEmpty);
    m.dispose();
  }, skip: liveTrial == null ? liveSkip : false, timeout: const Timeout(Duration(minutes: 2)));
}
