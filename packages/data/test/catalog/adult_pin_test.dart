import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  var now = DateTime(2026, 11, 15, 12);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 11, 15, 12);
  });
  AdultPinLock lock() => AdultPinLock(clock: () => now);

  test('panel PIN (Stalker parent_password) unlocks; wrong one does not', () async {
    final l = lock();
    expect(await l.verify('1234', panelPin: '0000'), AdultPinResult.wrong);
    expect(l.isUnlocked, isFalse);
    expect(await l.verify('0000', panelPin: '0000'), AdultPinResult.ok);
    expect(l.isUnlocked, isTrue);
  });

  test('XPlayer PIN: set once, stored only as a salted hash, verified', () async {
    final l = lock();
    expect(await l.hasAppPin(), isFalse);
    await l.setAppPin('4321');
    expect(await l.hasAppPin(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().map((k) => '${prefs.get(k)}').join(), isNot(contains('4321')));
    l.lock();
    expect(await lock().verify('4321'), AdultPinResult.ok);
    expect(await lock().verify('1111'), AdultPinResult.wrong);
  });

  test('unlock lasts 30 minutes, or until the app goes to the background', () async {
    final l = lock();
    await l.verify('0000', panelPin: '0000');
    now = now.add(const Duration(minutes: 29));
    expect(l.isUnlocked, isTrue);
    now = now.add(const Duration(minutes: 2));
    expect(l.isUnlocked, isFalse);
    await l.verify('0000', panelPin: '0000');
    l.lock();
    expect(l.isUnlocked, isFalse);
  });

  test('5 wrong PINs → locked for a minute, even the right one', () async {
    final l = lock();
    for (var i = 0; i < 4; i++) {
      expect(await l.verify('9999', panelPin: '0000'), AdultPinResult.wrong);
    }
    expect(await l.verify('9999', panelPin: '0000'), AdultPinResult.locked);
    expect(await l.verify('0000', panelPin: '0000'), AdultPinResult.locked);
    now = now.add(const Duration(seconds: 61));
    expect(await l.verify('0000', panelPin: '0000'), AdultPinResult.ok);
  });

  test('clear forgets the XPlayer PIN (device sign-out)', () async {
    final l = lock();
    await l.setAppPin('1234');
    await l.clear();
    expect(await l.hasAppPin(), isFalse);
    expect(l.isUnlocked, isFalse);
  });
}
