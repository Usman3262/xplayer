import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('provider kids categories are recognised', () {
    for (final n in ['KIDS أطفال', 'Kids LQ أطفال', 'مسلسلات كرتون زمان', 'MBC TOON', 'Cartoon Network', 'Baby TV']) {
      expect(KidsPanelCategories.looksKids(n), isTrue, reason: n);
    }
  });
  test('other categories are not', () {
    for (final n in ['MBC 4K', 'NEWS الأخبار', 'EGYPT مصر', 'beIN SPORTS']) {
      expect(KidsPanelCategories.looksKids(n), isFalse, reason: n);
    }
  });
}
