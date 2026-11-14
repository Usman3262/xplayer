import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart' show IconData, Icons;

/// Maps the Match Centre API models (`package:data`) to the shared design
/// widgets (`match_centre_ui.dart`). The phone and TV apps keep identical
/// copies of this file (apps/mobile and apps/tv, features/sports/).

McTeamHeader teamHeader(AppCopy copy, MatchDetail m, MatchTeam t) {
  final l = m.lineupFor(t.id);
  final sub = [
    if ((l?.coach ?? '').isNotEmpty) copy.matchManager(l!.coach!),
    if ((l?.formation ?? '').isNotEmpty) l!.formation!,
  ].join(' • ');
  return McTeamHeader(name: t.nameFor(mpLang(copy)), logo: t.logo, subtitle: sub.isEmpty ? null : sub);
}

/// Who came on / went off, from substitution events checked against the
/// lineup (providers differ on which field holds which player). Matched by
/// player id; names only when an id is missing (names differ between the
/// events and lineups endpoints: "Matias Soule" vs "M. Soulé").
({Map<String, String> on, Set<String> off}) _subs(MatchDetail m, MatchLineup l) {
  final starterIds = {for (final p in l.startXI) if (p.id != null) p.id!: p.name};
  final benchIds = {for (final p in l.substitutes) if (p.id != null) p.id!: p.name};
  final starters = {for (final p in l.startXI) p.name};
  final bench = {for (final p in l.substitutes) p.name};
  final on = <String, String>{};
  final off = <String>{};
  for (final e in m.events) {
    if (e.type != MatchEventType.subst || e.teamId != l.team.id) continue;
    for (final (id, name) in [(e.playerId, e.player), (e.assistId, e.assist)]) {
      if (id != null && benchIds.containsKey(id)) {
        on[benchIds[id]!] = e.minuteLabel;
      } else if (id != null && starterIds.containsKey(id)) {
        off.add(starterIds[id]!);
      } else if (name != null && bench.contains(name)) {
        on[name] = e.minuteLabel;
      } else if (name != null && starters.contains(name)) {
        off.add(name);
      }
    }
  }
  return (on: on, off: off);
}

/// Yellow / red card per lineup player name, matched by id first.
Map<String, String> _cards(MatchDetail m, MatchLineup l) {
  final byId = {for (final p in [...l.startXI, ...l.substitutes]) if (p.id != null) p.id!: p.name};
  final out = <String, String>{};
  for (final e in m.events) {
    if (e.type != MatchEventType.card || e.teamId != l.team.id) continue;
    final name = (e.playerId != null ? byId[e.playerId] : null) ?? e.player;
    if (name == null) continue;
    // A red card wins over an earlier yellow.
    if (out[name] != 'red') out[name] = e.isRedCard ? 'red' : 'yellow';
  }
  return out;
}

/// Goals per lineup player name (client 5 Nov: a ball above the scorer, as on
/// LG). Matched by player id, then by name, then by surname (the events and
/// lineups endpoints spell names differently). Own goals and missed penalties
/// are not the player's goals.
Map<String, int> _goals(MatchDetail m, MatchLineup l) {
  final players = [...l.startXI, ...l.substitutes];
  final byId = {for (final p in players) if (p.id != null) p.id!: p.name};
  final names = {for (final p in players) p.name};
  String last(String n) {
    final parts = n.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? n.toLowerCase() : parts.last.toLowerCase();
  }
  final out = <String, int>{};
  for (final e in m.events) {
    if (e.type != MatchEventType.goal || e.teamId != l.team.id) continue;
    final d = (e.detail ?? '').toLowerCase();
    if (d.contains('own goal') || d.contains('missed')) continue;
    var name = e.playerId != null ? byId[e.playerId] : null;
    final raw = e.player;
    if (name == null && raw != null) {
      if (names.contains(raw)) {
        name = raw;
      } else {
        final hits = players.where((p) => last(p.name) == last(raw)).toList();
        if (hits.length == 1) name = hits.first.name;
      }
    }
    if (name == null) continue;
    out[name] = (out[name] ?? 0) + 1;
  }
  return out;
}

