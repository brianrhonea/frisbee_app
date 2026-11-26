import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/account_gate/account_gate.dart';
import 'package:frisbee_app/domain/models/personal_details.dart';
import 'package:frisbee_app/routing/router.dart';
import 'package:frisbee_app/routing/routes.dart';

import '../testing/fakes.dart';

/// Routing by the account gate's first missing field (the 403
/// `account_incomplete` fields), and the order of the sign-up steps with
/// the birth date before any username.
void main() {
  late FakeAuthRepository auth;
  late AccountGate gate;

  setUp(() {
    auth = FakeAuthRepository(user: testUser);
    gate = AccountGate(auth: auth);
  });

  String? go(
    String location, {
    FakePersonalDetailsRepository? personal,
    FakeAgreementRepository? agreement,
  }) => authRedirect(
    auth,
    Uri.parse(location),
    personal: personal,
    agreement: agreement,
    gate: gate,
  );

  test('nothing missing: nobody is held', () {
    expect(go(Routes.home), isNull);
  });

  group('by the first field', () {
    test('email_unverified goes to the verify-email screen', () {
      gate.report(['email_unverified', 'age', 'terms']);
      expect(go('/teams/t1'), '${Routes.verifyEmail}?from=%2Fteams%2Ft1');
      expect(go(Routes.verifyEmail), isNull);
    });

    test('age goes to the birth date step', () {
      gate.report(['age', 'terms']);
      expect(go('/teams/t1'), '${Routes.finishSignUp}?from=%2Fteams%2Ft1');
      expect(go(Routes.finishSignUp), isNull);
    });

    test('terms goes to the agree-terms step', () {
      gate.report(['terms']);
      expect(go('/teams/t1'), '${Routes.agreeTerms}?from=%2Fteams%2Ft1');
      expect(go(Routes.agreeTerms), isNull);
    });

    test('clearing a field moves to the next, then leaves', () {
      gate.report(['email_unverified', 'age', 'terms']);
      gate.clear('email_unverified');
      expect(go(Routes.verifyEmail), Routes.home);
      expect(go(Routes.home), startsWith(Routes.finishSignUp));
      gate.clear('age');
      expect(go(Routes.finishSignUp), startsWith(Routes.agreeTerms));
      expect(go(Routes.home), startsWith(Routes.agreeTerms));
      gate.clear('terms');
      expect(go(Routes.agreeTerms), Routes.home);
      expect(go(Routes.home), isNull);
    });

    test('the agree-terms step stays even if the agreement looks done', () {
      gate.report(['terms']);
      expect(
        go(Routes.agreeTerms, agreement: FakeAgreementRepository()),
        isNull,
      );
    });
  });

  group('under 18', () {
    test('is a dead end from anywhere, and the only place to be', () {
      gate.markUnderAge();
      expect(go(Routes.home), Routes.adultsOnly);
      expect(go('/teams/t1'), Routes.adultsOnly);
      expect(go(Routes.finishSignUp), Routes.adultsOnly);
      expect(go(Routes.adultsOnly), isNull);
    });

    test('signing out resets it (a signed-out user goes to sign-in)', () {
      gate.markUnderAge();
      auth.setUser(null);
      expect(gate.underAge, isFalse);
    });
  });

  group('the birth date comes before the username', () {
    const status = PersonalDetailsStatus(complete: false, required: true);

    test('a new account without ageOk is asked for it first', () {
      auth
        ..usernameMissing = true
        ..ageOkClaim = false;
      final personal = FakePersonalDetailsRepository(status: status);
      expect(go(Routes.home, personal: personal), Routes.finishSignUp);
      expect(go(Routes.finishSignUp, personal: personal), isNull);
      // Never the username screen before the birth date.
      expect(
        go(Routes.chooseUsername, personal: personal),
        startsWith(Routes.finishSignUp),
      );
    });

    test('with ageOk the username comes next', () {
      auth
        ..usernameMissing = true
        ..ageOkClaim = true;
      final personal = FakePersonalDetailsRepository(status: status);
      expect(go(Routes.home, personal: personal), Routes.chooseUsername);
    });

    test('while the status is unknown nobody is held', () {
      auth
        ..usernameMissing = true
        ..ageOkClaim = false;
      expect(
        go(Routes.home, personal: FakePersonalDetailsRepository()),
        Routes.chooseUsername,
      );
    });
  });
}
