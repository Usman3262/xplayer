import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usman 12 Nov: /sports/* (except /sports/status) answers 403
/// SPORTS_NOT_IN_PACKAGE when the package has no Sports.
void main() {
  test('403 SPORTS_NOT_IN_PACKAGE is recognised; other errors are not', () {
    expect(
      SportsApi.isNotInPackage(ApiException('Matches are not included in your package',
          statusCode: 403, code: 'SPORTS_NOT_IN_PACKAGE')),
      isTrue,
    );
    // Code missing, same status and message (older client parsing).
    expect(
      SportsApi.isNotInPackage(
          ApiException('Matches are not included in your package', statusCode: 403)),
      isTrue,
    );
    expect(SportsApi.isNotInPackage(ApiException('Network error.', code: 'NETWORK')), isFalse);
    expect(SportsApi.isNotInPackage(ApiException('Forbidden', statusCode: 403)), isFalse);
    expect(SportsApi.isNotInPackage(null), isFalse);
  });
}
