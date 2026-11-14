import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('Arabic channel names are channels, not ad or header rows', () {
    for (final n in ['قناة الجزيرة', 'روتانا سينما', 'شاهد', 'الجزيرة HD']) {
      expect(isProviderAdOrHeaderChannel(n), isFalse, reason: n);
    }
  });

  test('banner and symbol-only rows are still dropped', () {
    for (final n in ['### ALWAN ###', '#####', '=== X ===', '★ ★ ★', '---']) {
      expect(isProviderAdOrHeaderChannel(n), isTrue, reason: n);
    }
  });
}
