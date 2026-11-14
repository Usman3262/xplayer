import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

// Client 23 Oct round 3 #13: 12-hour match times with AM / PM.
void main() {
  test('12-hour clock', () {
    expect(matchClock(DateTime(2026, 10, 23, 18, 30)), '06:30 PM');
    expect(matchClock(DateTime(2026, 10, 23, 21, 0)), '09:00 PM');
    expect(matchClock(DateTime(2026, 10, 23, 0, 5)), '12:05 AM');
    expect(matchClock(DateTime(2026, 10, 23, 12, 0)), '12:00 PM');
    expect(matchClock(DateTime(2026, 10, 23, 9, 45)), '09:45 AM');
  });
}
