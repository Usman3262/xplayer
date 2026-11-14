import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TV Continue Watching: long Arabic title centred, two lines, fits the rail', (tester) async {
    const w = 300.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: ContinueCard.heightFor(w, centeredTitle: true),
              child: const ContinueCard(
                width: w,
                centeredTitle: true,
                title: 'مسلسل الحشاشين الحلقة الثالثة عشر والأخيرة من الموسم الأول كاملة',
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.textContaining('الحشاشين'));
    expect(text.textAlign, TextAlign.center);
    expect(text.maxLines, 2);
    final box = tester.getRect(find.textContaining('الحشاشين'));
    expect(box.width, w);
    expect(box.bottom, lessThanOrEqualTo(ContinueCard.heightFor(w, centeredTitle: true)));
  });
}
