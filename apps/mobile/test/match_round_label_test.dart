import 'package:player_mobile/features/sports/match_centre_adapters.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

// Client 23 Oct check: in Arabic, match cards still showed the provider's
// English round ("LEAGUE STAGE - 3", "REGULAR SEASON - 11").
void main() {
  final ar = AppCopy.ofLanguage('ar');
  final en = AppCopy.ofLanguage('en');

  test('Arabic rounds', () {
    expect(mpRound(ar, 'Regular Season - 11'), 'الجولة 11');
    expect(mpRound(ar, 'League Stage - 3'), 'مرحلة الدوري - الجولة 3');
    expect(mpRound(ar, 'Quarter-finals'), 'ربع النهائي');
  });

  test('English and unknown rounds keep the provider text', () {
    expect(mpRound(en, 'League Stage - 3'), 'League Stage - 3');
    expect(mpRound(ar, '3rd Qualifying Round'), '3rd Qualifying Round');
    expect(mpRound(ar, null), isNull);
  });
}
