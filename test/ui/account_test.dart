import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/ui/auth/view_models/sign_in_viewmodel.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_in_screen.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/profile/view_models/profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';

import '../testing/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late ProfileViewModel vm;

  setUp(() {
    auth = FakeAuthRepository(user: testUser);
    vm = ProfileViewModel(
      authRepository: auth,
      themeRepository: FakeThemeRepository(),
      notificationRepository: FakeNotificationRepository(),
    );
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(child: SettingsCard(viewModel: vm)),
        ),
      ),
    );
  }

  Finder deleteButton() => find.widgetWithText(FilledButton, 'Delete account');

  bool enabled(WidgetTester tester, Finder f) =>
      tester.widget<FilledButton>(f).onPressed != null;

  testWidgets('sign out asks first', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Are you sure you want to sign out?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(auth.currentUser, isNotNull);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(auth.currentUser, isNull);
  });

  testWidgets('deleting needs DELETE typed and the password', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('permanently deletes'), findsOneWidget);
    expect(enabled(tester, deleteButton()), isFalse);

    await tester.enterText(find.byType(TextField).at(0), 'delete it');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.pump();
    expect(enabled(tester, deleteButton()), isFalse);

    await tester.enterText(find.byType(TextField).at(0), 'DELETE');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.pump();
    expect(enabled(tester, deleteButton()), isTrue);
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(auth.deleted, isFalse);
    expect(auth.currentUser, isNotNull);

    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.pump();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    expect(auth.deleted, isTrue);
    expect(auth.currentUser, isNull);
    expect(auth.signedOutNotice, 'Account deleted successfully');
  });

  testWidgets('Google accounts sign in again instead of a password', (
    tester,
  ) async {
    auth.method = SignInMethod.google;
    await pumpSettings(tester);
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('sign in with Google again'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    expect(auth.reauthenticated, isTrue);
    expect(auth.deleted, isTrue);
  });

  testWidgets('cancelling leaves the account alone', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(auth.deleted, isFalse);
  });

  testWidgets('sign-in says the account was deleted, once', (tester) async {
    await auth.deleteAccount(); // Not confirmed yet: refused.
    expect(auth.deleted, isFalse);
    await auth.reauthenticate(password: 'secret');
    await auth.deleteAccount();

    Future<void> open() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SignInScreen(
            viewModel: SignInViewModel(authRepository: auth),
          ),
        ),
      );
      await tester.pump();
    }

    await open();
    expect(find.text('Account deleted successfully'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await open();
    expect(find.text('Account deleted successfully'), findsNothing);
  });
}
