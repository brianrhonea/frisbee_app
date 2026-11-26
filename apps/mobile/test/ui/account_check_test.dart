// "Couldn't check your account": Try again, Sign out, and leaving once a
// retry gets a proper answer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/auth/view_models/account_check_viewmodel.dart';
import 'package:frisbee_app/ui/auth/widgets/account_check_screen.dart';
import 'package:frisbee_app/ui/auth/widgets/auth_layout.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';

import '../testing/fakes.dart';

void main() {
  setUp(AuthLayout.debugReset);

  late FakeAgreementRepository agreement;
  late FakePersonalDetailsRepository personal;
  late FakeAuthRepository auth;

  AccountCheckViewModel makeVm() => AccountCheckViewModel(
    agreementRepository: agreement,
    personalRepository: personal,
    authRepository: auth,
  );

  setUp(() {
    agreement = FakeAgreementRepository(agreed: null)..checkFailed = true;
    personal = FakePersonalDetailsRepository();
    auth = FakeAuthRepository(user: testUser);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AccountCheckScreen(viewModel: makeVm()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('says it could not check, and offers retry, sign-out and the '
      'legal pages', (tester) async {
    await pump(tester);
    expect(find.text("Couldn't check your account"), findsOneWidget);
    expect(find.byKey(const Key('account-check-retry')), findsOneWidget);
    expect(find.byKey(const Key('account-check-sign-out')), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('Try again asks only the failed check; success clears it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('account-check-retry')));
    await tester.pumpAndSettle();
    expect(agreement.refreshCalls, 1);
    expect(personal.refreshCalls, 0, reason: 'that check had not failed');
    expect(agreement.checkFailed, isFalse);
    expect(find.byKey(const Key('account-check-still-failing')), findsNothing);
  });

  testWidgets('a retry that fails again says so and stays blocked', (
    tester,
  ) async {
    agreement.refreshFails = true;
    personal.checkFailed = true;
    personal.refreshFails = true;
    await pump(tester);
    await tester.tap(find.byKey(const Key('account-check-retry')));
    await tester.pumpAndSettle();
    expect(agreement.refreshCalls, 1);
    expect(personal.refreshCalls, 1);
    expect(agreement.checkFailed, isTrue);
    expect(personal.checkFailed, isTrue);
    expect(
      find.byKey(const Key('account-check-still-failing')),
      findsOneWidget,
    );
  });

  testWidgets('Sign out signs out', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('account-check-sign-out')));
    await tester.pumpAndSettle();
    expect(auth.currentUser, isNull);
  });
}
