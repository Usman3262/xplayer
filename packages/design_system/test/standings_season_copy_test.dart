import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('season label: start year / next year', () {
    expect(AppCopy.seasonLabel(2024), '2024/25');
    expect(AppCopy.seasonLabel(2099), '2099/00');
    expect(AppCopy.seasonLabel(2008), '2008/09');
  });

  test('plan notices name both seasons', () {
    for (final lang in [AppLang.en, AppLang.ar]) {
      final copy = AppCopy(lang);
      expect(copy.matchStandingsOlderSeason(2024, 2026), allOf(contains('2024/25'), contains('2026/27')));
      expect(copy.matchStandingsNotInPlan(2026), contains('2026/27'));
      expect(copy.matchSeason(2024), contains('2024/25'));
    }
  });
}
