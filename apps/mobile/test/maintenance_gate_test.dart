import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_mobile/core/remote_config.dart';
import 'package:player_mobile/widgets/maintenance_gate.dart';

RemoteConfig config({Map<String, dynamic>? maintenance}) => RemoteConfig.tryParse({
      'version': 3,
      'settings': {},
      'flags': {},
      if (maintenance != null) 'maintenance': maintenance,
    })!;

Widget app(RemoteConfig c) => ProviderScope(
      overrides: [remoteConfigProvider.overrideWithValue(c)],
      child: const MaterialApp(home: MaintenanceGate(child: Text('APP CONTENT'))),
    );

void main() {
  testWidgets('no maintenance → the app shows', (t) async {
    await t.pumpWidget(app(config()));
    expect(find.text('APP CONTENT'), findsOneWidget);
  });

  testWidgets('active maintenance → message instead of the app', (t) async {
    final until = DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String();
    await t.pumpWidget(app(config(maintenance: {'title': 'Back soon', 'message': 'Upgrading servers', 'to': until})));
    expect(find.text('APP CONTENT'), findsNothing);
    expect(find.text('Back soon'), findsOneWidget);
    expect(find.text('Upgrading servers'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('window already ended → the app shows again', (t) async {
    final past = DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String();
    await t.pumpWidget(app(config(maintenance: {'title': 'Old', 'message': 'x', 'to': past})));
    expect(find.text('APP CONTENT'), findsOneWidget);
  });
}
