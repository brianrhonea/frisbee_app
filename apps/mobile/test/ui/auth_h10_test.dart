// H10: sign in and sign up with the shared buttons and type scale. Every
// sign-in option stays. Parity: website sign-in and sign-up pages.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/auth/view_models/sign_in_viewmodel.dart';
import 'package:frisbee_app/ui/auth/view_models/sign_up_viewmodel.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_in_screen.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_up_screen.dart';
import 'package:frisbee_app/ui/core/ui/app_button.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';

void main() {
  Widget signIn() => SignInScreen(
    viewModel: SignInViewModel(authRepository: FakeAuthRepository()),
  );

  Widget signUp() => SignUpScreen(
    viewModel: SignUpViewModel(
      authRepository: FakeAuthRepository(),
      personalRepository: FakePersonalDetailsRepository(),
    ),
  );

  testWidgets('sign in: fields, primary button and the sign-up link', (
    tester,
  ) async {
    await pumpInApp(tester, signIn(), width: 390, height: 844);
    await tester.pumpAndSettle();
    expect(find.text('Email or username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Sign in'), findsOneWidget);
    expect(find.textContaining('Sign up', findRichText: true), findsOneWidget);
  });

  testWidgets('sign in: empty fields show the errors in words', (tester) async {
    await pumpInApp(tester, signIn(), width: 390, height: 844);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email or username'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('sign up: create account is the primary button', (tester) async {
    await pumpInApp(tester, signUp(), width: 390, height: 1000);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppButton, 'Create account'), findsOneWidget);
  });

  for (final (name, build, height) in [
    ('sign in', signIn, 844.0),
    ('sign up', signUp, 1000.0),
  ]) {
    for (final theme in GoldenTheme.values) {
      testWidgets('$name meets accessibility guidelines, ${theme.name}', (
        tester,
      ) async {
        await pumpInApp(
          tester,
          build(),
          theme: theme,
          width: 390,
          height: height,
        );
        await tester.pumpAndSettle();
        await expectAccessible(tester);
      });
    }

    testWidgets('$name fits at text scale 2.0', (tester) async {
      await expectNoOverflowWithLargeText(
        tester,
        build(),
        width: 390,
        height: height,
      );
    });
  }

  testWidgets(
    'goldens at phone and tablet widths, light and dark',
    skip: goldenSkip != null,
    (tester) async {
      await expectGoldens(
        tester,
        signIn(),
        'sign_in_h10',
        widths: const [GoldenWidth.phone, GoldenWidth.tablet],
        height: 844,
      );
      await expectGoldens(
        tester,
        signUp(),
        'sign_up_h10',
        widths: const [GoldenWidth.phone, GoldenWidth.tablet],
        height: 1000,
      );
    },
  );
}
