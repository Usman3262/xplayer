import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bytes over time become Mbps', () {
    // 100 MB in 8 s = 100 Mbps.
    expect(megabitsPerSecond(100000000, const Duration(seconds: 8)), closeTo(100, 0.001));
    expect(megabitsPerSecond(6250000, const Duration(seconds: 1)), closeTo(50, 0.001));
    expect(megabitsPerSecond(1000, Duration.zero), 0);
  });

  test('speed classes', () {
    SpeedClass q(double m) => SpeedTestResult(mbps: m, bytes: 1, elapsed: const Duration(seconds: 1), source: 't').quality;
    expect(q(300), SpeedClass.uhd);
    expect(q(25), SpeedClass.uhd);
    expect(q(24.9), SpeedClass.hd);
    expect(q(8), SpeedClass.hd);
    expect(q(5), SpeedClass.sd);
    expect(q(1), SpeedClass.poor);
  });
}
