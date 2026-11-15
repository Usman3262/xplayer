import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const matchId = '6f1c2d3e-0000-4000-8000-000000000001';
  const comp = 'c0000000-0000-4000-8000-000000000001';
  const home = 'a0000000-0000-4000-8000-00000000000a';
  const away = 'b0000000-0000-4000-8000-00000000000b';
  final calls = <String, Map<String, dynamic>>{};

  Future<Object?> rpc(String fn, Map<String, dynamic> p) async {
    calls[fn] = p;
    switch (fn) {
      case 'get_matches_between':
        return [
          {
            'id': matchId, 'status': 'live', 'minute': 63, 'kickoff_at': '2026-11-15T18:00:00Z',
            'round': 'Week 12', 'venue': 'Camp Nou', 'home_score': 2, 'away_score': 1,
            'competition': {'id': comp, 'name': 'La Liga', 'country': 'ES'},
            'home': {'id': home, 'name': 'Barcelona'}, 'away': {'id': away, 'name': 'Real Madrid'},
            'channels': ['beIN Sports 1'],
          },
        ];
      case 'get_match':
        return {
          'match': {'id': matchId, 'status': 'finished', 'kickoff_at': '2026-11-15T18:00:00Z', 'home_score': 3, 'away_score': 1},
          'competition': {'id': comp, 'name': 'La Liga'},
          'home': {'id': home, 'name': 'Barcelona'},
          'away': {'id': away, 'name': 'Real Madrid'},
          'lineups': [
            {'team': home, 'formation': '4-3-3', 'players': [
              {'name': 'Ter Stegen', 'number': 1, 'position': 'G'},
              {'name': 'Bench Guy', 'number': 20, 'starter': false},
            ]},
          ],
          'events': [
            {'minute': 10, 'type': 'goal', 'team': home, 'player': 'Lewandowski'},
            {'minute': 45, 'extra': 2, 'type': 'yellow', 'team': away, 'player': 'Vinicius'},
          ],
          'channels': [{'match': 'beIN Sports 1'}],
        };
      case 'get_standings':
        return {
          'competition': {'id': comp, 'name': 'La Liga', 'season': '2026/27'},
          'rows': [
            {'group': '', 'rank': 1, 'played': 12, 'won': 10, 'drawn': 1, 'lost': 1, 'gf': 30, 'ga': 8, 'points': 31,
              'team': {'id': home, 'name': 'Barcelona'}},
          ],
        };
    }
    return null;
  }

  test('day list: local day range sent, fixture mapped, live status', () async {
    final s = SupabaseSports(rpc, clock: () => DateTime(2026, 11, 15, 12));
    final day = await s.fixtures(date: '2026-11-15');
    expect(day.date, '2026-11-15');
    final f = day.fixtures.single;
    expect(f.home.name, 'Barcelona');
    expect((f.homeGoals, f.awayGoals), (2, 1));
    expect(f.status.live, isTrue);
    expect(f.status.elapsed, 63);
    expect(f.league.name, 'La Liga');
    expect(f.channels, ['beIN Sports 1']);
    expect(f.id, SupabaseSports.idFor(matchId));
    final from = DateTime.parse(calls['get_matches_between']!['p_from'] as String);
    expect(from, DateTime(2026, 11, 15).toUtc());
  });

  test('match page: lineups split starters / bench, events typed', () async {
    final s = SupabaseSports(rpc, clock: () => DateTime(2026, 11, 15, 12));
    final f = (await s.fixtures(date: '2026-11-15')).fixtures.single;
    final d = await s.match(f.id);
    expect(calls['get_match']!['p_id'], matchId);
    expect(d.fixture.status.finished, isTrue);
    expect(d.lineups.single.startXI.single.name, 'Ter Stegen');
    expect(d.lineups.single.substitutes.single.number, 20);
    expect(d.events.first.type, MatchEventType.goal);
    expect(d.events.last.type, MatchEventType.card);
    expect(d.events.last.detail, 'Yellow Card');
    expect(d.events.last.teamId, f.away.id);
  });

  test('standings by the league number from the list', () async {
    final s = SupabaseSports(rpc, clock: () => DateTime(2026, 11, 15, 12));
    final f = (await s.fixtures(date: '2026-11-15')).fixtures.single;
    final t = await s.standings(f.league.id);
    expect(calls['get_standings']!['p_competition'], comp);
    expect(t.groups.single.single.points, 31);
    expect(t.groups.single.single.goalsDiff, 22);
    expect(t.season, 2026);
  });

  test('stable ids; failures fall back to the last list (marked stale)', () async {
    expect(SupabaseSports.idFor(matchId), SupabaseSports.idFor(matchId));
    var fail = false;
    final s = SupabaseSports((fn, p) async {
      if (fail) throw Exception('offline');
      return rpc(fn, p);
    }, clock: () => DateTime(2026, 11, 15, 12));
    await s.fixtures(date: '2026-11-15');
    fail = true;
    final again = await s.fixtures(date: '2026-11-15');
    expect(again.stale, isTrue);
    expect(again.fixtures, hasLength(1));
    expect(await s.enabled(), isFalse);
  });
}