McTeamPitch matchTeamPitch(AppCopy copy, MatchDetail m, MatchLineup l, {double scale = 1}) {
  final top = m.topPlayer(l.team.id);
  String? highlight;
  if (top != null) {
    for (final p in l.startXI) {
      if ((top.id != null && p.id == top.id) || p.name == top.name) highlight = p.name;
    }
  }
  final subs = _subs(m, l);
  final cards = _cards(m, l);
  final goals = _goals(m, l);
  return McTeamPitch(
    scale: scale,
    kitColor: l.kitColor,
    numberColor: l.kitNumberColor,
    attackLabel: '${copy.matchAttack} ↑',
    highlight: highlight,
    highlightCaption: top == null || highlight == null
        ? null
        : copy.matchRatingCaption(top.rating!.toStringAsFixed(1), top.goals ?? 0, top.keyPasses ?? 0),
    players: [
      for (final p in l.startXI)
        McPlayer(
          name: p.name,
          number: p.number,
          grid: p.grid,
          position: p.position,
          photo: p.photo,
          card: cards[p.name],
          subbedOff: subs.off.contains(p.name),
          goals: goals[p.name] ?? 0,
        ),
    ],
  );
}

McBenchStrip matchBenchStrip(AppCopy copy, MatchDetail m, MatchLineup l, {double scale = 1}) {
  final subs = _subs(m, l);
  return McBenchStrip(
    scale: scale,
    title: copy.matchBench(l.team.nameFor(mpLang(copy))),
    players: [
      for (final p in l.substitutes)
        McBenchPlayer(
          name: p.name,
          number: p.number,
          photo: p.photo,
          detail: [
            if ((p.position ?? '').isNotEmpty) p.position!,
            subs.on.containsKey(p.name) ? copy.matchCameOn(subs.on[p.name]!) : copy.matchOnBench,
          ].join(' • '),
        ),
    ],
  );
}

McEventsCard matchEventsCard(AppCopy copy, MatchDetail m, {double scale = 1, int? limit}) {
  final rows = m.keyEvents();
  final shown = limit == null ? rows : rows.take(limit).toList();
  return McEventsCard(
    scale: scale,
    title: copy.matchKeyEvents,
    emptyText: copy.matchNoEvents,
    events: [
      for (final r in shown)
        McEvent(
          home: r.home,
          minute: r.event.minuteLabel,
          kind: switch (r.event.type) {
            MatchEventType.goal => r.home ? McEventKind.goalHome : McEventKind.goalAway,
            MatchEventType.card => r.event.isRedCard ? McEventKind.red : McEventKind.yellow,
            MatchEventType.subst => McEventKind.sub,
            MatchEventType.varCheck => McEventKind.varCheck,
            MatchEventType.other => McEventKind.other,
          },
          title: switch (r.event.type) {
            MatchEventType.goal => [r.event.player ?? '', if (r.score != null) '(${r.score})'].join(' '),
            MatchEventType.subst => copy.matchSubstitution(r.event.player ?? '', r.event.assist ?? ''),
            _ => r.event.player ?? r.event.detail ?? '',
          },
          subtitle: switch (r.event.type) {
            MatchEventType.goal => [
              if (r.event.assist != null) copy.matchAssist(r.event.assist!),
              if (r.event.detail != null && r.event.detail != 'Normal Goal') r.event.detail!,
            ].join(' • '),
            MatchEventType.card => r.event.isRedCard ? copy.matchRedCard : copy.matchYellowCard,
            MatchEventType.varCheck => [copy.matchVar, if (r.event.detail != null) r.event.detail!].join(' • '),
            _ => r.event.detail,
          },
        ),
    ],
  );
}

