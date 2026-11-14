import 'sports_api.dart';

/// View figures for the Match Centre screens, shared by the phone and TV
/// apps (client design 20 Oct: key events with the running score,
/// head-to-head bars and boxes, Today / Tomorrow lists).

/// "58%" → 58, "1.42" → 1.42, null → 0.
double matchStatNumber(String? v) =>
    double.tryParse((v ?? '').replaceAll('%', '').trim()) ?? 0;

/// One row of "Key Match Events".
class MatchKeyEvent {
  const MatchKeyEvent({required this.event, required this.home, this.score});
  final MatchEvent event;
  final bool home;

  /// Running score after a goal ("2-1"), only when the goals in the event
  /// list add up to the fixture score (otherwise it could be wrong).
  final String? score;
}

bool _countsAsGoal(MatchEvent e) =>
    e.type == MatchEventType.goal && !(e.detail ?? '').toLowerCase().contains('missed');

extension MatchDetailView on MatchDetail {
  /// Events newest first, goals with the running score.
  List<MatchKeyEvent> keyEvents() {
    final homeId = fixture.home.id;
    var h = 0;
    var a = 0;
    final rows = <MatchKeyEvent>[];
    final scores = <String?>[];
    for (final e in events) {
      String? score;
      if (_countsAsGoal(e)) {
        if (e.teamId == homeId) {
          h++;
        } else {
          a++;
        }
        score = '$h-$a';
      }
      scores.add(score);
      rows.add(MatchKeyEvent(event: e, home: e.teamId == homeId));
    }
    final consistent =
        fixture.homeGoals == null || (fixture.homeGoals == h && fixture.awayGoals == a);
    return [
      for (var i = rows.length - 1; i >= 0; i--)
        MatchKeyEvent(event: rows[i].event, home: rows[i].home, score: consistent ? scores[i] : null),
    ];
  }

  TeamStatistics? statsFor(int teamId) {
    for (final s in statistics) {
      if (s.teamId == teamId) return s;
    }
    return null;
  }

  /// Both teams' value for a provider statistic, or null when either is
  /// missing.
  (String, String)? statPair(String type) {
    final h = statsFor(fixture.home.id)?.values[type];
    final a = statsFor(fixture.away.id)?.values[type];
    if (h == null && a == null) return null;
    if (statsFor(fixture.home.id) == null || statsFor(fixture.away.id) == null) return null;
    return (h ?? '0', a ?? '0');
  }
}

/// The backend groups matches by day in `SPORTS_TIMEZONE` (Asia/Riyadh,
/// UTC+3, no daylight saving). "Today" must be that day too: after midnight
/// in Pakistan it is still yesterday in Riyadh, and asking for the next day
/// hit the provider's Free-plan "future dates" refusal, so the TV showed
/// "No matches on this day" (TCL test, 21 Oct 00:44 PKT).
const sportsUtcOffset = Duration(hours: 3);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Match day ("YYYY-MM-DD") of [t] on the sports calendar.
String matchSportsDay(DateTime t) => _ymd(t.toUtc().add(sportsUtcOffset));

/// Today and Tomorrow on the sports calendar ("YYYY-MM-DD").
List<String> matchTodayTomorrow([DateTime? now]) {
  final r = (now ?? DateTime.now()).toUtc().add(sportsUtcOffset);
  return [_ymd(r), _ymd(DateTime.utc(r.year, r.month, r.day + 1))];
}

/// Yesterday, Today and Tomorrow on the sports calendar (client 21 Oct:
/// "add a Yesterday section").
List<String> matchThreeDays([DateTime? now]) {
  final r = (now ?? DateTime.now()).toUtc().add(sportsUtcOffset);
  return [
    _ymd(DateTime.utc(r.year, r.month, r.day - 1)),
    _ymd(r),
    _ymd(DateTime.utc(r.year, r.month, r.day + 1)),
  ];
}
