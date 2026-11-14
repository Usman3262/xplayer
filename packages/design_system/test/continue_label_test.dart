import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = AppCopy.ofLanguage('en');

  test('movie shows watched / total minutes when progress is known', () {
    expect(
      en.continueLabel(
        positionSec: 62 * 60,
        title: 'Saqr & Kanarya',
        series: false,
        progress: 62 / 110,
      ),
      '62 / 110 min',
    );
  });

  test('series keeps the episode tag', () {
    expect(
      en.continueLabel(
        positionSec: 20 * 60,
        title: 'Show S1 E3',
        series: true,
        progress: 0.5,
      ),
      'S1 E3 · 20 / 40 min',
    );
  });

  test('no progress falls back to "Reached"', () {
    expect(
      en.continueLabel(positionSec: 300, title: 'X', series: false),
      'Reached 5 min',
    );
  });

  test('under a minute is "Just started"', () {
    expect(
      en.continueLabel(
        positionSec: 20,
        title: 'X',
        series: false,
        progress: 0.01,
      ),
      'Just started',
    );
  });
}
