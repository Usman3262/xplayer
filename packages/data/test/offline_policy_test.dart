import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offline downloads rule (client 5 Nov, P17).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;

  Map<String, dynamic> me({String id = 'acc-1', String status = 'ACTIVE', DateTime? ends, int days = 7}) => {
        'id': id,
        'role': 'CUSTOMER',
        'subscription': {'status': status, 'expiresAt': ends?.toUtc().toIso8601String(), 'offlineDays': days},
      };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 11, 6, 12);
    OfflineDownloadPolicy.nowOverride = () => now;
  });
  tearDown(() => OfflineDownloadPolicy.nowOverride = null);

  test('no online check yet (first run after the update): allowed', () async {
    expect(await OfflineDownloadPolicy.check(), isNull);
  });

  test('active subscription, checked now: allowed', () async {
    await OfflineDownloadPolicy.recordOnline(me(ends: now.add(const Duration(days: 30))));
    expect(await OfflineDownloadPolicy.check(), isNull);
  });

  test('subscription end date passed: refused', () async {
    await OfflineDownloadPolicy.recordOnline(me(ends: now.add(const Duration(days: 2))));
    now = now.add(const Duration(days: 3));
    expect(await OfflineDownloadPolicy.check(), OfflineRefusal.subscriptionEnded);
  });

  test('status not active: refused', () async {
    await OfflineDownloadPolicy.recordOnline(me(status: 'EXPIRED', ends: now.add(const Duration(days: 30))));
    expect(await OfflineDownloadPolicy.check(), OfflineRefusal.subscriptionEnded);
  });

  test('no check-in for more than offlineDays: refused; within: allowed', () async {
    await OfflineDownloadPolicy.recordOnline(me(ends: now.add(const Duration(days: 60))));
    now = now.add(const Duration(days: 6, hours: 23));
    expect(await OfflineDownloadPolicy.check(), isNull);
    now = now.add(const Duration(days: 1, hours: 2));
    expect(await OfflineDownloadPolicy.check(), OfflineRefusal.checkInNeeded);
  });

  test('server offlineDays is used', () async {
    await OfflineDownloadPolicy.recordOnline(me(ends: now.add(const Duration(days: 60)), days: 14));
    now = now.add(const Duration(days: 10));
    expect(await OfflineDownloadPolicy.check(), isNull);
  });

  test('device clock moved back before the last check: refused', () async {
    await OfflineDownloadPolicy.recordOnline(me(ends: now.add(const Duration(days: 30))));
    now = now.subtract(const Duration(days: 1));
    expect(await OfflineDownloadPolicy.check(), OfflineRefusal.clockChanged);
  });

  test('another account signs in: accountChanged event; same account: none', () async {
    final events = <String>[];
    final sub = OfflineDownloadPolicy.events.listen(events.add);
    await OfflineDownloadPolicy.recordOnline(me(id: 'acc-1'));
    await OfflineDownloadPolicy.recordOnline(me(id: 'acc-1'));
    expect(events, isEmpty);
    await OfflineDownloadPolicy.recordOnline(me(id: 'acc-2'));
    await Future<void>.delayed(Duration.zero);
    expect(events, ['accountChanged']);
    await sub.cancel();
  });

  test('sign-out: signedOut event and anything left needs a new online check', () async {
    final events = <String>[];
    final sub = OfflineDownloadPolicy.events.listen(events.add);
    await OfflineDownloadPolicy.recordOnline(me(ends: now.add(const Duration(days: 30))));
    await OfflineDownloadPolicy.signedOut();
    await Future<void>.delayed(Duration.zero);
    expect(events, ['signedOut']);
    expect(await OfflineDownloadPolicy.check(), OfflineRefusal.checkInNeeded);
    await sub.cancel();
  });

  test('older server without a subscription block: only the check-in time applies', () async {
    await OfflineDownloadPolicy.recordOnline({'id': 'acc-1', 'role': 'CUSTOMER'});
    expect(await OfflineDownloadPolicy.check(), isNull);
    now = now.add(const Duration(days: 8));
    expect(await OfflineDownloadPolicy.check(), OfflineRefusal.checkInNeeded);
  });

  test('sign-out / account change leave a wipe flag for a controller that was not running', () async {
    expect(await OfflineDownloadPolicy.wipePending(), isFalse);
    await OfflineDownloadPolicy.recordOnline(me(id: 'acc-1'));
    await OfflineDownloadPolicy.recordOnline(me(id: 'acc-2'));
    expect(await OfflineDownloadPolicy.wipePending(), isTrue);
    await OfflineDownloadPolicy.wipeDone();
    expect(await OfflineDownloadPolicy.wipePending(), isFalse);
    await OfflineDownloadPolicy.signedOut();
    expect(await OfflineDownloadPolicy.wipePending(), isTrue);
  });
}