/// Design: possession and xG bars, shots (target) / pass accuracy /
/// corners boxes. [all] adds every other statistic as a bar (phone tab).
McHeadToHead matchHeadToHead(AppCopy copy, MatchDetail m, {bool all = false, double scale = 1}) {
  final f = m.fixture;
  const featured = {'Ball Possession', 'expected_goals', 'Total Shots', 'Shots on Goal', 'Passes %', 'Corner Kicks'};
  McStatBar? bar(String type, String label) {
    final p = m.statPair(type);
    if (p == null) return null;
    return McStatBar(
      label: label,
      home: p.$1,
      away: p.$2,
      homeValue: matchStatNumber(p.$1),
      awayValue: matchStatNumber(p.$2),
    );
  }

  final bars = <McStatBar>[
    ?bar('Ball Possession', copy.matchPossession),
    ?bar('expected_goals', copy.matchXg),
    if (all)
      for (final t in m.statsFor(f.home.id)?.values.keys ?? const <String>[])
        if (!featured.contains(t)) ?bar(t, copy.matchStat(t)),
  ];
  final shots = m.statPair('Total Shots');
  final onTarget = m.statPair('Shots on Goal');
  final pass = m.statPair('Passes %');
  final corners = m.statPair('Corner Kicks');
  final boxes = <McStatBox>[
    if (shots != null)
      McStatBox(
        label: copy.matchShotsTarget,
        value: onTarget == null
            ? '${shots.$1} - ${shots.$2}'
            : '${shots.$1} (${onTarget.$1}) - ${shots.$2} (${onTarget.$2})',
      ),
    if (pass != null) McStatBox(label: copy.matchPassAccuracy, value: '${pass.$1} - ${pass.$2}'),
    if (corners != null) McStatBox(label: copy.matchCorners, value: '${corners.$1} - ${corners.$2}'),
  ];
  return McHeadToHead(
    scale: scale,
    title: f.status.live ? copy.matchLiveHeadToHead : copy.matchHeadToHead,
    homeLabel: f.home.nameFor(mpLang(copy)),
    awayLabel: f.away.nameFor(mpLang(copy)),
    bars: bars,
    boxes: boxes,
    emptyText: copy.matchNoStats,
  );
}

/// Groups holding either team, or all groups when neither is found.
List<List<StandingRow>> matchStandingGroups(LeagueTable t, MatchFixture f) {
  final mine = [
    for (final g in t.groups)
      if (g.any((r) => r.team.id == f.home.id || r.team.id == f.away.id)) g,
  ];
  return mine.isNotEmpty ? mine : t.groups;
}

/// Table rows for [view] (client 23 Oct: P, W, D, L, goals, +/-, points and
/// the zone colours; zones only on the overall table).
List<McStandingRow> matchStandingRows(
  List<StandingRow> g,
  MatchFixture f, [
  String lang = 'en',
  StandingsView view = StandingsView.overall,
]) => [
  for (final e in standingsFor(g, view))
    McStandingRow(
      rank: e.rank,
      team: e.row.team.nameFor(lang),
      logo: e.row.team.logo,
      played: e.stats.played,
      win: e.stats.win,
      draw: e.stats.draw,
      lose: e.stats.lose,
      goalsFor: e.stats.goalsFor,
      goalsAgainst: e.stats.goalsAgainst,
      goalDiff: view == StandingsView.overall ? e.row.goalsDiff : e.stats.goalsDiff,
      points: view == StandingsView.overall ? e.row.points : e.stats.points,
      form: e.row.form,
      zone: view == StandingsView.overall ? e.row.description : null,
      highlight: e.row.team.id == f.home.id || e.row.team.id == f.away.id,
    ),
];

// ── Approved reference design (client 22 Oct): match_page_ui.dart ────────

/// 'ar' when the app is in Arabic (team / league names from the server).
String mpLang(AppCopy copy) => copy.lang == AppLang.ar ? 'ar' : 'en';

MpScoreCard mpScoreCard(AppCopy copy, MatchDetail m, {double scale = 1, DateTime? now}) {
  final f = m.fixture;
  final lang = mpLang(copy);
  final live = f.status.live || f.status.short == 'HT';
  return MpScoreCard(
    scale: scale,
    leagueName: f.league.nameFor(lang),
    leagueLogo: f.league.logo,
    homeName: f.home.nameFor(lang),
    awayName: f.away.nameFor(lang),
    homeLogo: f.home.logo,
    awayLogo: f.away.logo,
    homeGoals: f.homeGoals,
    awayGoals: f.awayGoals,
    liveLabel: live && !f.liveStale(now ?? DateTime.now()) ? copy.matchLiveBadge : null,
    clock: live
        ? (f.status.short == 'HT'
            ? copy.matchHalfTime
            : f.liveStale(now ?? DateTime.now())
                ? copy.matchUpdating
                : (f.liveClock(now ?? DateTime.now()) ?? (f.status.elapsed == null ? null : "${f.status.elapsed}'")))
        : (f.kickoff == null ? null : _hm(f.kickoff!)),
    statusText: f.status.finished ? copy.matchFullTime : (f.status.notStarted ? copy.matchKickoff : null),
  );
}

