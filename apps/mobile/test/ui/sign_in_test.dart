import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/auth/view_models/sign_in_viewmodel.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_in_screen.dart';

import '../testing/fakes.dart';

void main() {
  late FakeAuthRepository auth;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = SignInViewModel(authRepository: auth);
    addTearDown(vm.dispose);
    await tester.pumpWidget(MaterialApp(home: SignInScreen(viewModel: vm)));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> signIn(WidgetTester tester, String id) async {
    await tester.enterText(field('Email or username'), id);
    await tester.enterText(field('Password'), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    auth = FakeAuthRepository()..emailsByUsername['pat.lee'] = 'pat@x.org';
  });

  testWidgets('signs in with an email', (tester) async {
    await pump(tester);
    await signIn(tester, 'pat@x.org');
    expect(auth.currentUser?.email, 'pat@x.org');
  });

  testWidgets('signs in with a username, @ or not', (tester) async {
    await pump(tester);
    await signIn(tester, '@Pat.Lee');
    expect(auth.currentUser?.email, 'pat@x.org');
  });

  testWidgets('an unknown username reads like a wrong password', (
    tester,
  ) async {
    await pump(tester);
    await signIn(tester, 'nobody');
    expect(auth.currentUser, isNull);
    expect(find.text('Incorrect username or password.'), findsOne);
  });

  testWidgets('resetting the password needs the email', (tester) async {
    await pump(tester);
    await tester.enterText(field('Email or username'), 'pat.lee');
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    expect(find.text('Enter your email to reset your password.'), findsOne);
  });
}
