import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/guides.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/learn/widgets/guide_screens.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  }

  testWidgets('the rules page links the official rules and lists every '
      'section', (tester) async {
    await pump(tester, const RulesScreen());
    expect(find.text('USA Ultimate rules'), findsOneWidget);
    for (final s in rulesGuide) {
      await tester.scrollUntilVisible(
        find.byKey(Key('rules-${s.id}')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(s.title), findsWidgets);
    }
  });

  testWidgets('help topics open in place, and support is a tap away', (
    tester,
  ) async {
    await pump(tester, const HelpScreen());
    final first = helpTopics.first;
    expect(find.text(first.points.first), findsNothing);
    await tester.tap(find.text(first.title));
    await tester.pumpAndSettle();
    expect(find.text(first.points.first), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('help-contact')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(supportEmail), findsOneWidget);
  });
}
