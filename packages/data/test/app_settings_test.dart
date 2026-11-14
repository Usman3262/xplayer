import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

// Client 27 Oct: screen protection is on unless the owner turns it off.
void main() {
  test('defaults keep protection on and lineups shown', () {
    const d = AppSettingsDto();
    expect(d.screenProtection, isTrue);
    expect(d.lineups, isTrue);
  });

  test('missing or wrong values fall back to the safe defaults', () {
    final d = AppSettingsDto.fromJson({'screenProtection': 'no', 'lineups': null});
    expect(d.screenProtection, isTrue);
    expect(d.lineups, isTrue);
  });

  test('owner choices are read', () {
    final d = AppSettingsDto.fromJson({'screenProtection': false, 'lineups': false});
    expect(d.screenProtection, isFalse);
    expect(d.lineups, isFalse);
    expect(AppSettingsDto.fromJson(d.toJson()), d);
  });
}
