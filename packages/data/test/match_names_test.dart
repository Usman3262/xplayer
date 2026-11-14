import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client 22 Oct: team / league names in Arabic from our server (stored
/// once per provider id), English otherwise.
void main() {
  final f = MatchFixture.fromJson({
    'id': 1,
    'status': {'short': 'FT'},
    'league': {'id': 307, 'name': 'Pro League', 'nameAr': 'دوري روشن السعودي'},
    'home': {'id': 2944, 'name': 'Al-Ettifaq', 'nameAr': 'الاتفاق'},
    'away': {'id': 99, 'name': 'Unknown Town', 'nameAr': null},
  });

  test('Arabic name when the app is Arabic', () {
    expect(f.home.nameFor('ar'), 'الاتفاق');
    expect(f.league.nameFor('ar'), 'دوري روشن السعودي');
  });
  test('English name otherwise', () {
    expect(f.home.nameFor('en'), 'Al-Ettifaq');
    expect(f.league.nameFor('en'), 'Pro League');
  });
  test('no Arabic name yet → English, never empty', () {
    expect(f.away.nameFor('ar'), 'Unknown Town');
  });
  test('old server without nameAr still works', () {
    final t = MatchTeam.fromJson({'id': 5, 'name': 'Como'});
    expect(t.nameFor('ar'), 'Como');
  });
}
