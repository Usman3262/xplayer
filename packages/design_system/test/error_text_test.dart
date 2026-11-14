import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player errors are shown in the app language', () {
    final ar = AppCopy.ofLanguage('ar');
    final en = AppCopy.ofLanguage('en');
    const raw = 'No access token stored. Please sign in again.';
    expect(en.errorText(raw), raw);
    expect(ar.errorText(raw), isNot(raw));
    expect(ar.errorText(raw), contains('تسجيل الدخول'));
    expect(ar.errorText('Android playback failed. Try the default player.'), contains('المشغّل'));
    // Unknown text stays as is (the screen lays it out left-to-right).
    expect(ar.errorText('Something new'), 'Something new');
  });
}
