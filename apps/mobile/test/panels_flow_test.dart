import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:player_mobile/core/panels.dart';
import 'package:player_mobile/core/remote_config.dart';
import 'package:player_mobile/features/connect/choose_panel_screen.dart';
import 'package:player_mobile/features/connect/panel_copy.dart';
import 'package:player_mobile/features/connect/panel_form_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PlainBox implements SecretBox {
  @override
  Future<String?> seal(String plain) async => 'sealed:$plain';
  @override
  Future<String?> open(String stored) async => stored.replaceFirst('sealed:', '');
}

class _FakeAdapter implements ProviderAdapter {
  _FakeAdapter(this.creds, this.result);
  final ProviderCredentials creds;
  final Future<ProviderAccount> Function() result;
  @override
  ProviderKind get kind => creds.kind;
  @override
  Future<ProviderAccount> authenticate() => result();
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final copy = AppCopy.ofLanguage('en');

void main() {
  late List<ProviderCredentials> logins;
  late Future<ProviderAccount> Function() loginResult;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    logins = [];
    loginResult = () async => const ProviderAccount(status: ConnectionStatus.active);
    PanelsService.useManager(ConnectionManager(
      store: ConnectionStore(secrets: _PlainBox()),
      createAdapter: (c) {
        logins.add(c);
        return _FakeAdapter(c, loginResult);
      },
    ));
  });

  Widget app(Widget screen, {RemoteConfig? config}) {
    final router = GoRouter(
      initialLocation: '/form',
      routes: [
        GoRoute(path: '/form', builder: (_, _) => screen),
        GoRoute(path: '/home', builder: (_, _) => const Text('HOME')),
        GoRoute(path: '/settings/panels', builder: (_, _) => const Text('PANELS')),
        GoRoute(path: '/connect', builder: (_, _) => const Text('CONNECT')),
        GoRoute(path: '/connect/:kind', builder: (_, s) => Text('FORM ${s.pathParameters['kind']}')),
      ],
    );
    return ProviderScope(
      overrides: [
        panelUiLanguageProvider.overrideWithValue('en'),
        remoteConfigProvider.overrideWithValue(config ?? RemoteConfig.empty),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> enter(WidgetTester t, int index, String text) async {
    await t.enterText(find.byType(TextField).at(index), text);
  }

  group('panel options from the admin config', () {
    test('built-in three when no config', () {
      final o = panelOptions(RemoteConfig.empty, copy);
      expect(o.map((x) => x.kind), [ProviderKind.xtream, ProviderKind.m3u, ProviderKind.stalker]);
    });

    test('admin order, labels, help, placeholders; switched-off and unknown types hidden', () {
      final c = RemoteConfig.tryParse({
        'version': 4,
        'onboarding': [
          {'key': 'stalker', 'label': 'MAG box', 'description': 'Portal + MAC', 'icon': 'tv',
           'fields': [{'key': 'portal', 'label': 'Portal', 'placeholder': 'http://my.portal/c/'}]},
          {'key': 'enigma2', 'label': 'Enigma'},
          {'key': 'xtream', 'label': 'Xtream', 'help': 'From your provider'},
        ],
      })!;
      final o = panelOptions(c, copy);
      expect(o.map((x) => x.kind), [ProviderKind.stalker, ProviderKind.xtream]);
      expect(o.first.title, 'MAG box');
      expect(o.first.icon, Icons.tv_rounded);
      expect(o.first.placeholders['portal'], 'http://my.portal/c/');
      expect(o.last.help, 'From your provider');
    });

    test('failure messages', () {
      expect(panelFailureText(const ProviderFailure(ProviderFailureKind.unauthorized), copy), copy.panelErrUnauthorized);
      expect(panelFailureText(const ProviderFailure(ProviderFailureKind.unsupported, 'HTTP 884'), copy), copy.panelErrUnsupported);
      expect(panelFailureText(const ProviderFailure(ProviderFailureKind.unsupported, 'stalker off'), copy), copy.panelErrTypeOff);
      expect(panelFailureText(const ProviderFailure(ProviderFailureKind.invalidInput, 'max panels 2'), copy, maxPanels: 2),
          copy.panelErrTooMany(2));
    });
  });

  testWidgets('choose screen lists the panel types and opens the form', (t) async {
    final router = GoRouter(initialLocation: '/connect', routes: [
      GoRoute(path: '/connect', builder: (_, _) => const ChoosePanelScreen()),
      GoRoute(path: '/connect/:kind', builder: (_, s) => Text('FORM ${s.pathParameters['kind']}')),
      GoRoute(path: '/home', builder: (_, _) => const Text('HOME')),
    ]);
    await t.pumpWidget(ProviderScope(
      overrides: [
        panelUiLanguageProvider.overrideWithValue('en'),
        remoteConfigProvider.overrideWithValue(RemoteConfig.empty),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await t.pumpAndSettle();
    expect(find.text(copy.choosePanelTitle), findsOneWidget);
    expect(find.text(copy.panelXtream), findsOneWidget);
    expect(find.text(copy.panelStalker), findsOneWidget);
    await t.tap(find.text(copy.panelM3u));
    await t.pumpAndSettle();
    expect(find.text('FORM m3u'), findsOneWidget);
  });

  testWidgets('empty Xtream form → field errors, no network call', (t) async {
    await t.pumpWidget(app(const PanelFormScreen(kind: ProviderKind.xtream)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('panel-connect')));
    await t.pumpAndSettle();
    expect(find.text(copy.errFieldRequired), findsNWidgets(3));
    expect(logins, isEmpty);
  });

  testWidgets('bad server link → URL error', (t) async {
    await t.pumpWidget(app(const PanelFormScreen(kind: ProviderKind.xtream)));
    await t.pumpAndSettle();
    await enter(t, 0, 'ftp://nope');
    await enter(t, 1, 'user');
    await enter(t, 2, 'pass');
    await t.tap(find.byKey(const Key('panel-connect')));
    await t.pumpAndSettle();
    expect(find.text(copy.errInvalidUrl), findsOneWidget);
    expect(logins, isEmpty);
  });

  testWidgets('connect works → saved and first panel goes Home', (t) async {
    await t.pumpWidget(app(const PanelFormScreen(kind: ProviderKind.xtream)));
    await t.pumpAndSettle();
    await enter(t, 0, 'panel.example:8080');
    await enter(t, 1, 'alice');
    await enter(t, 2, 'secret');
    await enter(t, 3, 'Living room');
    await t.tap(find.byKey(const Key('panel-connect')));
    await t.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    final saved = PanelsService.manager.connections.value.single;
    expect(saved.name, 'Living room');
    expect(saved.isPrimary, isTrue);
    expect((logins.single as XtreamCredentials).username, 'alice');
  });

  testWidgets('login refused → clear message, nothing saved, stays on the form', (t) async {
    loginResult = () async => throw const ProviderFailure(ProviderFailureKind.unauthorized);
    await t.pumpWidget(app(const PanelFormScreen(kind: ProviderKind.xtream)));
    await t.pumpAndSettle();
    await enter(t, 0, 'http://panel.example');
    await enter(t, 1, 'alice');
    await enter(t, 2, 'wrong');
    await t.tap(find.byKey(const Key('panel-connect')));
    await t.pumpAndSettle();
    expect(find.text(copy.panelErrUnauthorized), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(PanelsService.manager.connections.value, isEmpty);
  });

  testWidgets('Stalker form starts with this device MAC; bad MAC is caught locally', (t) async {
    await t.pumpWidget(app(const PanelFormScreen(kind: ProviderKind.stalker)));
    await t.pumpAndSettle();
    final mac = await PanelsService.manager.deviceMac();
    expect(find.text(mac), findsOneWidget);
    expect(find.text(copy.macDeviceHint), findsOneWidget);
    await enter(t, 0, 'http://portal.example/c/');
    await enter(t, 1, '00:1A:79:ZZ');
    await t.tap(find.byKey(const Key('panel-connect')));
    await t.pumpAndSettle();
    expect(find.text(copy.errInvalidMac), findsOneWidget);
    expect(logins, isEmpty);
  });
}
