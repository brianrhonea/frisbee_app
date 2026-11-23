import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/guides.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/data/repositories/learn/learn_progress_repository.dart';
import 'package:frisbee_app/ui/learn/view_models/learn_viewmodel.dart';
import 'package:frisbee_app/ui/learn/widgets/guide_screens.dart';
import 'package:frisbee_app/ui/learn/widgets/learn_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  }

  testWidgets('Learn to play ends with the rules: the official rules, then '
      'every rule opening in place; /rules opens it there', (tester) async {
    await pump(
      tester,
      LearnScreen(
        viewModel: LearnViewModel(repository: LearnProgressRepositoryMemory()),
        openRules: true,
      ),
    );
    await tester.pumpAndSettle();
    // Opened at the rules.
    expect(find.text('USA Ultimate rules').hitTestable(), findsOneWidget);
    expect(find.text('The rules of ultimate'), findsWidgets);
    final first = rulesGuide.first;
    expect(find.text(first.points.first), findsNothing);
    await tester.tap(find.byKey(Key('rules-${first.id}')));
    await tester.pumpAndSettle();
    expect(find.text(first.points.first), findsOneWidget);
    for (final s in rulesGuide) {
      await tester.scrollUntilVisible(
        find.byKey(Key('rules-${s.id}')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
  });

  testWidgets("the contents' last row jumps to the rules", (tester) async {
    await pump(
      tester,
      LearnScreen(
        viewModel: LearnViewModel(repository: LearnProgressRepositoryMemory()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('USA Ultimate rules').hitTestable(), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('learn-to-rules')));
    await tester.tap(find.byKey(const Key('learn-to-rules')));
    await tester.pumpAndSettle();
    expect(find.text('USA Ultimate rules').hitTestable(), findsOneWidget);
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
