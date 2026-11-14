import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

// Shapes as returned by App-Backend /v1/sports/* (Docs/SPORTS_MATCH_CENTRE_API.md).
final _fixture = <String, dynamic>{
  'id': 1001,
  'kickoff': '2026-10-20T20:00:00+03:00',
  'status': {'short': '2H', 'long': 'Second Half', 'elapsed': 67, 'live': true, 'finished': false},
  'league': {'id': 307, 'name': 'Pro League', 'country': 'Saudi-Arabia', 'logo': 'l.png', 'round': 'Regular Season - 8'},
  'venue': {'name': 'King Fahd Stadium', 'city': 'Riyadh'},
  'referee': 'Ref',
  'home': {'id': 2932, 'name': 'Al-Hilal', 'logo': 'h.png', 'winner': null},
  'away': {'id': 2939, 'name': 'Al-Nassr', 'logo': 'a.png', 'winner': null},
  'goals': {'home': 2, 'away': 1},
};

void main() {
  test('fixture parses teams, score, live status', () {
    final f = MatchFixture.fromJson(_fixture);
    expect(f.id, 1001);
    expect(f.home.name, 'Al-Hilal');
    expect(f.hasScore, isTrue);
    expect(f.homeGoals, 2);
    expect(f.status.live, isTrue);
    expect(f.status.elapsed, 67);
    expect(f.league.round, 'Regular Season - 8');
    expect(f.kickoff, isNotNull);
  });

  test('not started fixture has no score', () {
    final f = MatchFixture.fromJson({
      ..._fixture,
      'status': {'short': 'NS', 'live': false, 'finished': false},
      'goals': {'home': null, 'away': null},
    });
    expect(f.hasScore, isFalse);
    expect(f.status.notStarted, isTrue);
  });

  test('match detail: lineups, events, statistics', () {
    final m = MatchDetail.fromJson({
      'fixture': _fixture,
      'lineups': [
        {
          'team': {
            'id': 2932,
            'name': 'Al-Hilal',
            'colors': {'player': {'primary': '#0033a0', 'number': '#ffffff'}, 'goalkeeper': {'primary': '#00ff00'}},
          },
          'formation': '4-2-3-1',
          'coach': {'name': 'Coach'},
          'startXI': [
            {'id': 535, 'name': 'Bono', 'number': 37, 'position': 'G', 'grid': '1:1', 'photo': 'p.png'},
          ],
          'substitutes': [
            {'id': 9, 'name': 'Sub', 'number': 20, 'position': 'M', 'grid': null},
          ],
        },
      ],
      'events': [
        {'minute': 45, 'extra': 2, 'team': {'id': 2939}, 'player': {'name': 'P'}, 'assist': {'name': null}, 'type': 'card', 'detail': 'Red Card'},
        {'minute': 12, 'team': {'id': 2932}, 'player': {'name': 'G'}, 'assist': {'name': 'A'}, 'type': 'goal', 'detail': 'Normal Goal'},
      ],
      'statistics': [
        {'team': {'id': 2932}, 'stats': [{'type': 'Ball Possession', 'value': '58%'}, {'type': 'Shots on Goal', 'value': 6}, {'type': 'xG', 'value': null}]},
      ],
    }, stale: true);
    final l = m.lineupFor(2932)!;
    expect(l.formation, '4-2-3-1');
    expect(l.kitColor, '#0033a0');
    expect(l.startXI.single.grid, '1:1');
    expect(l.substitutes.single.grid, isNull);
    expect(m.events.first.minuteLabel, "45+2'");
    expect(m.events.first.isRedCard, isTrue);
    expect(m.events.last.type, MatchEventType.goal);
    expect(m.statistics.single.values['Ball Possession'], '58%');
    expect(m.statistics.single.values['Shots on Goal'], '6');
    expect(m.statistics.single.values['xG'], isNull);
    expect(m.stale, isTrue);
  });

  test('day groups by league in order', () {
    final day = MatchDay(date: '2026-10-20', fixtures: [
      MatchFixture.fromJson(_fixture),
      MatchFixture.fromJson({..._fixture, 'id': 2, 'league': {'id': 39, 'name': 'Premier League'}}),
      MatchFixture.fromJson({..._fixture, 'id': 3}),
    ]);
    final g = day.byLeague(DateTime(2026, 10, 20, 12));
    expect(g.map((e) => e.key.id).toList(), [307, 39]);
    expect(g.first.value.map((f) => f.id).toList(), [1001, 3]);
  });

  // Client 24 Oct: a 7 PM match was listed before a 3 PM one; a match that
  // starts moves ahead of the upcoming ones.
  test('match order: live, then nearest kickoff, then finished', () {
    MatchFixture m(int id, String kick, String short, {int league = 307}) => MatchFixture.fromJson({
          'id': id,
          'kickoff': kick,
          'league': {'id': league, 'name': 'L$league'},
          'status': {'short': short, 'long': '', 'live': short == '2H', 'finished': short == 'FT'},
        });
    final now = DateTime.utc(2026, 10, 24, 13).toLocal();
    final list = [
      m(1, '2026-10-24T19:00:00Z', 'NS'),
      m(2, '2026-10-24T15:00:00Z', 'NS', league: 140),
      m(3, '2026-10-24T11:00:00Z', 'FT'),
      m(4, '2026-10-24T12:00:00Z', '2H'),
      m(5, '2026-10-24T12:55:00Z', 'NS'), // kickoff passed, not refreshed yet
    ];
    expect(sortMatches(list, now).map((f) => f.id).toList(), [4, 5, 2, 1, 3]);
    final day = MatchDay(date: '2026-10-24', fixtures: list);
    // League 307 has the live match, so it leads; inside it the same order.
    expect(day.byLeague(now).map((e) => e.key.id).toList(), [307, 140]);
    expect(day.byLeague(now).first.value.map((f) => f.id).toList(), [4, 5, 1, 3]);
  });

  test('standings: older season shown with the plan notice', () {
    final t = LeagueTable.fromJson({
      'league': {'id': 307, 'name': 'Pro League', 'season': 2024},
      'groups': [
        [
          {'rank': 1, 'team': {'id': 2932, 'name': 'Al-Hilal'}, 'points': 70}
        ]
      ],
      'notice': {
        'code': 'PLAN_SEASON_LIMIT',
        'leagueId': 307,
        'requestedSeason': 2026,
        'shownSeason': 2024,
        'availableSeasons': {'from': 2022, 'to': 2024},
        'message': 'Free plans do not have access to this season, try from 2022 to 2024.',
        'provider': {'httpStatus': 200, 'body': {}},
      },
    });
    expect(t.season, 2024);
    expect(t.groups.single.single.points, 70);
    expect(t.notice?.requestedSeason, 2026);
    expect(t.notice?.shownSeason, 2024);
    expect(t.notice?.availableFrom, 2022);
    expect(t.notice?.availableTo, 2024);
  });

  test('standings: no notice, or an unknown one, is null', () {
    expect(LeagueTable.fromJson({'league': {'id': 1, 'season': 2026}}).notice, isNull);
    expect(StandingsNotice.fromJson({'code': 'OTHER', 'requestedSeason': 2026}), isNull);
    expect(StandingsNotice.fromJson(null), isNull);
  });

  test('standings: home / away tables re-ranked by points, GD, goals', () {
    StandingRow row(int rank, String name, Map<String, dynamic> home) => StandingRow.fromJson({
          'rank': rank,
          'team': {'id': rank, 'name': name},
          'points': 30 - rank,
          'played': 10,
          'goalsFor': 20,
          'goalsAgainst': 10,
          'description': rank == 1 ? 'Promotion - AFC Champions League Elite' : null,
          'home': home,
          'away': {'played': 5, 'win': 1, 'draw': 0, 'lose': 4, 'goalsFor': 3, 'goalsAgainst': 9},
        });
    final g = [
      row(1, 'A', {'played': 5, 'win': 3, 'draw': 1, 'lose': 1, 'goalsFor': 9, 'goalsAgainst': 5}),
      row(2, 'B', {'played': 5, 'win': 4, 'draw': 0, 'lose': 1, 'goalsFor': 10, 'goalsAgainst': 4}),
      row(3, 'C', {'played': 5, 'win': 3, 'draw': 1, 'lose': 1, 'goalsFor': 11, 'goalsAgainst': 5}),
    ];
    expect(g.first.description, 'Promotion - AFC Champions League Elite');
    expect(g.first.goalsFor, 20);
    final overall = standingsFor(g, StandingsView.overall);
    expect([for (final e in overall) e.row.team.name], ['A', 'B', 'C']);
    final home = standingsFor(g, StandingsView.home);
    // B 12 pts; A and C 10 pts, C ahead on goal difference (+6 vs +4).
    expect([for (final e in home) '${e.rank}${e.row.team.name}${e.stats.points}'], ['1B12', '2C10', '3A10']);
    expect(home.first.stats.goalsDiff, 6);
  });

  test('live clock runs on from the provider minute (MM:SS)', () {
    final at = DateTime(2026, 10, 23, 20, 0, 0);
    MatchFixture f(String short, int? min) => MatchFixture.fromJson({
          'id': 1,
          'status': {'short': short, 'long': '', 'elapsed': min, 'live': short != 'HT' && short != 'NS'},
        }, fetchedAt: at);
    expect(f('1H', 26).liveClock(at), '26:00');
    expect(f('1H', 26).liveClock(at.add(const Duration(minutes: 2, seconds: 14))), '28:14');
    // Added time is not in the feed: the first half stops at 50:00.
    expect(f('1H', 44).liveClock(at.add(const Duration(minutes: 20))), '50:00');
    expect(f('2H', 67).liveClock(at.add(const Duration(seconds: 5))), '67:05');
    expect(f('HT', 45).liveClock(at), isNull);
    expect(f('NS', null).liveClock(at), isNull);
  });

  test('stale live: Updating once the copy is old and past the match end', () {
    final at = DateTime(2026, 10, 23, 20, 0);
    MatchFixture f(String short, int min, DateTime kick) => MatchFixture.fromJson({
          'id': 1,
          'kickoff': kick.toUtc().toIso8601String(),
          'status': {'short': short, 'long': '', 'elapsed': min, 'live': true},
        }, fetchedAt: at);
    final kick = at.subtract(const Duration(minutes: 70));
    expect(f('2H', 67, kick).liveStale(at.add(const Duration(minutes: 2))), isFalse);
    expect(f('2H', 67, kick).liveStale(at.add(const Duration(minutes: 10))), isFalse);
    // 20 min later the clock would be at 87 + ... and kickoff 110 min ago.
    expect(f('2H', 85, kick).liveStale(at.add(const Duration(minutes: 20))), isTrue);
    // Old copy whose clock passed 95 min.
    expect(f('2H', 93, at.subtract(const Duration(minutes: 60))).liveStale(at.add(const Duration(minutes: 4))), isTrue);
    // Fresh copy is never stale.
    expect(f('2H', 95, at.subtract(const Duration(minutes: 130))).liveStale(at.add(const Duration(minutes: 1))), isFalse);
  });

  test('garbage does not throw', () {
    expect(MatchDetail.fromJson(const {}).fixture.id, 0);
    expect(MatchFixture.fromJson(null).home.name, '');
  });
}
