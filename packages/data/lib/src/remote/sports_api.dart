import '../backend/supabase_sports.dart' show MatchCentreSource;
import 'dart:convert';

import '../diag/diag.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'json_read.dart';

/// Match centre (`/v1/sports/*`, App-Backend PR #7): schedules,
/// lineups, formations, substitutes, events, statistics, timeline.
/// The provider key stays on the server; this only reads our own shapes.

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
List<Object?> _list(Object? v) => v is List ? v : const [];
String? _text(Object? v) {
  if (v == null) return null;
  final t = '$v'.trim();
  return t.isEmpty ? null : t;
}

int? _int(Object? v) => jsonDouble(v)?.toInt();

class MatchTeam {
  const MatchTeam({required this.id, required this.name, this.nameAr, this.logo, this.winner});
  final int id;
  final String name;

  /// Arabic name stored once on our server for this provider id (backend
  /// `sports_names`); null when not known yet.
  final String? nameAr;
  final String? logo;
  final bool? winner;

  /// Name for the app language ('ar' → Arabic when known).
  String nameFor(String language) =>
      language == 'ar' && (nameAr ?? '').isNotEmpty ? nameAr! : name;

  factory MatchTeam.fromJson(Object? raw) {
    final j = _map(raw);
    return MatchTeam(
      id: _int(j['id']) ?? 0,
      name: _text(j['name']) ?? '',
      nameAr: _text(j['nameAr']),
      logo: _text(j['logo']),
      winner: j['winner'] is bool ? j['winner'] as bool : null,
    );
  }
}

class MatchStatus {
  const MatchStatus({
    required this.short,
    required this.long,
    this.elapsed,
    this.live = false,
    this.finished = false,
  });
  final String short;
  final String long;
  final int? elapsed;
  final bool live;
  final bool finished;

  bool get notStarted => !live && !finished;

  factory MatchStatus.fromJson(Object? raw) {
    final j = _map(raw);
    return MatchStatus(
      short: _text(j['short']) ?? 'NS',
      long: _text(j['long']) ?? '',
      elapsed: _int(j['elapsed']),
      live: j['live'] == true,
      finished: j['finished'] == true,
    );
  }
}

class MatchLeague {
  const MatchLeague({
    required this.id,
    required this.name,
    this.nameAr,
    this.country,
    this.logo,
    this.round,
  });
  final int id;
  final String name;
  final String? nameAr;

  String nameFor(String language) =>
      language == 'ar' && (nameAr ?? '').isNotEmpty ? nameAr! : name;
  final String? country;
  final String? logo;
  final String? round;

  factory MatchLeague.fromJson(Object? raw) {
    final j = _map(raw);
    return MatchLeague(
      id: _int(j['id']) ?? 0,
      name: _text(j['name']) ?? '',
      nameAr: _text(j['nameAr']),
      country: _text(j['country']),
      logo: _text(j['logo']),
      round: _text(j['round']),
    );
  }
}

class MatchFixture {
  const MatchFixture({
    required this.id,
    required this.kickoff,
    required this.status,
    required this.league,
    required this.home,
    required this.away,
    this.homeGoals,
    this.awayGoals,
    this.venue,
    this.city,
    this.referee,
    this.channels = const [],
    this.fetchedAt,
  });

  final int id;
  final DateTime? kickoff;

  /// When the server read this from the provider (live clock base).
  final DateTime? fetchedAt;
  final MatchStatus status;
  final MatchLeague league;
  final MatchTeam home;
  final MatchTeam away;
  final int? homeGoals;
  final int? awayGoals;
  final String? venue;
  final String? city;
  final String? referee;

  /// Broadcasting channels, when the server knows them (not in the
  /// API-Football feed; set by the operator).
  final List<String> channels;

  bool get hasScore => homeGoals != null && awayGoals != null;

  factory MatchFixture.fromJson(Object? raw, {DateTime? fetchedAt}) {
    final j = _map(raw);
    final goals = _map(j['goals']);
    final venue = _map(j['venue']);
    return MatchFixture(
      id: _int(j['id']) ?? 0,
      kickoff: DateTime.tryParse('${j['kickoff'] ?? ''}')?.toLocal(),
      status: MatchStatus.fromJson(j['status']),
      league: MatchLeague.fromJson(j['league']),
      home: MatchTeam.fromJson(j['home']),
      away: MatchTeam.fromJson(j['away']),
      homeGoals: _int(goals['home']),
      awayGoals: _int(goals['away']),
      venue: _text(venue['name']),
      city: _text(venue['city']),
      referee: _text(j['referee']),
      channels: [for (final c in _list(j['channels'])) ?_text(c)],
      fetchedAt: fetchedAt,
    );
  }

