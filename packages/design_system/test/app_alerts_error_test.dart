import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clean strips the Exception: prefix', () {
    expect(
      AppAlerts.clean(Exception('Request failed (502)')),
      'Request failed (502)',
    );
  });

  test('clean keeps plain messages unchanged', () {
    expect(AppAlerts.clean('Request failed (502)'), 'Request failed (502)');
  });

  test('clean uses toString of other error types', () {
    expect(AppAlerts.clean(StateError('bad')), 'Bad state: bad');
  });
}
