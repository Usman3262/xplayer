import 'dart:io';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('avatar tokens round-trip; unknown or empty fall back to initials', () {
    for (final s in kProfileAvatars) {
      expect(avatarStyleFor(s.token)?.key, s.key);
    }
    expect(kProfileAvatars.map((s) => s.key).toSet().length, kProfileAvatars.length);
    expect(avatarStyleFor(null), isNull);
    expect(avatarStyleFor(''), isNull);
    expect(avatarStyleFor('https://example.com/a.png'), isNull);
    expect(avatarStyleFor('app:avatar/unknown'), isNull);
  });

  test('the picker offers the 30 illustrated faces; old icon avatars still draw (point 37)', () {
    expect(kProfileAvatars, hasLength(30));
    expect(kProfileAvatars.every((s) => s.asset != null), isTrue);
    expect(avatarStyleFor('app:avatar/face01')?.asset, 'assets/avatars/face01.png');
    expect(avatarStyleFor('app:avatar/face30')?.asset, 'assets/avatars/face30.png');
    expect(avatarStyleFor('app:avatar/neon')?.icon, isNotNull);
    for (final s in kProfileFaces) {
      expect(File('${s.asset}').existsSync(), isTrue, reason: s.asset);
    }
  });
}
