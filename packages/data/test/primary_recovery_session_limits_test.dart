import 'package:data/src/remote/api_exception.dart';
import 'package:data/src/remote/auth_models.dart';
import 'package:data/src/remote/app_media_repository.dart';
import 'package:data/src/remote/media_models.dart';
import 'package:test/test.dart';

void main() {
  group('AccountFeatures', () {
    test('new flags default true when features map omits keys', () {
      final f = AccountFeatures.fromJson({
        'deviceLoginApproval': true,
      });
      expect(f.deviceLoginApproval, isTrue);
      expect(f.primaryRecovery, isTrue);
      expect(f.playbackTakeover, isTrue);
      expect(f.deviceHeartbeat, isTrue);
    });

    test('explicit false is respected', () {
      final f = AccountFeatures.fromJson({
        'primaryRecovery': false,
        'playbackTakeover': false,
        'deviceHeartbeat': false,
      });
      expect(f.primaryRecovery, isFalse);
      expect(f.playbackTakeover, isFalse);
      expect(f.deviceHeartbeat, isFalse);
    });
  });

  group('LoginChallengeDto recovery fields', () {
    test('parses recovery enrichment', () {
      final dto = LoginChallengeDto.fromJson({
        'challengeId': 'c1',
        'status': 'PENDING',
        'primaryUnreachable': true,
        'recoveryAvailable': true,
        'recoveryMethods': ['totp', 'email_otp'],
      });
      expect(dto.isPending, isTrue);
      expect(dto.primaryUnreachable, isTrue);
      expect(dto.recoveryAvailable, isTrue);
      expect(dto.canOfferRecovery, isTrue);
      expect(dto.recoveryMethods, ['totp', 'email_otp']);
    });
  });

  group('DeviceDto', () {
    test('unreachable and STALE', () {
      final dto = DeviceDto.fromJson({
        'id': 'd1',
        'platform': 'ANDROID',
        'name': 'Phone',
        'status': 'STALE',
        'unreachable': true,
        'isPriority': true,
      });
      expect(dto.unreachable, isTrue);
      expect(dto.isStale, isTrue);
      expect(dto.isPriority, isTrue);
    });
  });

  group('PrimaryRecoveryStartDto', () {
    test('parses methods', () {
      final dto = PrimaryRecoveryStartDto.fromJson({
        'recoveryId': 'r1',
        'methods': ['totp', 'recovery_code'],
        'expiresAt': '2026-10-13T12:00:00.000Z',
      });
      expect(dto.recoveryId, 'r1');
      expect(dto.methods, ['totp', 'recovery_code']);
    });
  });

  group('ApiException codes', () {
    test('helpers and holder', () {
      final e = ApiException(
        'held',
        statusCode: 409,
        code: 'PLAYBACK_LEASE_HELD',
        data: {
          'holder': {'deviceId': 'd9', 'playbackId': 'p9'},
        },
      );
      expect(e.isPlaybackLeaseHeld, isTrue);
      expect(e.holder?['deviceId'], 'd9');
      expect(
        ApiException('x', code: 'DEVICE_LIMIT_REACHED').isDeviceLimit,
        isTrue,
      );
      expect(
        ApiException('x', code: 'PRIORITY_REQUIRED').isPriorityRequired,
        isTrue,
      );
    });
  });

  group('PlaybackActiveDto', () {
    test('parses active holder', () {
      final dto = PlaybackActiveDto.fromJson({
        'active': true,
        'deviceId': 'd1',
        'deviceName': 'Living Room',
        'title': 'Match',
      });
      expect(dto.active, isTrue);
      expect(dto.deviceName, 'Living Room');
    });
  });

  group('mapPlaybackConflict', () {
    test('maps 409 to PlaybackConflictException with holder', () async {
      try {
        await mapPlaybackConflict(() async {
          throw ApiException(
            'Another device',
            statusCode: 409,
            code: 'PLAYBACK_LEASE_HELD',
            data: {
              'holder': {'deviceId': 'dx', 'playbackId': 'px'},
            },
          );
        });
        fail('expected conflict');
      } on PlaybackConflictException catch (e) {
        expect(e.code, 'PLAYBACK_LEASE_HELD');
        expect(e.holderDeviceId, 'dx');
        expect(e.holderPlaybackId, 'px');
        expect(e.isLeaseHeld, isTrue);
      }
    });

    test('does not map DEVICE_LIMIT_REACHED as lease conflict', () async {
      try {
        await mapPlaybackConflict(() async {
          throw ApiException(
            'Too many devices',
            statusCode: 409,
            code: 'DEVICE_LIMIT_REACHED',
          );
        });
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.isDeviceLimit, isTrue);
      }
    });
  });
}
