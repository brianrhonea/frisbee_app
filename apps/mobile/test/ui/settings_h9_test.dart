// H9: Settings with a profile row, grouped rows with chevrons and the
// appearance choice, on the shared type scale. Parity: website settings.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/profile/view_models/profile_viewmodel.dart';
import 'package:frisbee_app/ui/settings/widgets/settings_screen.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';
import '../ui_harness/harness.dart';

void main() {
  late FakeAuthRepository auth;

  Widget screen() {
    auth = FakeAuthRepository(user: testUser);
    final vm = ProfileViewModel(
      authRepository: auth,
      themeRepository: FakeThemeRepository(),
      notificationRepository: FakeNotificationRepository(),
      directMessageRepository: FakeDirectMessageRepository(),
    );
    addTearDown(vm.dispose);
    return SettingsScreen(viewModel: vm);
  }

  testWidgets('profile row, grouped rows with chevrons, and the groups', (
    tester,
  ) async {
    await pumpInApp(tester, screen(), width: 390, height: 1100);
    await tester.pumpAndSettle();
    expect(find.text(testUser.label), findsOneWidget);
    for (final row in [
      'General',
      'Notifications',
      'Privacy',
      'Account',
      'Help',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.text('APP'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsWidgets);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('meets accessibility guidelines, ${theme.name}', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        screen(),
        theme: theme,
        width: 390,
        height: 1100,
      );
      await tester.pumpAndSettle();
      await expectAccessible(tester);
    });
  }

  testWidgets('fits at text scale 2.0', (tester) async {
    await expectNoOverflowWithLargeText(
      tester,
      screen(),
      width: 390,
      height: 1100,
    );
  });

  testWidgets(
    'goldens at phone and tablet widths, light and dark',
    skip: goldenSkip != null,
    (tester) async {
      await expectGoldens(
        tester,
        screen(),
        'settings_h9',
        widths: const [GoldenWidth.phone, GoldenWidth.tablet],
        height: 1100,
      );
    },
  );
}
