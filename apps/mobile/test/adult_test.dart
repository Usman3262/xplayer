import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_mobile/core/adult.dart';
import 'package:player_mobile/core/panels.dart';
import 'package:player_mobile/core/providers.dart';
import 'package:player_mobile/core/remote_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

final copy = AppCopy.ofLanguage('en');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CatalogStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AdultService.lock.lock();
    await AdultService.lock.clear();
    store = CatalogStore(CatalogDb(NativeDatabase.memory()));
    await store.saveCategories('p', CatalogKind.series, const [
      ProviderCategory(id: 's1', name: 'Drama'),
      ProviderCategory(id: 's2', name: 'XXX Night'),
    ], isAdult: (c) => AdultClassifier().isAdultName(c.name));
  });
  tearDown(() => store.close());

  Widget app(Widget child, {RemoteConfig? config, CatalogStore? withStore}) => ProviderScope(
        overrides: [
          panelUiLanguageProvider.overrideWithValue('en'),
          remoteConfigProvider.overrideWithValue(config ?? RemoteConfig.empty),
          catalogRepositoryProvider.overrideWithValue(
            PanelCatalogRepository(store: withStore ?? store, panelId: 'p', adapter: () async => null),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('Adult button shows only when the panel has 18+ series and the admin allows it', (t) async {
    await t.pumpWidget(app(const AdultButton(kind: MediaKind.series)));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('adult-button')), findsOneWidget);
    expect(find.text(copy.adultButton), findsOneWidget);

    await t.pumpWidget(app(const AdultButton(kind: MediaKind.movie))); // no adult movies
    await t.pumpAndSettle();
    expect(find.byKey(const Key('adult-button')), findsNothing);

    final off = RemoteConfig.tryParse({'version': 2, 'settings': {'content.adult_section': false}})!;
    await t.pumpWidget(app(const AdultButton(kind: MediaKind.series), config: off));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('adult-button')), findsNothing);
  });

  /// A button that runs the unlock flow and shows the result.
  Widget unlockHarness() => Consumer(builder: (context, ref, _) {
        return Column(children: [
          ElevatedButton(
            key: const Key('try'),
            onPressed: () async {
              final ok = await AdultService.unlock(context, ref);
              if (context.mounted && ok) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('UNLOCKED')));
              }
            },
            child: const Text('open'),
          ),
        ]);
      });

  Future<void> typePin(WidgetTester t, String pin) async {
    await t.enterText(find.byType(TextField).last, pin);
    await t.pumpAndSettle();
  }

  testWidgets('Xtream/M3U: first time creates an XPlayer PIN (twice), then asks for it', (t) async {
    await t.pumpWidget(app(unlockHarness()));
    await t.tap(find.byKey(const Key('try')));
    await t.pumpAndSettle();
    expect(find.text(copy.adultPinCreateTitle), findsOneWidget);
    await typePin(t, '2580');
    expect(find.text(copy.adultPinRepeat), findsOneWidget);
    await typePin(t, '2580');
    expect(find.text('UNLOCKED'), findsOneWidget);
    expect(AdultService.lock.isUnlocked, isTrue);
    expect(await AdultService.lock.hasAppPin(), isTrue);

    // Locked again (app went to the background) → asks for the PIN.
    AdultService.lock.lock();
    await t.tap(find.byKey(const Key('try')));
    await t.pumpAndSettle();
    expect(find.text(copy.adultPinTitle), findsOneWidget);
    await typePin(t, '1111');
    expect(find.text(copy.adultPinWrong), findsOneWidget);
  });

  testWidgets('create: PINs that differ are refused', (t) async {
    await t.pumpWidget(app(unlockHarness()));
    await t.tap(find.byKey(const Key('try')));
    await t.pumpAndSettle();
    await typePin(t, '1234');
    await typePin(t, '4321');
    expect(find.text(copy.adultPinMismatch), findsOneWidget);
    expect(await AdultService.lock.hasAppPin(), isFalse);
  });

  test('normal lists never contain 18+ (repository level)', () async {
    final repo = PanelCatalogRepository(store: store, panelId: 'p', adapter: () async => null);
    expect((await repo.getCategories(MediaKind.series)).map((c) => c.id), ['s1']);
    expect((await repo.adultView().getCategories(MediaKind.series)).map((c) => c.id), ['s2']);
  });
}
