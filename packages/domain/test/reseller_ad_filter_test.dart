import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('reseller adverts placed as channels', () {
    const ads = [
      'للاشتراك واتساب 0532161975',
      'ماجد اشتراك جوال او تلفاز',
      'WhatsApp +966 53 216 1975',
      'Telegram @iptvking',
      'www.best-iptv.com',
      'https://t.me/serverpanel',
      'SUBSCRIBE NOW 8K SERVER',
      'Renew your subscription',
      'IPTV SERVER CODE',
      'تجديد الاشتراك',
      'سيرفر 8K',
      'للتواصل 0555 123 456',
      '+971 50 123 4567',
    ];
    const channels = [
      'MBC 1 RAW',
      'MBC 1 HD',
      'beIN SPORTS 1 HD',
      'Al Jazeera',
      'قناة الجزيرة',
      'روتانا سينما',
      'SSC 1 HD',
      'Sky News Arabia',
      'National Geographic 4K',
      'Dubai Sports 2',
      'MBC 1 USA RAW',
    ];
    for (final n in ads) {
      test('drops "$n"', () => expect(isProviderAdOrHeaderChannel(n), isTrue));
    }
    for (final n in channels) {
      test('keeps "$n"', () => expect(isProviderAdOrHeaderChannel(n), isFalse));
    }
  });
}
