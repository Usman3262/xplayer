import 'package:data/data.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceTrustPolicy', () {
    test('never allows revoke of priority target', () {
      expect(
        DeviceTrustPolicy.canRevokeDevice(targetIsPriority: true),
        isFalse,
      );
      expect(
        DeviceTrustPolicy.canRevokeDevice(targetIsPriority: false),
        isTrue,
      );
    });

    test('revoke-all only when actor is priority if account has one', () {
      expect(
        DeviceTrustPolicy.canRevokeAll(
          actorIsPriority: false,
          accountHasPriority: true,
        ),
        isFalse,
      );
      expect(
        DeviceTrustPolicy.canRevokeAll(
          actorIsPriority: true,
          accountHasPriority: true,
        ),
        isTrue,
      );
      expect(
        DeviceTrustPolicy.canRevokeAll(
          actorIsPriority: false,
          accountHasPriority: false,
        ),
        isTrue,
      );
    });
  });
}