/// The provider's live status ("First Half", "Second Half"…) in the app
/// language; unknown codes keep the provider's text.
String mpLiveStatus(AppCopy copy, MatchFixture f) {
  if (copy.lang != AppLang.ar) return f.status.long;
  return switch (f.status.short) {
    '1H' => 'الشوط الأول',
    'HT' => 'استراحة بين الشوطين',
    '2H' => 'الشوط الثاني',
    'ET' => 'الوقت الإضافي',
    'BT' => 'استراحة قبل الوقت الإضافي',
    'P' => 'ركلات الترجيح',
    'SUSP' => 'المباراة معلقة',
    'INT' => 'المباراة متوقفة',
    _ => f.status.long,
  };
}

/// The provider's round ("Regular Season - 11", "League Stage - 3",
/// "Quarter-finals"…) in the app language; other rounds keep the provider's text.
String? mpRound(AppCopy copy, String? round) {
  if (round == null || round.isEmpty || copy.lang != AppLang.ar) return round;
  final m = RegExp(r'^(.*?)\s*-\s*(\d+)$').firstMatch(round.trim());
  final stage = (m?.group(1) ?? round).trim().toLowerCase();
  final n = m?.group(2);
  const stages = {
    'regular season': 'الجولة',
    'league stage': 'مرحلة الدوري - الجولة',
    'group stage': 'دور المجموعات - الجولة',
    'qualifying round': 'التصفيات - الجولة',
    'play-offs': 'الملحق',
    'round of 32': 'دور الـ32',
    'round of 16': 'دور الـ16',
    'quarter-finals': 'ربع النهائي',
    'semi-finals': 'نصف النهائي',
    'final': 'النهائي',
  };
  final ar = stages[stage];
  if (ar == null) return round;
  return n == null ? ar : '$ar $n';
}

String _hm(DateTime t) => matchClock(t);

List<MpPlayer> mpStarters(MatchDetail m, MatchLineup l) {
  final subs = _subs(m, l);
  final cards = _cards(m, l);
  final goals = _goals(m, l);
  return [
    for (final p in l.startXI)
      MpPlayer(
        name: p.name,
        number: p.number,
        grid: p.grid,
        position: p.position,
        photo: p.photo,
        card: cards[p.name],
        subbedOff: subs.off.contains(p.name),
        goals: goals[p.name] ?? 0,
      ),
  ];
}

List<MpBenchPlayer> mpBench(MatchDetail m, MatchLineup l) {
  final subs = _subs(m, l);
  final goals = _goals(m, l);
  return [
    for (final p in l.substitutes)
      MpBenchPlayer(name: p.name, number: p.number, photo: p.photo, cameOn: subs.on[p.name], goals: goals[p.name] ?? 0),
  ];
}

List<MpEvent> mpEvents(AppCopy copy, MatchDetail m, {int? limit}) {
  final f = m.fixture;
  final rows = m.keyEvents();
  final shown = limit == null ? rows : rows.take(limit).toList();
  return [
    for (final r in shown)
      MpEvent(
        minute: r.event.minuteLabel,
        kind: switch (r.event.type) {
          MatchEventType.goal => MpEventKind.goal,
          MatchEventType.card => r.event.isRedCard ? MpEventKind.red : MpEventKind.yellow,
          MatchEventType.subst => MpEventKind.sub,
          MatchEventType.varCheck => MpEventKind.varCheck,
          MatchEventType.other => MpEventKind.other,
        },
        label: switch (r.event.type) {
          MatchEventType.goal => copy.matchGoal,
          MatchEventType.card => r.event.isRedCard ? copy.matchRedCard : copy.matchYellowCard,
          MatchEventType.subst => copy.matchSubstitutionLabel,
          MatchEventType.varCheck => copy.matchVar,
          MatchEventType.other => r.event.detail ?? '',
        },
        // Provider: for a substitution `player` went off, `assist` came on.
        player: r.event.player ?? r.event.detail ?? '',
        second: r.event.type == MatchEventType.subst ? r.event.assist : null,
        teamLogo: r.home ? f.home.logo : f.away.logo,
        score: r.score?.replaceAll('-', ' - '),
      ),
  ];
}

