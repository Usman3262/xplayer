// Phase 7.8: matches & lineups from Supabase (sports_* tables, filled by the
// admin Sports module or a sports-API job). Same models the match centre
// screens already use, so their design stays as it is.

import 'dart:async';

import '../remote/json_read.dart';
import 'json_util.dart';
import '../remote/sports_api.dart';

/// What the match centre screens ask for. Implemented by the old server API
/// ([SportsApi]) and by Supabase ([SupabaseSports]).
abstract class MatchCentreSource {
  Future<bool> enabled();
  Future<MatchDay> fixtures({String? date, int? league, bool liveOnly = false});
  Future<MatchDetail> match(int id);
  Future<LeagueTable> standings(int league);
}

/// Calls one Postgres RPC and returns its decoded JSON.
typedef SportsRpc = Future<Object?> Function(String fn, Map<String, dynamic> params);

/// Match centre over Supabase RPCs `get_matches_between`, `get_match`,
/// `get_standings` (one round trip per screen). Supabase ids are UUIDs; the
/// screens use ints, so each UUID gets a stable 31-bit number and the
/// mapping is remembered for the session.
class SupabaseSports implements MatchCentreSource {
  SupabaseSports(this._rpc, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final SportsRpc _rpc;
  final DateTime Function() _clock;
  final _uuidOf = <int, String>{};
  final _lastDay = <String, MatchDay>{};
  static const _timeout = Duration(seconds: 12);

  /// FNV-1a: the same number for a UUID on every device and run.
  static int idFor(String uuid) {
    var h = 0x811c9dc5;
    for (final c in uuid.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }

  int _remember(String? uuid) {
    if (uuid == null || uuid.isEmpty) return 0;
    final id = idFor(uuid);
    _uuidOf[id] = uuid;
    return id;
  }

  /// On when the admin has matches from yesterday to the day after
  /// tomorrow (one small call); an empty match centre stays hidden.
  @override
  Future<bool> enabled() async {
    try {
      final now = _clock();
      final from = DateTime(now.year, now.month, now.day - 1);
      final list = await _between(from, from.add(const Duration(days: 3)), limit: 1);
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// [date] = YYYY-MM-DD in the device's time zone (null = today).
  @override
  Future<MatchDay> fixtures({String? date, int? league, bool liveOnly = false}) async {
    final now = _clock();
    final day = DateTime.tryParse(date ?? '') ?? DateTime(now.year, now.month, now.day);
    final from = DateTime(day.year, day.month, day.day);
    final key = '${_ymd(from)}|${league ?? ''}|$liveOnly';
    try {
      var list = await _between(from, DateTime(from.year, from.month, from.day + 1));
      if (league != null) list = list.where((f) => f.league.id == league).toList();
      if (liveOnly) list = list.where((f) => f.status.live).toList();
      final d = MatchDay(date: _ymd(from), fixtures: list, fetchedAt: now);
      _lastDay[key] = d;
      return d;
    } catch (e) {
      final kept = _lastDay[key];
      if (kept != null) {
        return MatchDay(date: kept.date, fixtures: kept.fixtures, stale: true, fetchedAt: kept.fetchedAt);
      }
      rethrow;
    }
  }

  Future<List<MatchFixture>> _between(DateTime from, DateTime to, {int limit = 100}) async {
    final raw = await _rpc('get_matches_between', {
      'p_from': from.toUtc().toIso8601String(),
      'p_to': to.toUtc().toIso8601String(),
      'p_limit': limit,
    }).timeout(_timeout);
    final fetched = _clock();
    return [for (final j in _maps(raw)) _fixture(j, fetched)];
  }

  @override
  Future<MatchDetail> match(int id) async {
    final uuid = _uuidOf[id];
    if (uuid == null) throw StateError('match $id not known');
    final d = jsonMap(await _rpc('get_match', {'p_id': uuid}).timeout(_timeout));
    final m = jsonMap(d['match']);
    final comp = jsonMap(d['competition']);
    final home = jsonMap(d['home']);
    final away = jsonMap(d['away']);
    final fixture = _fixture({
      ...m,
      'competition': comp,
      'home': home,
      'away': away,
      'channels': [for (final c in _maps(d['channels'])) jsonStr(c['name']) ?? jsonStr(c['match'])]
          .whereType<String>()
          .toList(),
    }, _clock());
    final teams = {jsonStr(home['id']): fixture.home, jsonStr(away['id']): fixture.away};
    return MatchDetail(
      fixture: fixture,
      lineups: [
        for (final l in _maps(d['lineups']))
          if (teams[jsonStr(l['team'])] case final team?) _lineup(l, team),
      ],
      events: [for (final e in _maps(d['events'])) _event(e)],
    );
  }

  @override
  Future<LeagueTable> standings(int league) async {
    final uuid = _uuidOf[league];
    if (uuid == null) throw StateError('league $league not known');
    final d = jsonMap(await _rpc('get_standings', {'p_competition': uuid}).timeout(_timeout));
    final comp = jsonMap(d['competition']);
    final groups = <String, List<StandingRow>>{};
    for (final r in _maps(d['rows'])) {
      final played = jsonInt(r['played']) ?? 0;
      final gf = jsonInt(r['gf']) ?? 0;
      final ga = jsonInt(r['ga']) ?? 0;
      (groups[jsonStr(r['group']) ?? ''] ??= []).add(
        StandingRow(
          rank: jsonInt(r['rank']) ?? 0,
          team: _team(jsonMap(r['team'])),
          points: jsonInt(r['points']) ?? 0,
          goalsDiff: gf - ga,
          played: played,
          win: jsonInt(r['won']) ?? 0,
          draw: jsonInt(r['drawn']) ?? 0,
          lose: jsonInt(r['lost']) ?? 0,
          goalsFor: gf,
          goalsAgainst: ga,
          form: jsonStr(r['form']),
        ),
      );
    }
    return LeagueTable(
      league: _league(comp, null),
      groups: groups.values.toList(),
      season: int.tryParse(jsonStr(comp['season'])?.split(RegExp(r'[/-]')).first ?? ''),
    );
  }

  // ── Mapping ──────────────────────────────────────────────────────────────

  MatchFixture _fixture(Map<String, dynamic> j, DateTime fetched) {
    final kickoff = DateTime.tryParse(jsonStr(j['kickoff_at']) ?? '')?.toLocal();
    return MatchFixture(
      id: _remember(jsonStr(j['id'])),
      kickoff: kickoff,
      fetchedAt: fetched,
      status: statusFor(jsonStr(j['status']), jsonInt(j['minute'])),
      league: _league(jsonMap(j['competition']), jsonStr(j['round'])),
      home: _team(jsonMap(j['home'])),
      away: _team(jsonMap(j['away'])),
      homeGoals: jsonInt(j['home_score']),
      awayGoals: jsonInt(j['away_score']),
      venue: jsonStr(j['venue']),
      channels: [for (final c in (j['channels'] is List ? j['channels'] as List : const [])) ?jsonStr(c)],
    );
  }

  MatchLeague _league(Map<String, dynamic> c, String? round) => MatchLeague(
    id: _remember(jsonStr(c['id'])),
    name: jsonStr(c['name']) ?? jsonStr(c['short']) ?? '',
    country: jsonStr(c['country']),
    logo: jsonStr(c['logo']),
    round: round,
  );

  MatchTeam _team(Map<String, dynamic> t) => MatchTeam(
    id: _remember(jsonStr(t['id'])),
    name: jsonStr(t['name']) ?? jsonStr(t['short']) ?? '',
    logo: jsonStr(t['logo']),
  );

  MatchLineup _lineup(Map<String, dynamic> l, MatchTeam team) {
    LineupPlayer p(Map<String, dynamic> j) =>
        LineupPlayer(name: jsonStr(j['name']) ?? '', number: jsonInt(j['number']), position: jsonStr(j['position']));
    final players = _maps(l['players']);
    return MatchLineup(
      team: team,
      formation: jsonStr(l['formation']),
      coach: jsonStr(l['coach']),
      startXI: [
        for (final j in players)
          if (j['starter'] != false) p(j),
      ],
      substitutes: [
        for (final j in players)
          if (j['starter'] == false) p(j),
      ],
    );
  }

  MatchEvent _event(Map<String, dynamic> e) {
    final t = jsonStr(e['type']) ?? 'other';
    final (type, detail) = switch (t) {
      'goal' => (MatchEventType.goal, 'Normal Goal'),
      'own_goal' => (MatchEventType.goal, 'Own Goal'),
      'penalty_goal' => (MatchEventType.goal, 'Penalty'),
      'penalty_miss' => (MatchEventType.other, 'Missed Penalty'),
      'yellow' => (MatchEventType.card, 'Yellow Card'),
      'red' => (MatchEventType.card, 'Red Card'),
      'substitution' => (MatchEventType.subst, null),
      'var' => (MatchEventType.varCheck, null),
      _ => (MatchEventType.other, null),
    };
    return MatchEvent(
      type: type,
      teamId: _remember(jsonStr(e['team'])),
      minute: jsonInt(e['minute']),
      extra: jsonInt(e['extra']),
      player: jsonStr(e['player']),
      assist: jsonStr(e['assist']),
      detail: jsonStr(e['detail']) ?? detail,
    );
  }

  /// Supabase status → the short codes the screens know (API-Football style).
  static MatchStatus statusFor(String? s, int? minute) => switch (s) {
    'live' => MatchStatus(short: minute == null ? 'LIVE' : '2H', long: 'In play', elapsed: minute, live: true),
    'halftime' => MatchStatus(short: 'HT', long: 'Half time', elapsed: minute ?? 45, live: true),
    'finished' => const MatchStatus(short: 'FT', long: 'Match finished', finished: true),
    'postponed' => const MatchStatus(short: 'PST', long: 'Postponed'),
    'cancelled' => const MatchStatus(short: 'CANC', long: 'Cancelled'),
    'suspended' => const MatchStatus(short: 'SUSP', long: 'Suspended'),
    _ => const MatchStatus(short: 'NS', long: 'Not started'),
  };

  static List<Map<String, dynamic>> _maps(Object? v) => jsonMapList(v);

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
