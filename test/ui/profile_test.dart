import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/profile/view_models/profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';

import '../testing/fakes.dart';

void main() {
  testWidgets('appearance toggle switches between light and dark', (
    tester,
  ) async {
    final theme = FakeThemeRepository();
    final vm = ProfileViewModel(
      authRepository: FakeAuthRepository(user: testUser),
      themeRepository: theme,
    );
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: theme,
        builder: (_, _) => MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: theme.themeMode,
          home: ProfileScreen(viewModel: vm),
        ),
      ),
    );
    final context = tester.element(find.byType(ProfileScreen));
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(theme.themeMode, ThemeMode.dark);
    expect(Theme.of(context).brightness, Brightness.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(theme.themeMode, ThemeMode.light);
    expect(Theme.of(context).brightness, Brightness.light);
  });
}
