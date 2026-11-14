// Sports payloads: `get_matches` (list) and `get_match` (one match page).

import '../remote/json_read.dart';
import 'json_util.dart';

enum FixtureStatus { scheduled, live, halftime, finished, postponed, cancelled, suspended, unknown }

class TeamRef {
  const TeamRef({required this.id, required this.name, this.shortName, this.logoUrl});
  final String id;
  final String name;
  final String? shortName;
  final String? logoUrl;

  static TeamRef? tryParse(Object? v) {
    final j = jsonMap(v);
    final id = jsonStr(j['id']);
    final name = jsonStr(j['name']);
    if (id == null || name == null) return null;
    return TeamRef(id: id, name: name, shortName: jsonStr(j['short']), logoUrl: jsonStr(j['logo']));
  }
}

class FixtureSummary {
  const FixtureSummary({
    required this.id,
    required this.status,
    required this.kickoffAt,
    required this.home,
    required this.away,
    this.minute,
    this.homeScore,
    this.awayScore,
    this.round,
    this.competition,
    this.isFeatured = false,
    this.hasChannels = false,
  });

  final String id;
  final FixtureStatus status;
  final DateTime kickoffAt;
  final TeamRef home;
  final TeamRef away;
  final int? minute;
  final int? homeScore;
  final int? awayScore;
  final String? round;
  final TeamRef? competition; // same shape: id, name, logo
  final bool isFeatured;
  final bool hasChannels;

  bool get isLive => status == FixtureStatus.live || status == FixtureStatus.halftime;

  static FixtureSummary? tryParse(Map<String, dynamic> j) {
    final id = jsonStr(j['id']);
    final kickoff = jsonDate(j['kickoff_at']);
    final home = TeamRef.tryParse(j['home']);
    final away = TeamRef.tryParse(j['away']);
    if (id == null || kickoff == null || home == null || away == null) return null;
    return FixtureSummary(
      id: id,
      status: jsonEnum(j['status'], FixtureStatus.values, FixtureStatus.unknown),
      kickoffAt: kickoff,
      home: home,
      away: away,
      minute: jsonInt(j['minute']),
      homeScore: jsonInt(j['home_score']),
      awayScore: jsonInt(j['away_score']),
      round: jsonStr(j['round']),
      competition: TeamRef.tryParse(j['competition']),
      isFeatured: jsonBool(j['is_featured']) ?? false,
      hasChannels: jsonBool(j['has_channels']) ?? false,
    );
  }

  static List<FixtureSummary> listFrom(Object? json) => (json is List ? json : const [])
      .whereType<Map>()
      .map((m) => tryParse(jsonMap(m)))
      .whereType<FixtureSummary>()
      .toList();
}

class FixturePlayer {
  const FixturePlayer({required this.name, this.number, this.position, this.starter = true, this.grid});
  final String name;
  final int? number;
  final String? position;
  final bool starter;
  final String? grid;
}

class FixtureLineup {
  const FixtureLineup({required this.teamId, this.formation, this.coach, this.players = const []});
  final String teamId;
  final String? formation;
  final String? coach;
  final List<FixturePlayer> players;

  List<FixturePlayer> get starters => players.where((p) => p.starter).toList();
  List<FixturePlayer> get bench => players.where((p) => !p.starter).toList();
}

class FixtureEvent {
  const FixtureEvent({required this.minute, required this.type, this.extra, this.teamId, this.player, this.assist, this.detail});
  final int minute;
  final int? extra;
  final String type; // goal, own_goal, penalty_goal, penalty_miss, yellow, red, substitution, var, other
  final String? teamId;
  final String? player;
  final String? assist;
  final String? detail;

  String get clock => extra == null ? "$minute'" : "$minute+$extra'";
}

/// Where to watch. The app matches [channelName]/[epgId]/[matchName] against
/// the user's panel; [channelId] points to the global channel catalog.
class FixtureChannel {
  const FixtureChannel({this.channelId, this.matchName, this.channelName, this.logoUrl, this.epgId, this.country, this.note});
  final String? channelId;
  final String? matchName;
  final String? channelName;
  final String? logoUrl;
  final String? epgId;
  final String? country;
  final String? note;
}

class FixtureDetail {
  const FixtureDetail({
    required this.summary,
    this.venue,
    this.lineups = const [],
    this.events = const [],
    this.channels = const [],
  });

  final FixtureSummary summary;
  final String? venue;
  final List<FixtureLineup> lineups;
  final List<FixtureEvent> events;
  final List<FixtureChannel> channels;

  static FixtureDetail? tryParse(Object? json) {
    final j = jsonMap(json);
    final m = jsonMap(j['match']);
    final home = TeamRef.tryParse(j['home']);
    final away = TeamRef.tryParse(j['away']);
    final kickoff = jsonDate(m['kickoff_at']);
    final id = jsonStr(m['id']);
    if (id == null || home == null || away == null || kickoff == null) return null;
    final comp = jsonMap(j['competition']);

    final summary = FixtureSummary(
      id: id,
      status: jsonEnum(m['status'], FixtureStatus.values, FixtureStatus.unknown),
      kickoffAt: kickoff,
      home: home,
      away: away,
      minute: jsonInt(m['minute']),
      homeScore: jsonInt(m['home_score']),
      awayScore: jsonInt(m['away_score']),
      round: jsonStr(m['round']),
      competition: jsonStr(comp['id']) == null
          ? null
          : TeamRef(
              id: jsonStr(comp['id'])!,
              name: jsonStr(comp['short_name']) ?? jsonStr(comp['name']) ?? '',
              logoUrl: jsonStr(comp['logo_url'])),
      isFeatured: jsonBool(m['is_featured']) ?? false,
    );

    return FixtureDetail(
      summary: summary,
      venue: jsonStr(m['venue']),
      lineups: [
        for (final l in jsonMapList(j['lineups']))
          if (jsonStr(l['team']) != null)
            FixtureLineup(
              teamId: jsonStr(l['team'])!,
              formation: jsonStr(l['formation']),
              coach: jsonStr(l['coach']),
              players: [
                for (final p in jsonMapList(l['players']))
                  if (jsonStr(p['name']) != null)
                    FixturePlayer(
                      name: jsonStr(p['name'])!,
                      number: jsonInt(p['number']),
                      position: jsonStr(p['position']),
                      starter: jsonBool(p['starter']) ?? true,
                      grid: jsonStr(p['grid']),
                    ),
              ],
            ),
      ],
      events: [
        for (final e in jsonMapList(j['events']))
          if (jsonInt(e['minute']) != null && jsonStr(e['type']) != null)
            FixtureEvent(
              minute: jsonInt(e['minute'])!,
              extra: jsonInt(e['extra']),
              type: jsonStr(e['type'])!,
              teamId: jsonStr(e['team']),
              player: jsonStr(e['player']),
              assist: jsonStr(e['assist']),
              detail: jsonStr(e['detail']),
            ),
      ],
      channels: [
        for (final c in jsonMapList(j['channels']))
          FixtureChannel(
            channelId: jsonStr(c['channel']),
            matchName: jsonStr(c['match']),
            channelName: jsonStr(c['name']),
            logoUrl: jsonStr(c['logo']),
            epgId: jsonStr(c['epg']),
            country: jsonStr(c['country']),
            note: jsonStr(c['note']),
          ),
      ],
    );
  }
}
