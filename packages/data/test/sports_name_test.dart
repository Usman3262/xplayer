import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sports categories are sports; other beIN packages are not', () {
    for (final yes in [
      'BEIN SPORTS F',
      'beIN SPORTS 8K 3840p',
      'ALWAN SPORT RAW',
      'SHASHA SPORT F',
      'UEFA Champions League',
      'احدث المباريات ⚽',
      'قنوات رياضية',
      'كرة القدم',
    ]) {
      expect(RemoteCatalogRepository.isSportsName(yes), isTrue, reason: yes);
    }
    for (final no in [
      'BEIN ENTERTAINMENT 4K الترفيهية',
      'beIN MOVIES',
      'BEIN OD Platinum حسب الطلب',
      'MBC',
      'News',
    ]) {
      expect(RemoteCatalogRepository.isSportsName(no), isFalse, reason: no);
    }
  });
}
