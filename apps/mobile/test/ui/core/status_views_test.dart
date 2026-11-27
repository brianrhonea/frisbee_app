// C9: EmptyState, ErrorState and LoadingState.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/ui/app_button.dart';
import 'package:frisbee_app/ui/core/ui/skeleton.dart';
import 'package:frisbee_app/ui/core/ui/status_views.dart';

import '../../ui_harness/harness.dart';

/// Placeholders pulse for ever unless animations are off.
Widget _still(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child,
  ),
);

Widget _empty({Widget? action}) => EmptyState(
  icon: Icons.event_busy_outlined,
  title: 'Nothing scheduled',
  message: 'Add an event to see it here.',
  action: action,
);

Widget _error({VoidCallback? onRetry}) =>
    ErrorState(error: Exception('Offline'), onRetry: onRetry);

void main() {
  for (final (name, build) in <(String, Widget Function())>[
    (
      'empty',
      () => _empty(action: AppButton.primary('New event', onPressed: () {})),
    ),
    ('error', () => _error(onRetry: () {})),
    ('loading', () => _still(const LoadingState())),
  ]) {
    testWidgets(
      '$name: gallery goldens, light and dark',
      skip: goldenSkip != null,
      (t) async {
        await expectGoldens(t, build(), 'status_views_$name', height: 480);
      },
    );

    for (final theme in GoldenTheme.values) {
      testWidgets('$name meets accessibility guidelines, ${theme.name}', (
        t,
      ) async {
        await pumpInApp(t, build(), theme: theme, height: 480);
        await expectAccessible(t);
      });
    }

    testWidgets('$name fits at text scale 2.0', (t) async {
      await expectNoOverflowWithLargeText(t, build(), height: 900);
    });
  }

  testWidgets('empty: title, message and the next action', (t) async {
    var taps = 0;
    await pumpInApp(
      t,
      _empty(action: AppButton.primary('New event', onPressed: () => taps++)),
    );
    expect(find.text('Nothing scheduled'), findsOneWidget);
    expect(find.text('Add an event to see it here.'), findsOneWidget);
    await t.tap(find.text('New event'));
    expect(taps, 1);
  });

  testWidgets('empty without a message or action is just icon and title', (
    t,
  ) async {
    await pumpInApp(t, const EmptyState(icon: Icons.inbox, title: 'Empty'));
    expect(find.text('Empty'), findsOneWidget);
    expect(find.byType(AppButton), findsNothing);
  });

  testWidgets('error: says what went wrong and retries', (t) async {
    var retries = 0;
    await pumpInApp(t, _error(onRetry: () => retries++));
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await t.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('error can have a title and a retry label', (t) async {
    await pumpInApp(
      t,
      ErrorState(
        error: 'x',
        title: 'Could not load teams',
        retryLabel: 'Try again',
        onRetry: () {},
      ),
    );
    expect(find.text('Could not load teams'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('error without onRetry has no button', (t) async {
    await pumpInApp(t, _error());
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('error is announced as a live region', (t) async {
    final handle = t.ensureSemantics();
    await pumpInApp(t, _error(onRetry: () {}));
    final node = t.getSemantics(find.byIcon(Icons.error_outline));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  testWidgets('loading shows placeholder rows, read as "Loading"', (t) async {
    final handle = t.ensureSemantics();
    await pumpInApp(t, _still(const LoadingState()));
    expect(find.byType(Skeleton), findsWidgets);
    expect(find.bySemanticsLabel('Loading'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    handle.dispose();
  });
}
