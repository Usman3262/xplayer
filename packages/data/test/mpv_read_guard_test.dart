import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Play Console ANRs (Honor X9b, 6.0.23 / 6.0.32 / 6.0.33): mpv reads block
/// the main thread while the hardware decoder hangs. Reads only while the
/// picture clock is moving; a slow read switches reads off for 30 s.
void main() {
  final t0 = DateTime(2026, 11, 13, 12);
  Duration s(double v) => Duration(milliseconds: (v * 1000).round());

  test('no read until the clock is seen moving', () {
    final g = AppReadGuard(s(10));
    expect(g.allows(s(10), t0), isFalse);
    expect(g.allows(s(10.2), t0.add(s(0.2))), isTrue);
  });

  test('a clock that stopped for 1.5 s (hung decoder) blocks reads', () {
    final g = AppReadGuard(s(10));
    expect(g.allows(s(10.2), t0), isTrue);
    expect(g.allows(s(10.2), t0.add(s(1.0))), isTrue);
    expect(g.allows(s(10.2), t0.add(s(1.6))), isFalse);
    // Moving again: reads come back.
    expect(g.allows(s(10.5), t0.add(s(2.0))), isTrue);
  });

  test('a slow read switches reads off for 30 s', () {
    final g = AppReadGuard(s(10));
    expect(g.allows(s(10.2), t0), isTrue);
    g.tookLong(s(0.4), t0);
    expect(g.allows(s(10.4), t0.add(s(1))), isFalse);
    expect(g.allows(s(40), t0.add(s(29))), isFalse);
    expect(g.allows(s(40.5), t0.add(s(31))), isTrue);
    // A fast read changes nothing.
    g.tookLong(s(0.1), t0.add(s(31)));
    expect(g.allows(s(41), t0.add(s(31.5))), isTrue);
  });
}
