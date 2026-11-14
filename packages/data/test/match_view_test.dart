import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

// Shapes as returned by App-Backend /v1/sports/* (PR #13: players,
// standings, leagues).
Map<String, dynamic> _fixture({int? home = 2, int? away = 1, bool live = true}) => {
      'id': 1001,
      'kickoff': '2026-10-20T20:00:00+03:00',
      'status': {'short': live ? '2H' : 'NS', 'long': 'Second Half', 'elapsed': 67, 'live': live, 'finished': false},
      'league': {'id': 307, 'name': 'Pro League'},
      'home': {'id': 1, 'name': 'Home FC'},
      'away': {'id': 2, 'name': 'Away FC'},
      'goals': {'home': home, 'away': away},
    };

Map<String, dynamic> _goal(int team, int minute, String player, {String detail = 'Normal Goal'}) => {
      'minute': minute,
      'team': {'id': team},
      'player': {'name': player},
      'type': 'goal',
      'detail': detail,
    };

void main() {
  test('key events are newest first with the running score', () {
    final m = MatchDetail.fromJson({
      'fixture': _fixture(),
      'events': [
        _goal(1, 12, 'A'),
        {'minute': 30, 'team': {'id': 2}, 'player': {'name': 'B'}, 'type': 'card', 'detail': 'Yellow Card'},
        _goal(2, 45, 'C'),
        _goal(1, 60, 'X', detail: 'Missed Penalty'),
        _goal(1, 63, 'D'),
      ],
    });
    final rows = m.keyEvents();
    expect(rows.map((r) => r.event.player), ['D', 'X', 'C', 'B', 'A']);
    expect(rows.first.score, '2-1');
    expect(rows[1].score, isNull, reason: 'missed penalty is not a goal');
    expect(rows[2].score, '1-1');
    expect(rows[2].home, isFalse);
    expect(rows.last.score, '1-0');
  });

  test('running score is hidden when events do not add up to the score', () {
    final m = MatchDetail.fromJson({
      'fixture': _fixture(home: 3, away: 1),
      'events': [_goal(1, 12, 'A')],
    });
    expect(m.keyEvents().single.score, isNull);
  });

  test('statPair needs both teams', () {
    final m = MatchDetail.fromJson({
      'fixture': _fixture(),
      'statistics': [
        {
          'team': {'id': 1},
          'stats': [
            {'type': 'Ball Possession', 'value': '58%'},
            {'type': 'Total Shots', 'value': 13},
          ],
        },
        {
          'team': {'id': 2},
          'stats': [
            {'type': 'Ball Possession', 'value': '42%'},
          ],
        },
      ],
    });
    expect(m.statPair('Ball Possession'), ('58%', '42%'));
    expect(m.statPair('Total Shots'), ('13', '0'));
    expect(m.statPair('expected_goals'), isNull);
    expect(matchStatNumber('58%'), 58);
    expect(matchStatNumber('1.42'), 1.42);
    expect(matchStatNumber(null), 0);
  });

  test('top player is the best rating of that team', () {
    final m = MatchDetail.fromJson({
      'fixture': _fixture(),
      'players': [
        {'teamId': 1, 'id': 10, 'name': 'A', 'rating': 7.1},
        {'teamId': 1, 'id': 11, 'name': 'B', 'rating': '8.8', 'goals': 1, 'keyPasses': 4},
        {'teamId': 2, 'id': 20, 'name': 'C', 'rating': 9.5},
        {'teamId': 1, 'id': 12, 'name': 'D'},
      ],
    });
    final top = m.topPlayer(1)!;
    expect(top.name, 'B');
    expect(top.rating, 8.8);
    expect(top.keyPasses, 4);
    expect(m.topPlayer(3), isNull);
  });

  test('league table parses groups and rows', () {
    final t = LeagueTable.fromJson({
      'league': {'id': 307, 'name': 'Pro League', 'season': 2026},
      'groups': [
        [
          {'rank': 1, 'team': {'id': 1, 'name': 'Home FC'}, 'points': 22, 'goalsDiff': 14, 'played': 8, 'win': 7, 'draw': 1, 'lose': 0, 'form': 'WWDWW'},
          {'rank': 2, 'team': {'id': 2, 'name': 'Away FC'}, 'points': 20, 'goalsDiff': -3, 'played': 8},
        ],
      ],
    });
    expect(t.league.id, 307);
    expect(t.groups.single.length, 2);
    expect(t.groups.single.first.form, 'WWDWW');
    expect(t.groups.single.last.goalsDiff, -3);
  });

  test('today and tomorrow follow the Riyadh calendar', () {
    // 19:44 UTC = 22:44 Riyadh = 00:44 Pakistan next day: still the 20th.
    expect(matchTodayTomorrow(DateTime.utc(2026, 10, 20, 19, 44)), ['2026-10-20', '2026-10-21']);
    // 21:30 UTC = 00:30 Riyadh: the 21st has started.
    expect(matchTodayTomorrow(DateTime.utc(2026, 10, 20, 21, 30)), ['2026-10-21', '2026-10-22']);
    expect(matchTodayTomorrow(DateTime.utc(2026, 12, 31, 20, 59)), ['2026-12-31', '2027-01-01']);
    expect(matchSportsDay(DateTime.utc(2026, 10, 20, 21, 0)), '2026-10-21');
  });

  test('yesterday, today, tomorrow', () {
    expect(matchThreeDays(DateTime.utc(2026, 10, 21, 1, 0)), ['2026-10-20', '2026-10-21', '2026-10-22']);
    expect(matchThreeDays(DateTime.utc(2026, 1, 1, 0, 0)), ['2025-12-31', '2026-01-01', '2026-01-02']);
  });
}
