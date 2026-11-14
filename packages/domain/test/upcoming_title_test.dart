import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client 4 Nov (as on LG): titles not released yet show "Soon".
void main() {
  test('Arabic "soon" in its spellings, tatweel ignored', () {
    expect(isUpcomingTitle('AR KH: (قــريباً) جزيرة الضباب'), isTrue);
    expect(isUpcomingTitle('مسلسل قريبا'), isTrue);
    expect(isUpcomingTitle('Film (Coming Soon)'), isTrue);
  });
  test('ordinary titles and words starting with قريب are not', () {
    expect(isUpcomingTitle('AR: جزيرة الضباب'), isFalse);
    expect(isUpcomingTitle('قريبة من القلب'), isFalse);
    expect(isUpcomingTitle(null), isFalse);
  });
}