/// The reference's stat rows; [all] adds every other statistic.
List<MpStat> mpStats(AppCopy copy, MatchDetail m, {bool all = false}) {
  const main = [
    'Ball Possession',
    'Total Shots',
    'Shots on Goal',
    'Corner Kicks',
    'Total passes',
    'Passes %',
    'Fouls',
    'Yellow Cards',
    'Red Cards',
  ];
  String label(String t) => switch (t) {
        'Ball Possession' => copy.matchPossession,
        'Total Shots' => copy.matchShots,
        'Shots on Goal' => copy.matchShotsOnTarget,
        'Corner Kicks' => copy.matchCorners,
        'Total passes' => copy.matchPasses,
        'Passes %' => copy.matchPassAccuracy,
        'Fouls' => copy.matchFoulsLabel,
        'Yellow Cards' => copy.matchYellowCards,
        'Red Cards' => copy.matchRedCards,
        _ => copy.matchStat(t),
      };
  MpStat? stat(String t) {
    final p = m.statPair(t);
    if (p == null) return null;
    String v(String x) => x == 'null' || x.isEmpty ? '0' : x;
    return MpStat(
      label: label(t),
      home: v(p.$1),
      away: v(p.$2),
      homeValue: matchStatNumber(p.$1),
      awayValue: matchStatNumber(p.$2),
    );
  }

  return [
    for (final t in main) ?stat(t),
    if (all)
      for (final t in m.statsFor(m.fixture.home.id)?.values.keys ?? const <String>[])
        if (!main.contains(t)) ?stat(t),
  ];
}

/// Overview (client 23 Oct): date, kickoff, status / result, competition
/// with its logo, round, stadium, referee, and the channels when known.
List<(IconData, String, String, String?)> mpInfo(AppCopy copy, MatchDetail m, {DateTime? now}) {
  final f = m.fixture;
  final lang = mpLang(copy);
  final k = f.kickoff;
  final score = f.hasScore ? '${f.homeGoals} - ${f.awayGoals}' : null;
  final at = now ?? DateTime.now();
  final String status;
  if (f.status.finished) {
    status = [f.status.short == 'FT' ? copy.matchFullTime : f.status.long, ?score].join('  ');
  } else if (f.status.short == 'HT') {
    status = [copy.matchHalfTime, ?score].join('  ');
  } else if (f.status.live) {
    status = f.liveStale(at)
        ? copy.matchUpdating
        : ['${copy.matchLive} ${f.liveClock(at) ?? ''}'.trim(), ?score].join('  ');
  } else {
    status = copy.matchNotStarted;
  }
  return [
    if (k != null)
      (Icons.event_outlined, copy.matchDate,
          '${k.year}-${k.month.toString().padLeft(2, '0')}-${k.day.toString().padLeft(2, '0')}', null),
    if (k != null) (Icons.schedule_outlined, copy.matchTime, _hm(k), null),
    (Icons.sports_score_outlined, copy.matchStatusLabel, status, null),
    (Icons.emoji_events_outlined, copy.matchCompetition, f.league.nameFor(lang), f.league.logo),
    if ((f.league.round ?? '').isNotEmpty) (Icons.flag_outlined, copy.matchRound, mpRound(copy, f.league.round)!, null),
    if ((f.venue ?? '').isNotEmpty)
      (Icons.stadium_outlined, copy.matchVenue, [f.venue, f.city].whereType<String>().join(', '), null),
    if ((f.referee ?? '').isNotEmpty) (Icons.sports_outlined, copy.matchReferee, f.referee!, null),
    if (f.channels.isNotEmpty) (Icons.live_tv_outlined, copy.matchChannelsLabel, f.channels.join(', '), null),
  ];
}
