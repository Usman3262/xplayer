import 'package:data/src/remote/api_config.dart';
import 'package:data/src/remote/api_endpoints.dart';
import 'package:data/src/security/signed_app_config.dart';
import 'package:flutter_test/flutter_test.dart';

AppConfig _cfg(List<String> urls) => AppConfig(
      seq: 1,
      minSeq: 0,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      apiBaseUrls: urls,
      downloads: true,
      devicePop: false,
    );

void main() {
  final e = ApiEndpoints.instance;
  setUp(e.resetForTest);

  test('single base: no failover', () {
    e.ensurePrimary('https://a.example/v1');
    expect(e.reportNetworkFailure('https://a.example/v1'), isNull);
    expect(e.current('x'), 'https://a.example/v1');
  });

  test('built-in and signed-config backups follow the primary, no duplicates', () {
    e.ensurePrimary('https://api.example/v1');
    e.addBackups(ApiConfig.builtInBackupBaseUrls);
    e.addBackups(ApiConfig.builtInBackupBaseUrls);
    e.adopt(_cfg([
      'https://api.example',
      'https://backup.example',
    ]));
    expect(e.bases, [
      'https://api.example/v1',
      'https://backup.example/v1',
    ]);
    expect(
      e.reportNetworkFailure('https://api.example/v1'),
      'https://backup.example/v1',
    );
  });

  test('built-in backups (if any) are https /v1', () {
    for (final b in ApiConfig.builtInBackupBaseUrls) {
      expect(b.startsWith('https://'), isTrue);
      expect(b.endsWith('/v1'), isTrue);
    }
  });

  test('verified backups are added after the primary and used on failure', () {
    e.ensurePrimary('https://a.example/v1');
    e.adopt(_cfg(['https://a.example', 'https://b.example']));
    expect(e.bases, ['https://a.example/v1', 'https://b.example/v1']);
    expect(e.reportNetworkFailure('https://a.example/v1'), 'https://b.example/v1');
    expect(e.current('x'), 'https://b.example/v1');
    // A second report for the old base does not skip past b.
    expect(e.reportNetworkFailure('https://a.example/v1'), 'https://b.example/v1');
    // b fails too: wrap back to the primary.
    expect(e.reportNetworkFailure('https://b.example/v1'), 'https://a.example/v1');
  });
}
