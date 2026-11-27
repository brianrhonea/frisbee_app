import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart';

import '../../ui_harness/harness.dart';

void main() {
  testWidgets('bottomInset leaves room under the last row for a button', (
    tester,
  ) async {
    const last = Key('last');
    await pumpInApp(
      tester,
      PageScroll(
        bottomInset: 72,
        children: [
          for (var i = 0; i < 30; i++) const SizedBox(height: 60),
          const SizedBox(key: last, height: 60),
        ],
      ),
      width: 390,
      height: 800,
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();
    final bottom = tester.getRect(find.byKey(last)).bottom;
    expect(bottom, lessThanOrEqualTo(800 - 72));
  });
}
