import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<PitchPlayer> _xi(String prefix, {bool grid = true}) {
  const formation = [4, 4, 2];
  final out = [PitchPlayer(name: '$prefix Keeper', number: 1, grid: grid ? '1:1' : null, position: 'G')];
  var n = 2;
  for (var line = 0; line < formation.length; line++) {
    for (var c = 1; c <= formation[line]; c++) {
      out.add(PitchPlayer(
        name: '$prefix P$n',
        number: n,
        grid: grid ? '${line + 2}:$c' : null,
        position: line == 0 ? 'D' : line == 2 ? 'F' : 'M',
      ));
      n++;
    }
  }
  return out;
}

Future<void> _pump(WidgetTester t, {required bool horizontal, bool grid = true}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: horizontal ? 900 : 380,
        height: horizontal ? 480 : 640,
        child: LineupPitch(
          horizontal: horizontal,
          home: PitchTeam(players: _xi('H', grid: grid), kitColor: pitchColor('#1d4ed8')),
          away: PitchTeam(players: _xi('A', grid: grid), kitColor: pitchColor('facc15')),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('vertical pitch: 22 players, keepers at the ends', (t) async {
    await _pump(t, horizontal: false);
    expect(find.text('Keeper'), findsNWidgets(2));
    expect(find.text('P11'), findsNWidgets(2));
    final homeKeeper = t.getCenter(find.text('Keeper').first);
    final awayKeeper = t.getCenter(find.text('Keeper').last);
    // One keeper near the bottom, the other near the top.
    expect((homeKeeper.dy - awayKeeper.dy).abs(), greaterThan(400));
    expect(t.takeException(), isNull);
  });

  testWidgets('horizontal pitch (TV): keepers left and right', (t) async {
    await _pump(t, horizontal: true);
    final a = t.getCenter(find.text('Keeper').first);
    final b = t.getCenter(find.text('Keeper').last);
    expect((a.dx - b.dx).abs(), greaterThan(600));
    expect(t.takeException(), isNull);
  });

  testWidgets('no grid: falls back to G/D/M/F lines', (t) async {
    await _pump(t, horizontal: false, grid: false);
    expect(find.text('P11'), findsNWidgets(2));
    expect(t.takeException(), isNull);
  });

  test('pitchColor parses hex', () {
    expect(pitchColor('#1d4ed8'), const Color(0xFF1D4ED8));
    expect(pitchColor('zz'), isNull);
    expect(pitchColor(null), isNull);
  });
}
