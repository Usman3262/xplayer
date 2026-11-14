import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('isProviderAdOrHeaderChannel', () {
    test('drops ##### headers and empty junk', () {
      expect(isProviderAdOrHeaderChannel('##### SPORTS #####'), isTrue);
      expect(isProviderAdOrHeaderChannel('###'), isTrue);
      expect(isProviderAdOrHeaderChannel('   '), isTrue);
    });

    test('drops server ad / promo marketing rows', () {
      expect(isProviderAdOrHeaderChannel('SERVER AD'), isTrue);
      expect(isProviderAdOrHeaderChannel('Promo Channel'), isTrue);
      expect(isProviderAdOrHeaderChannel('Advertisement'), isTrue);
    });

    test('drops standalone 8K promo labels', () {
      expect(isProviderAdOrHeaderChannel('8K'), isTrue);
      expect(isProviderAdOrHeaderChannel('8K PACKAGE'), isTrue);
      expect(isProviderAdOrHeaderChannel('[8K]'), isTrue);
    });

    test('keeps real channel names', () {
      expect(isProviderAdOrHeaderChannel('BeIN Sports 1 HD'), isFalse);
      expect(isProviderAdOrHeaderChannel('National Geographic 4K'), isFalse);
      expect(isProviderAdOrHeaderChannel('BBC News'), isFalse);
    });
  });

  group('cleanDisplayName branding strip', () {
    test('strips trailing BE and mid 8K and soccer glyph', () {
      expect(cleanDisplayName('SOLO SPORT BE'), 'SOLO SPORT');
      expect(cleanDisplayName('BEIN SPORTS 8K SD'), 'BEIN SPORTS SD');
      // Client 16 Oct #10: provider "RAW" tags are removed too.
      expect(cleanDisplayName('ALWAN SPORT ⚽ RAW'), 'ALWAN SPORT');
    });
  });
}
