import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider cast strings split into names', () {
    expect(parseCastNames('محمد إمام  شيكو  خالد الصاوي'), ['محمد إمام', 'شيكو', 'خالد الصاوي']);
    expect(parseCastNames('Tom Hardy, Emily Blunt ,Cillian Murphy'), ['Tom Hardy', 'Emily Blunt', 'Cillian Murphy']);
    expect(parseCastNames('أحمد، منى، أحمد'), ['أحمد', 'منى']);
    expect(parseCastNames(null), isEmpty);
    expect(parseCastNames('   '), isEmpty);
  });
}
