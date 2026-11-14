import 'package:data/data.dart';
import 'package:test/test.dart';

void main() {
  test('no backend is built in', () {
    expect(ApiConfig.defaultBaseUrl, isEmpty);
    expect(ApiConfig.builtInBackupBaseUrls, isEmpty);
    expect(const ApiConfig(baseUrl: '').isConfigured, isFalse);
    expect(const ApiConfig(baseUrl: 'https://a.example/v1').isConfigured, isTrue);
  });
}
