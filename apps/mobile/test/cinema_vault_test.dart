import 'package:player_mobile/features/browse/cinema_vault_screen.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

// Client 23 Oct round 3 #17: the Vault shows only real 4K movies / series.
void main() {
  MediaItem item(String title, MediaKind kind, [List<String> badges = const []]) =>
      MediaItem(id: title, title: title, kind: kind, badges: badges);

  test('4K copies only', () {
    expect(isVaultTitle(item('4K-AR: صقر وكناريا', MediaKind.movie), inUhdPackage: false), isTrue);
    expect(isVaultTitle(item('Rudy', MediaKind.movie, ['4K']), inUhdPackage: false), isTrue);
    expect(isVaultTitle(item('AR: صقر وكناريا', MediaKind.movie), inUhdPackage: false), isFalse);
    expect(isVaultTitle(item('Show HD', MediaKind.series, ['HD']), inUhdPackage: false), isFalse);
  });

  test('anything in a 4K package counts; channels never', () {
    expect(isVaultTitle(item('Tangled', MediaKind.movie), inUhdPackage: true), isTrue);
    expect(isVaultTitle(item('MBC 4K', MediaKind.live, ['4K']), inUhdPackage: true), isFalse);
  });
}
