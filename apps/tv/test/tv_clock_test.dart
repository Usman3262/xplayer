import 'package:player_tv/core/tv_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('12-hour clock in English', () {
    expect(tvClock12(0, 5, arabic: false), '12:05 AM');
    expect(tvClock12(9, 30, arabic: false), '9:30 AM');
    expect(tvClock12(12, 0, arabic: false), '12:00 PM');
    expect(tvClock12(20, 7, arabic: false), '8:07 PM');
    expect(tvClock12(23, 59, arabic: false), '11:59 PM');
  });

  test('12-hour clock in Arabic', () {
    expect(tvClock12(0, 5, arabic: true), '12:05 ص');
    expect(tvClock12(20, 7, arabic: true), '8:07 م');
  });
}
