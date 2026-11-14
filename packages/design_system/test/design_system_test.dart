import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app cyan token is set', () {
    expect(AppColors.cyan.toARGB32(), isNonZero);
  });
}
