import 'package:player_mobile/core/screen_awake.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client 20 Oct: screensaver after exactly 10 min. A replacing player route
/// acquires before the old one releases; the screen must stay awake.
void main() {
  final calls = <bool>[];
  setUp(() {
    calls.clear();
    ScreenAwake.resetForTest();
    ScreenAwake.applyOverride = calls.add;
  });

  test('route replacement: new player on, old player off -> still awake', () {
    final oldPlayer = Object(), newPlayer = Object();
    ScreenAwake.acquire(oldPlayer);
    ScreenAwake.acquire(newPlayer); // next episode initState
    ScreenAwake.release(oldPlayer); // old route dispose afterwards
    expect(ScreenAwake.holders, 1);
    // Re-applying "on" for the second player is fine; "off" is not.
    expect(calls.contains(false), isFalse, reason: 'no disable while a player is open');
    expect(calls.last, isTrue);
    ScreenAwake.release(newPlayer);
    expect(calls.last, isFalse);
  });

  test('preview and fullscreen together', () {
    final preview = Object(), player = Object();
    ScreenAwake.acquire(preview);
    ScreenAwake.acquire(player);
    ScreenAwake.release(preview);
    expect(calls.last, isTrue);
    ScreenAwake.release(player);
    expect(calls.last, isFalse);
  });

  test('double release is harmless', () {
    final a = Object();
    ScreenAwake.acquire(a);
    ScreenAwake.release(a);
    ScreenAwake.release(a);
    expect(calls, [true, false]);
  });
}
