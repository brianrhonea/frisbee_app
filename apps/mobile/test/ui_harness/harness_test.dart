// Checks the UI rework test helpers on today's shared state views, so the
// harness is known to work before components are rebuilt (board tasks P4, P5).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/ui/status_views.dart';

import 'harness.dart';

void main() {
  Widget empty() => const EmptyState(
    icon: Icons.event_outlined,
    title: 'Nothing scheduled',
    message: 'Practices and games you RSVP to show up here.',
  );

  Widget error({VoidCallback? onRetry}) =>
      ErrorState(error: 'Could not load the schedule.', onRetry: onRetry);

  group('goldens', () {
    testWidgets(
      'empty view, light and dark, all widths',
      skip: goldenSkip != null,
      (tester) async {
        await expectGoldens(
          tester,
          empty(),
          'empty_view',
          widths: GoldenWidth.values,
        );
      },
    );

    testWidgets('error view with retry', skip: goldenSkip != null, (
      tester,
    ) async {
      await expectGoldens(tester, error(onRetry: () {}), 'error_view');
    });
  });

  group('accessibility', () {
    testWidgets('error view meets tap-target, label and contrast guidelines', (
      tester,
    ) async {
      await pumpInApp(tester, error(onRetry: () {}));
      await expectAccessible(tester);
    });

    testWidgets('the tap-target check catches a 32 px button', (tester) async {
      await pumpInApp(
        tester,
        Center(
          child: SizedBox.square(
            dimension: 32,
            child: Material(
              child: InkWell(
                onTap: () {},
                child: const Icon(Icons.undo, semanticLabel: 'Undo last'),
              ),
            ),
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      final result = await androidTapTargetGuideline.evaluate(tester);
      handle.dispose();
      expect(result.passed, isFalse);
    });

    testWidgets('empty view meets the guidelines in dark', (tester) async {
      await pumpInApp(tester, empty(), theme: GoldenTheme.dark);
      await expectAccessible(tester);
    });
  });

  group('large text', () {
    testWidgets('empty view fits at 200% on a phone', (tester) async {
      await expectNoOverflowWithLargeText(tester, empty());
    });

    testWidgets('error view fits at 200% on a phone', (tester) async {
      await expectNoOverflowWithLargeText(tester, error(onRetry: () {}));
    });
  });
}
