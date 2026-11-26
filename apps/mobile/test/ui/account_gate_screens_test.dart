import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/account_gate/account_gate.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/personal_details.dart';
import 'package:frisbee_app/ui/auth/view_models/adults_only_viewmodel.dart';
import 'package:frisbee_app/ui/auth/view_models/verify_email_viewmodel.dart';
import 'package:frisbee_app/ui/auth/widgets/adults_only_screen.dart';
import 'package:frisbee_app/ui/auth/widgets/verify_email_screen.dart';

import '../testing/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late AccountGate gate;
  late FakePersonalDetailsRepository personal;

  setUp(() {
    auth = FakeAuthRepository(
      user: const AppUser(uid: 'u1', email: 'pat@x.test'),
    )..verified = false;
    gate = AccountGate(auth: auth)..report(['email_unverified', 'terms']);
    personal = FakePersonalDetailsRepository();
  });

  group('verify email', () {
    Future<VerifyEmailViewModel> pump(WidgetTester tester) async {
      final vm = VerifyEmailViewModel(
        authRepository: auth,
        accountGate: gate,
        personalRepository: personal,
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(home: VerifyEmailScreen(viewModel: vm)),
      );
      await tester.pumpAndSettle();
      return vm;
    }

    testWidgets('says where the link went, with the three buttons', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.textContaining('pat@x.test'), findsOneWidget);
      expect(find.text("I've verified"), findsOneWidget);
      expect(find.text('Resend email'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('resend sends Firebase\'s email again', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('verify-email-resend')));
      await tester.pumpAndSettle();
      expect(auth.verificationsSent, 1);
      expect(
        find.text('Email sent. Check your inbox and spam folder.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed resend says so', (tester) async {
      await pump(tester);
      auth.nextError = Exception('boom');
      await tester.tap(find.byKey(const Key('verify-email-resend')));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't send the email. Wait a moment and try again."),
        findsOneWidget,
      );
    });

    testWidgets('not verified yet: stays, tells them', (tester) async {
      auth.verifiedAfterCheck = false;
      await pump(tester);
      await tester.tap(find.byKey(const Key('verify-email-check')));
      await tester.pumpAndSettle();
      expect(auth.verifiedChecks, 1);
      expect(gate.has('email_unverified'), isTrue);
      expect(
        find.text(
          "We can't see that yet. Open the link in the email we sent, then "
          'try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('verified: reloads, clears the field, asks status again', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('verify-email-check')));
      await tester.pumpAndSettle();
      expect(auth.verifiedChecks, 1);
      expect(gate.has('email_unverified'), isFalse);
      // The next missing step is still there for the router.
      expect(gate.first, 'terms');
      expect(personal.refreshCalls, 1);
    });

    testWidgets('a failed check says so and keeps the gate', (tester) async {
      await pump(tester);
      auth.nextError = Exception('offline');
      await tester.tap(find.byKey(const Key('verify-email-check')));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't check. Check your connection and try again."),
        findsOneWidget,
      );
      expect(gate.has('email_unverified'), isTrue);
    });
  });

  group('the adults-only dead end', () {
    Future<AdultsOnlyViewModel> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vm = AdultsOnlyViewModel(authRepository: auth);
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(home: AdultsOnlyScreen(viewModel: vm)),
      );
      await tester.pumpAndSettle();
      return vm;
    }

    testWidgets('names the rule, offers only sign out and delete', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Stall 10 is for players 18 and older'), findsOneWidget);
      expect(find.text(adultOnlyMessage), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('sign out signs out', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('adults-only-sign-out')));
      await tester.pumpAndSettle();
      expect(auth.currentUser, isNull);
    });

    testWidgets('delete asks first, then deletes the account', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('adults-only-delete')));
      await tester.pumpAndSettle();
      expect(
        find.text("Delete your account and its data? This can't be undone."),
        findsOneWidget,
      );
      // Cancel leaves it alone.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.deleted, isFalse);

      await tester.tap(find.byKey(const Key('adults-only-delete')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('adults-only-password')),
        'secret',
      );
      await tester.tap(find.text('Yes, delete my account'));
      await tester.pumpAndSettle();
      expect(auth.deleted, isTrue);
    });

    testWidgets('a failed delete says where to write', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('adults-only-delete')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('adults-only-password')),
        'wrong',
      );
      await tester.tap(find.text('Yes, delete my account'));
      await tester.pumpAndSettle();
      expect(auth.deleted, isFalse);
      expect(
        find.text(
          "Couldn't delete the account. Sign in again and retry, or email "
          'support@stall10.app.',
        ),
        findsOneWidget,
      );
    });
  });
}
