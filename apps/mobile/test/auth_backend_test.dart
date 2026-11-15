import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:player_mobile/widgets/auth_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('auth back button with nothing to pop goes Home (no crash)', (t) async {
    final router = GoRouter(initialLocation: '/auth/register', routes: [
      GoRoute(
        path: '/auth/register',
        builder: (_, _) => const AuthScaffold(title: 'Join', subtitle: 'sub', child: SizedBox()),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('HOME')),
    ]);
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pump(const Duration(milliseconds: 500)); // auth screen animates forever
    await t.tap(find.byType(IconButton).first);
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('HOME'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('Supabase config is bundled in the app (plain flutter run works)', () async {
    final raw = jsonDecode(await rootBundle.loadString('assets/config/app_env.json')) as Map;
    expect('${raw['SUPABASE_URL']}', startsWith('https://'));
    expect('${raw['SUPABASE_PUBLISHABLE_KEY']}', isNotEmpty);
  }, skip: File('assets/config/app_env.json').existsSync() ? false : 'no local env (CI)');
}
