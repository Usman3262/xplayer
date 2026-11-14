import 'package:data/data.dart';
import 'package:test/test.dart';

void main() {
  test('api config default host is production', () {
    // Production API behind Cloudflare. The old Railway backup address was
    // removed (5 Nov); backups come only from the signed config.
    expect(ApiConfig.defaultBaseUrl, 'https://api.sksj.online/v1');
    expect(
      ApiConfig.builtInBackupBaseUrls.where((b) => b.contains('railway.app')),
      isEmpty,
    );
  });
}
