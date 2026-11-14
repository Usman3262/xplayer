import 'package:data/src/remote/notifications_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isAppVersionNewer', () {
    test('compares semver parts', () {
      expect(isAppVersionNewer('6.0.23', '6.0.18'), isTrue);
      expect(isAppVersionNewer('6.0.18', '6.0.23'), isFalse);
      expect(isAppVersionNewer('6.1.0', '6.0.99'), isTrue);
      expect(isAppVersionNewer('6.0.18', '6.0.18'), isFalse);
    });
  });
}
