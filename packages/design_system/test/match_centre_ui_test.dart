import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Layout checks for the Match Centre design widgets at phone and TV
// sizes: no overflow, top player caption shown, both teams' labels.

List<McPlayer> _xi() => [
      const McPlayer(name: 'Keeper One', number: 1, grid: '1:1'),
      for (var c = 1; c <= 4; c++) McPlayer(name: 'Defender Long Name $c', number: c + 1, grid: '2:$c'),
      for (var c = 1; c <= 3; c++) McPlayer(name: 'Midfielder $c', number: c + 5, grid: '3:$c', card: c == 2 ? 'yellow' : null),
      const McPlayer(name: 'Playmaker Ten', number: 10, grid: '4:1'),
      const McPlayer(name: 'Striker Nine', number: 9, grid: '5:1'),
      const McPlayer(name: 'Striker Eleven', number: 11, grid: '5:2', subbedOff: true),
    ];

Widget _page(Size size, double scale, {bool compact = false}) => MaterialApp(
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                McScoreHeader(
                  compact: compact,
                  scale: scale,
                  competition: 'UEFA Champions League',
                  round: 'Quarter-final - 2nd Leg',
                  venue: 'Santiago Bernabéu, Madrid',
                  livePill: "LIVE 67'",
                  statusLine: 'Second Half',
                  home: const McTeamHeader(name: 'Real Madrid', subtitle: 'Manager: Carlo Ancelotti • 4-3-1-2'),
                  away: const McTeamHeader(name: 'Manchester City', subtitle: 'Manager: Pep Guardiola • 4-2-3-1'),
                  homeGoals: 2,
                  awayGoals: 1,
                ),
                SizedBox(
                  height: compact ? 520 : 420,
                  child: McTeamPitch(
                    scale: scale,
                    players: _xi(),
                    highlight: 'Playmaker Ten',
                    highlightCaption: 'Rating 8.8 • 1 goal • 4 key passes',
                    attackLabel: 'Attack ↑',
                  ),
                ),
                McBenchStrip(
                  scale: scale,
                  title: 'Bench reserves (Real Madrid)',
                  players: [for (var i = 12; i < 18; i++) McBenchPlayer(name: 'Sub $i', number: i, detail: 'MF • Bench')],
                ),
                McEventsCard(
                  scale: scale,
                  title: 'Key Match Events',
                  events: const [
                    McEvent(kind: McEventKind.goalHome, title: 'Vinícius Júnior (2-1)', subtitle: 'Assist: Jude Bellingham', minute: "64'"),
                    McEvent(kind: McEventKind.yellow, title: 'Rodri', subtitle: 'Yellow card', minute: "51'", home: false),
                    McEvent(kind: McEventKind.sub, title: 'Substitution: A ⇄ B', minute: "45+2'"),
                  ],
                ),
                McHeadToHead(
                  scale: scale,
                  title: 'Live Head-to-Head Stats',
                  homeLabel: 'Real Madrid',
                  awayLabel: 'Manchester City',
                  bars: const [
                    McStatBar(label: 'Possession', home: '42%', away: '58%', homeValue: 42, awayValue: 58),
                    McStatBar(label: 'Expected goals (xG)', home: '1.84', away: '1.12', homeValue: 1.84, awayValue: 1.12),
                  ],
                  boxes: const [
                    McStatBox(label: 'Shots (target)', value: '14 (6) - 9 (3)'),
                    McStatBox(label: 'Pass accuracy', value: '88% - 91%'),
                    McStatBox(label: 'Corners', value: '7 - 3'),
                  ],
                ),
                McMatchCard(
                  width: 260,
                  scale: scale,
                  competition: 'Premier League',
                  round: 'Regular Season - 8',
                  homeName: 'Wolverhampton Wanderers',
                  awayName: 'Brighton & Hove Albion',
                  kickoff: '09:00 PM',
                  statusText: 'Tomorrow 21:00',
                ),
                McStandingsTable(
                  scale: scale,
                  title: 'Pro League',
                  trailing: '2024/25',
                  headers: const ['#', 'Team', 'P', 'W', 'D', 'L', 'Goals', '+/-', 'Pts', 'Form'],
                  rows: const [
                    McStandingRow(rank: 1, team: 'Al-Hilal', played: 34, win: 28, draw: 4, lose: 2, goalsFor: 101, goalsAgainst: 23, goalDiff: 78, points: 88, form: 'WWDWW', zone: 'Promotion - AFC Champions League Elite', highlight: true),
                    McStandingRow(rank: 18, team: 'Al-Nassr with a long name', played: 34, win: 5, draw: 6, lose: 23, goalsFor: 30, goalsAgainst: 71, goalDiff: -41, points: 21, form: 'LLDLW', zone: 'Relegation'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

void main() {
  for (final (name, size, scale, compact) in [
    ('phone 360', const Size(360, 780), 1.0, true),
    ('phone 430', const Size(430, 932), 1.0, true),
    ('tv 960', const Size(960, 540), 0.9, false),
  ]) {
    testWidgets('match centre widgets lay out without overflow ($name)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_page(size, scale, compact: compact));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('RATING 8.8 • 1 GOAL'), findsOneWidget);
      expect(find.text('PLAYMAKER TEN'), findsNothing);
      expect(find.text('TEN'), findsOneWidget);
      expect(find.text('Key Match Events'), findsOneWidget);
    });
  }
}
