import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lineups switch in the Control Panel: the match answer says
/// `lineupsHidden: true`, and the apps hide the tab from that answer.
void main() {
  Map<String, dynamic> match({bool? hidden}) => {
        'fixture': {
          'id': 1,
          'status': {'short': 'NS'},
          'league': {'id': 307, 'name': 'Pro League'},
          'home': {'id': 1, 'name': 'A'},
          'away': {'id': 2, 'name': 'B'},
        },
        'lineups': <Object>[],
        if (hidden != null) 'lineupsHidden': hidden,
      };

  test('switched off in the panel → hidden', () {
    expect(MatchDetail.fromJson(match(hidden: true)).lineupsHidden, isTrue);
  });
  test('switched on (no flag) → shown', () {
    expect(MatchDetail.fromJson(match()).lineupsHidden, isFalse);
    expect(MatchDetail.fromJson(match(hidden: false)).lineupsHidden, isFalse);
  });
}