  /// True while "live" data can no longer be trusted (client round 3 #14:
  /// a finished match kept "LIVE 95:00"): the copy is over 3 min old and
  /// either the clock has run past the period's end or kickoff was more
  /// than 105 min ago. The apps then show "Updating" instead of LIVE.
  bool liveStale(DateTime now) {
    if (!status.live || fetchedAt == null) return false;
    final age = now.difference(fetchedAt!);
    if (age < const Duration(minutes: 3)) return false;
    final k = kickoff;
    if (k != null && now.difference(k) > const Duration(minutes: 105)) return true;
    final minute = status.elapsed;
    if (minute == null) return false;
    final cap = switch (status.short) { '1H' => 50, '2H' => 95, 'ET' => 125, _ => 999 };
    return minute + age.inMinutes >= cap;
  }

  /// Match clock "MM:SS" while in play (client 23 Oct round 3 #12): the
  /// provider's minute plus the time since the server read it, so it runs
  /// on between refreshes. Capped per period (45 / 90 / 120 + 5 min), as
  /// added time is not in the feed. Null when not in play.
  String? liveClock(DateTime now) {
    final s = status;
    if (s.short == 'HT' || !s.live) return null;
    final minute = s.elapsed;
    if (minute == null) return null;
    final since = fetchedAt == null ? 0 : now.difference(fetchedAt!).inSeconds.clamp(0, 25 * 60);
    final cap = switch (s.short) {
      '1H' => 50 * 60,
      '2H' => 95 * 60,
      'ET' => 125 * 60,
      _ => minute * 60 + 59,
    };
    final secs = (minute * 60 + since).clamp(0, cap < minute * 60 ? minute * 60 : cap);
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

class LineupPlayer {
  const LineupPlayer({
    required this.name,
    this.id,
    this.number,
    this.position,
    this.grid,
    this.photo,
  });
  final int? id;
  final String name;
  final int? number;

  /// G, D, M, F
  final String? position;

  /// "row:col" on the pitch (starting XI only).
  final String? grid;
  final String? photo;

  factory LineupPlayer.fromJson(Object? raw) {
    final j = _map(raw);
    return LineupPlayer(
      id: _int(j['id']),
      name: _text(j['name']) ?? '',
      number: _int(j['number']),
      position: _text(j['position']),
      grid: _text(j['grid']),
      photo: _text(j['photo']),
    );
  }
}

class MatchLineup {
  const MatchLineup({
    required this.team,
    this.formation,
    this.coach,
    this.kitColor,
    this.kitNumberColor,
    this.keeperColor,
    this.keeperNumberColor,
    this.startXI = const [],
    this.substitutes = const [],
  });
  final MatchTeam team;
  final String? formation;
  final String? coach;

  /// "#rrggbb" from the provider, when it has team colours.
  final String? kitColor;
  final String? kitNumberColor;
  final String? keeperColor;
  final String? keeperNumberColor;
  final List<LineupPlayer> startXI;
  final List<LineupPlayer> substitutes;

  factory MatchLineup.fromJson(Object? raw) {
    final j = _map(raw);
    final team = _map(j['team']);
    final colors = _map(team['colors']);
    final player = _map(colors['player']);
    final keeper = _map(colors['goalkeeper']);
    return MatchLineup(
      team: MatchTeam.fromJson(team),
      formation: _text(j['formation']),
      coach: _text(_map(j['coach'])['name']),
      kitColor: _text(player['primary']),
      kitNumberColor: _text(player['number']),
      keeperColor: _text(keeper['primary']),
      keeperNumberColor: _text(keeper['number']),
      startXI: [for (final p in _list(j['startXI'])) LineupPlayer.fromJson(p)],
      substitutes: [
        for (final p in _list(j['substitutes'])) LineupPlayer.fromJson(p),
      ],
    );
  }
}

enum MatchEventType { goal, card, subst, varCheck, other }

class MatchEvent {
  const MatchEvent({
    required this.type,
    required this.teamId,
    this.minute,
    this.extra,
    this.player,
    this.assist,
    this.playerId,
    this.assistId,
    this.detail,
    this.comments,
  });
  /// Provider player ids: names differ between endpoints ("Matias Soule"
  /// in events, "M. Soulé" in lineups), ids do not.
  final int? playerId;
  final int? assistId;
  final int? minute;
  final int? extra;
  final int teamId;
  final String? player;
  final String? assist;
  final MatchEventType type;
  final String? detail;
  final String? comments;

  /// "45+2'"
  String get minuteLabel =>
      minute == null ? '' : (extra != null && extra! > 0 ? "$minute+$extra'" : "$minute'");

  bool get isRedCard =>
      type == MatchEventType.card && (detail ?? '').toLowerCase().contains('red');

  factory MatchEvent.fromJson(Object? raw) {
    final j = _map(raw);
    final type = switch (_text(j['type'])) {
      'goal' => MatchEventType.goal,
      'card' => MatchEventType.card,
      'subst' => MatchEventType.subst,
      'var' => MatchEventType.varCheck,
      _ => MatchEventType.other,
    };
    return MatchEvent(
      minute: _int(j['minute']),
      extra: _int(j['extra']),
      teamId: _int(_map(j['team'])['id']) ?? 0,
      player: _text(_map(j['player'])['name']),
      assist: _text(_map(j['assist'])['name']),
      playerId: _int(_map(j['player'])['id']),
      assistId: _int(_map(j['assist'])['id']),
      type: type,
      detail: _text(j['detail']),
      comments: _text(j['comments']),
    );
  }
}

class TeamStatistics {
  const TeamStatistics({required this.teamId, required this.values});
  final int teamId;

  /// Provider order: type → value ("58%", 6, or null).
  final Map<String, String?> values;

  factory TeamStatistics.fromJson(Object? raw) {
    final j = _map(raw);
    return TeamStatistics(
      teamId: _int(_map(j['team'])['id']) ?? 0,
      values: {
        for (final s in _list(j['stats']))
          if (_text(_map(s)['type']) case final type?)
            type: _text(_map(s)['value']),
      },
    );
  }
}

class MatchPlayerRating {
  const MatchPlayerRating({
    required this.teamId,
    required this.name,
    this.id,
    this.photo,
    this.rating,
    this.goals,
    this.assists,
    this.keyPasses,
    this.captain = false,
  });
  final int teamId;
  final int? id;
  final String name;
  final String? photo;
  final double? rating;
  final int? goals;
  final int? assists;
  final int? keyPasses;
  final bool captain;

  factory MatchPlayerRating.fromJson(Object? raw) {
    final j = _map(raw);
    return MatchPlayerRating(
      teamId: _int(j['teamId']) ?? 0,
      id: _int(j['id']),
      name: _text(j['name']) ?? '',
      photo: _text(j['photo']),
      rating: jsonDouble(j['rating']),
      goals: _int(j['goals']),
      assists: _int(j['assists']),
      keyPasses: _int(j['keyPasses']),
      captain: j['captain'] == true,
    );
  }
}

/// Played / won / drawn / lost and goals: overall, home games or away games.
class StandingSplit {
  const StandingSplit({
    this.played = 0,
    this.win = 0,
    this.draw = 0,
    this.lose = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
  });
  final int played;
  final int win;
  final int draw;
  final int lose;
  final int goalsFor;
  final int goalsAgainst;

  int get points => win * 3 + draw;
  int get goalsDiff => goalsFor - goalsAgainst;

  factory StandingSplit.fromJson(Object? raw) {
    final j = _map(raw);
    return StandingSplit(
      played: _int(j['played']) ?? 0,
      win: _int(j['win']) ?? 0,
      draw: _int(j['draw']) ?? 0,
      lose: _int(j['lose']) ?? 0,
      goalsFor: _int(j['goalsFor']) ?? 0,
      goalsAgainst: _int(j['goalsAgainst']) ?? 0,
    );
  }
}

class StandingRow {
  const StandingRow({
    required this.rank,
    required this.team,
    required this.points,
    required this.goalsDiff,
    required this.played,
    required this.win,
    required this.draw,
    required this.lose,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
    this.home = const StandingSplit(),
    this.away = const StandingSplit(),
    this.form,
    this.description,
  });
  final int rank;
  final MatchTeam team;
  final int points;
  final int goalsDiff;
  final int played;
  final int win;
  final int draw;
  final int lose;
  final int goalsFor;
  final int goalsAgainst;

  /// Home games only / away games only (backend #47).
  final StandingSplit home;
  final StandingSplit away;
  final String? form;

  /// Qualification / relegation zone, e.g. "Promotion - AFC Champions League Elite".
  final String? description;

  factory StandingRow.fromJson(Object? raw) {
    final j = _map(raw);
    return StandingRow(
      rank: _int(j['rank']) ?? 0,
      team: MatchTeam.fromJson(j['team']),
      points: _int(j['points']) ?? 0,
      goalsDiff: _int(j['goalsDiff']) ?? 0,
      played: _int(j['played']) ?? 0,
      win: _int(j['win']) ?? 0,
      draw: _int(j['draw']) ?? 0,
      lose: _int(j['lose']) ?? 0,
      goalsFor: _int(j['goalsFor']) ?? 0,
      goalsAgainst: _int(j['goalsAgainst']) ?? 0,
      home: StandingSplit.fromJson(j['home']),
      away: StandingSplit.fromJson(j['away']),
      form: _text(j['form']),
      description: _text(j['description']),
    );
  }
}

/// Overall / home games / away games table.
enum StandingsView { overall, home, away }

/// Rows of [group] for [view]: overall keeps the provider's order; home and
/// away are ranked by points, then goal difference, then goals scored.
List<({int rank, StandingRow row, StandingSplit stats})> standingsFor(
  List<StandingRow> group,
  StandingsView view,
) {
  StandingSplit overall(StandingRow r) => StandingSplit(
        played: r.played,
        win: r.win,
        draw: r.draw,
        lose: r.lose,
        goalsFor: r.goalsFor,
        goalsAgainst: r.goalsAgainst,
      );
  if (view == StandingsView.overall) {
    return [for (final r in group) (rank: r.rank, row: r, stats: overall(r))];
  }
  final rows = [
    for (final r in group) (row: r, stats: view == StandingsView.home ? r.home : r.away),
  ]..sort((a, b) {
      final p = b.stats.points.compareTo(a.stats.points);
      if (p != 0) return p;
      final gd = b.stats.goalsDiff.compareTo(a.stats.goalsDiff);
      if (gd != 0) return gd;
      final gf = b.stats.goalsFor.compareTo(a.stats.goalsFor);
      return gf != 0 ? gf : a.row.rank.compareTo(b.row.rank);
    });
  return [
    for (var i = 0; i < rows.length; i++) (rank: i + 1, row: rows[i].row, stats: rows[i].stats),
  ];
}

class LeagueTable {
  const LeagueTable({required this.league, this.groups = const [], this.season, this.notice});
  final MatchLeague league;
  final List<List<StandingRow>> groups;

  /// Season of the table (API-Football: the year it starts, 2024 = 2024/25).
  final int? season;

  /// Set when the match-data plan does not include the season asked for.
  final StandingsNotice? notice;

  factory LeagueTable.fromJson(Map<String, dynamic> j) => LeagueTable(
        league: MatchLeague.fromJson(j['league']),
        season: _int(_map(j['league'])['season']),
        notice: StandingsNotice.fromJson(j['notice']),
        groups: [
          for (final g in _list(j['groups']))
            [for (final r in _list(g)) StandingRow.fromJson(r)],
        ],
      );
}

/// Backend notice: the plan refused [requestedSeason]; [shownSeason] is the
/// newest season it allows (null when none could be shown).
class StandingsNotice {
  const StandingsNotice({
    required this.requestedSeason,
    this.shownSeason,
    this.availableFrom,
    this.availableTo,
    this.message = '',
  });
  final int requestedSeason;
  final int? shownSeason;
  final int? availableFrom;
  final int? availableTo;

  /// The provider's refusal, as sent (English).
  final String message;

  static StandingsNotice? fromJson(Object? raw) {
    final j = _map(raw);
    final asked = _int(j['requestedSeason']);
    if (j['code'] != 'PLAN_SEASON_LIMIT' || asked == null) return null;
    final range = _map(j['availableSeasons']);
    return StandingsNotice(
      requestedSeason: asked,
      shownSeason: _int(j['shownSeason']),
      availableFrom: _int(range['from']),
      availableTo: _int(range['to']),
      message: _text(j['message']) ?? '',
    );
  }
}

class MatchCentreStatus {
  const MatchCentreStatus({this.enabled = false, this.leagues = const []});
  final bool enabled;
  final List<MatchLeague> leagues;
}

class MatchDetail {
  const MatchDetail({
    required this.fixture,
    this.lineups = const [],
    this.events = const [],
    this.statistics = const [],
    this.players = const [],
    this.stale = false,
    this.fetchedAt,
    this.lineupsHidden = false,
  });
  final MatchFixture fixture;
  final List<MatchLineup> lineups;

  /// Lineups switched off in the Control Panel: the server says so in every
  /// match answer (`lineupsHidden: true`), so the tab goes at the next refresh
  /// of the match (about 30 s), without waiting for the app settings.
  final bool lineupsHidden;
  final List<MatchEvent> events;
  final List<TeamStatistics> statistics;

  /// Ratings and figures per player (may be empty before kickoff).
  final List<MatchPlayerRating> players;

  /// Best-rated player of [teamId] (design: highlighted on the pitch).
  MatchPlayerRating? topPlayer(int teamId) {
    MatchPlayerRating? best;
    for (final p in players) {
      if (p.teamId != teamId || p.rating == null) continue;
      if (best == null || p.rating! > best.rating!) best = p;
    }
    return best;
  }

  /// Served from the server's last good copy (provider down / limit).
  final bool stale;

  /// When the server last fetched it from the provider.
  final DateTime? fetchedAt;

  MatchLineup? lineupFor(int teamId) {
    for (final l in lineups) {
      if (l.team.id == teamId) return l;
    }
    return null;
  }

  factory MatchDetail.fromJson(
    Map<String, dynamic> j, {
    bool stale = false,
    DateTime? fetchedAt,
  }) =>
      MatchDetail(
        fixture: MatchFixture.fromJson(j['fixture'], fetchedAt: fetchedAt),
        lineups: [for (final l in _list(j['lineups'])) MatchLineup.fromJson(l)],
        events: [for (final e in _list(j['events'])) MatchEvent.fromJson(e)],
        statistics: [
          for (final s in _list(j['statistics'])) TeamStatistics.fromJson(s),
        ],
        players: [
          for (final p in _list(j['players'])) MatchPlayerRating.fromJson(p),
        ],
        stale: stale,
        fetchedAt: fetchedAt,
        lineupsHidden: j['lineupsHidden'] == true,
      );
}

/// Day list grouped by competition, in kickoff order.
class MatchDay {
  const MatchDay({
    required this.date,
    required this.fixtures,
    this.stale = false,
    this.fetchedAt,
  });
  final String date;
  final List<MatchFixture> fixtures;
  final bool stale;
  final DateTime? fetchedAt;

  /// Competitions in match order (client 24 Oct): the league of the
  /// nearest live / upcoming match first; inside each, [sortMatches].
  List<MapEntry<MatchLeague, List<MatchFixture>>> byLeague([DateTime? now]) {
    final at = now ?? DateTime.now();
    final leagues = <int, MatchLeague>{};
    final groups = <int, List<MatchFixture>>{};
    for (final f in fixtures) {
      leagues.putIfAbsent(f.league.id, () => f.league);
      (groups[f.league.id] ??= []).add(f);
    }
    final out = [
      for (final e in leagues.entries) MapEntry(e.value, sortMatches(groups[e.key]!, at)),
    ];
    return _stableSort(out, (a, b) => compareMatches(a.value.first, b.value.first, at));
  }
}

/// 0 = live or should have started (kickoff passed, not finished: the next
/// refresh brings its live status), 1 = upcoming, 2 = finished.
int matchRank(MatchFixture f, DateTime now) {
  if (f.status.finished) return 2;
  if (f.status.live || f.status.short == 'HT') return 0;
  final k = f.kickoff;
  if (k != null && !k.isAfter(now)) return 0;
  return 1;
}

/// Live first, then the nearest kickoff, then finished (client 24 Oct: a
/// 7 PM match was listed before a 3 PM one). One comparator: the old
/// two-pass sort was not stable and mixed the order up.
int compareMatches(MatchFixture a, MatchFixture b, DateTime now) {
  final r = matchRank(a, now).compareTo(matchRank(b, now));
  if (r != 0) return r;
  return (a.kickoff ?? DateTime(0)).compareTo(b.kickoff ?? DateTime(0));
}

/// [compareMatches] order; equal matches keep the provider's order.
List<MatchFixture> sortMatches(Iterable<MatchFixture> list, [DateTime? now]) {
  final at = now ?? DateTime.now();
  return _stableSort(list.toList(), (a, b) => compareMatches(a, b, at));
}

List<T> _stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

class SportsApi implements MatchCentreSource {
  /// The account's package has no Sports (Usman 12 Nov: every /sports/*
  /// call except /sports/status answers 403 SPORTS_NOT_IN_PACKAGE). Screens
  /// show "not in your package" instead of an error; it is never retried.
  static bool isNotInPackage(Object? e) =>
      e is ApiException &&
      (e.code == 'SPORTS_NOT_IN_PACKAGE' ||
          (e.statusCode == 403 && e.message.toLowerCase().contains('package')));

  SportsApi(this._client);
  final ApiClient _client;

  /// False when the server has no match centre (flag off, no key, or an
  /// older deployment without the routes): the entry stays hidden.
  Future<bool> enabled() async => (await status()).enabled;

  /// Enabled flag + configured leagues (no provider call on the server).
  Future<MatchCentreStatus> status() async {
    try {
      final d = await _client.get('/sports/status');
      return MatchCentreStatus(
        enabled: d?['enabled'] == true,
        leagues: [for (final l in _list(d?['leagues'])) MatchLeague.fromJson(l)],
      );
    } on ApiException {
      return const MatchCentreStatus();
    }
  }

  final Map<int, LeagueTable> _lastTable = {};
  final Map<int, MatchDetail> _lastMatch = {};

  /// Same rule as [fixtures]: 12 s, one retry, then the last answer.
  Future<T> _withFallback<T>(Future<T> Function() load, T? kept, void Function(T) keep) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final v = await load().timeout(_sportsTimeout);
        keep(v);
        return v;
      } catch (e) {
        if (isNotInPackage(e)) rethrow;
        lastError = e;
        if (kept != null) return kept;
      }
    }
    throw lastError!;
  }

  Future<LeagueTable> standings(int league) =>
      _withFallback(() => _standingsOnce(league), _lastTable[league], (v) => _lastTable[league] = v);

  Future<LeagueTable> _standingsOnce(int league) async {
    final d = await _client.get('/sports/standings', query: {'league': '$league'});
    final notice = d?['notice'];
    if (notice != null) {
      // Diagnostic builds: the provider's exact refusal (league, season,
      // errors, coverage) for the client (round 3 standings follow-up).
      final raw = jsonEncode(notice);
      for (var i = 0; i < raw.length; i += 900) {
        Diag.dev('STANDINGS_NOTICE ${i ~/ 900} ${raw.substring(i, (i + 900).clamp(0, raw.length))}');
      }
    }
    return LeagueTable.fromJson(d ?? const <String, dynamic>{});
  }

  /// Last good answer per request (client 4 Nov: Sports "sometimes fails to
  /// load after a long wait"). A slow or failed request is retried once and
  /// then shows the last match list, marked stale, instead of an error.
  final Map<String, MatchDay> _lastDay = {};
  static const _sportsTimeout = Duration(seconds: 12);

  /// [date] as YYYY-MM-DD in the server's sports timezone (null = today).
  Future<MatchDay> fixtures({String? date, int? league, bool liveOnly = false}) async {
    final key = '${date ?? ''}|${league ?? ''}|$liveOnly';
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final day = await _fixturesOnce(date: date, league: league, liveOnly: liveOnly)
            .timeout(_sportsTimeout);
        _lastDay[key] = day;
        return day;
      } catch (e) {
        if (isNotInPackage(e)) rethrow;
        lastError = e;
        final kept = _lastDay[key];
        if (kept != null) {
          return MatchDay(date: kept.date, fixtures: kept.fixtures, stale: true, fetchedAt: kept.fetchedAt);
        }
      }
    }
    throw lastError!;
  }

  Future<MatchDay> _fixturesOnce({String? date, int? league, bool liveOnly = false}) async {
    final env = await _client.getEnvelope('/sports/fixtures', query: {
      if (date != null) 'date': date,
      if (league != null) 'league': '$league',
      if (liveOnly) 'live': '1',
    });
    final d = env.data ?? const <String, dynamic>{};
    final at = _fetchedAt(env);
    return MatchDay(
      date: _text(d['date']) ?? (date ?? ''),
      fixtures: [for (final f in _list(d['fixtures'])) MatchFixture.fromJson(f, fetchedAt: at)],
      stale: env.meta?['stale'] == true,
      fetchedAt: at,
    );
  }

  static DateTime? _fetchedAt(ApiEnvelope env) =>
      DateTime.tryParse('${env.meta?['fetchedAt'] ?? ''}')?.toLocal();

  Future<MatchDetail> match(int id) =>
      _withFallback(() => _matchOnce(id), _lastMatch[id], (v) => _lastMatch[id] = v);

  Future<MatchDetail> _matchOnce(int id) async {
    final env = await _client.getEnvelope('/sports/fixtures/$id');
    return MatchDetail.fromJson(
      env.data ?? const <String, dynamic>{},
      stale: env.meta?['stale'] == true,
      fetchedAt: _fetchedAt(env),
    );
  }
}
