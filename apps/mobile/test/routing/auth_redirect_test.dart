import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/personal_details.dart';
import 'package:frisbee_app/routing/router.dart';
import 'package:frisbee_app/routing/routes.dart';

import '../testing/fakes.dart';

void main() {
  String? redirect(FakeAuthRepository auth, String location) =>
      authRedirect(auth, Uri.parse(location));

  test('waits on splash until auth is ready', () {
    final auth = FakeAuthRepository(ready: false);
    expect(redirect(auth, '/teams/t1'), '/splash?from=%2Fteams%2Ft1');
    expect(redirect(auth, '/splash?from=/teams/t1'), isNull);
  });

  test('signed-out users go to sign-in, keeping their destination', () {
    final auth = FakeAuthRepository();
    expect(redirect(auth, '/teams/t1'), '/sign-in?from=%2Fteams%2Ft1');
    expect(redirect(auth, Routes.home), Routes.signIn);
    expect(
      redirect(auth, '/splash?from=/teams/t1'),
      '/sign-in?from=%2Fteams%2Ft1',
    );
    expect(redirect(auth, Routes.signUp), isNull);
  });

  test('signing in always lands on Community', () {
    final auth = FakeAuthRepository(user: testUser);
    expect(redirect(auth, Routes.signIn), Routes.home);
    expect(redirect(auth, '/sign-in?from=/teams/t1'), Routes.home);
    expect(redirect(auth, '/sign-in?from=/explore'), Routes.home);
    expect(redirect(auth, '/sign-up?from=/teams/t1'), Routes.home);
    expect(redirect(auth, '/explore'), isNull);
  });

  test('except from an invite link, to finish joining', () {
    final auth = FakeAuthRepository(user: testUser);
    expect(redirect(auth, '/sign-in?from=/join/ABC123'), '/join/ABC123');
    expect(redirect(auth, '/sign-up?from=/join/ABC123'), '/join/ABC123');
    expect(redirect(auth, '/sign-in?from=/g/grp1'), '/g/grp1');
  });

  test('opening the app signed in carries on where it was headed', () {
    final auth = FakeAuthRepository(user: testUser);
    expect(redirect(auth, '/splash'), Routes.home);
    expect(redirect(auth, '/splash?from=/teams/t1'), '/teams/t1');
  });

  test('no username yet: pick one first, then carry on', () {
    final auth = FakeAuthRepository(user: testUser)..usernameMissing = true;
    expect(redirect(auth, Routes.home), Routes.chooseUsername);
    expect(
      redirect(auth, '/teams/t1'),
      '${Routes.chooseUsername}?from=%2Fteams%2Ft1',
    );
    // Straight from signing in with an invite link.
    expect(
      redirect(auth, '/sign-in?from=/join/ABC123'),
      '${Routes.chooseUsername}?from=%2Fjoin%2FABC123',
    );
    expect(redirect(auth, Routes.chooseUsername), isNull);

    auth.usernameMissing = false;
    expect(redirect(auth, Routes.chooseUsername), Routes.home);
    expect(
      redirect(auth, '${Routes.chooseUsername}?from=/join/ABC123'),
      '/join/ABC123',
    );
  });

  group('personal details', () {
    String? go(FakePersonalDetailsRepository p, String location) =>
        authRedirect(
          FakeAuthRepository(user: testUser),
          Uri.parse(location),
          personal: p,
        );
    const missing = PersonalDetailsStatus(complete: false, required: true);

    test('a new account gives them first, then carries on', () {
      final p = FakePersonalDetailsRepository(status: missing);
      expect(go(p, '/teams/t1'), '${Routes.finishSignUp}?from=%2Fteams%2Ft1');
      expect(go(p, Routes.home), Routes.finishSignUp);
      expect(go(p, Routes.finishSignUp), isNull);
      expect(
        go(p, '/sign-up?from=/join/ABC123'),
        '${Routes.finishSignUp}?from=%2Fjoin%2FABC123',
      );

      p.status = const PersonalDetailsStatus(complete: true, required: true);
      expect(go(p, Routes.finishSignUp), Routes.home);
      expect(go(p, '${Routes.finishSignUp}?from=/teams/t1'), '/teams/t1');
      expect(go(p, '/teams/t1'), isNull);
    });

    test('older accounts and an unknown status are never held up', () {
      expect(
        go(
          FakePersonalDetailsRepository(
            status: const PersonalDetailsStatus(
              complete: false,
              required: false,
            ),
          ),
          '/teams/t1',
        ),
        isNull,
      );
      expect(go(FakePersonalDetailsRepository(), '/teams/t1'), isNull);
    });

    test('a failed status check blocks, and recovers on a retry', () {
      final p = FakePersonalDetailsRepository()..checkFailed = true;
      expect(go(p, '/teams/t1'), '${Routes.accountCheck}?from=%2Fteams%2Ft1');
      expect(go(p, Routes.accountCheck), isNull);
      p
        ..checkFailed = false
        ..status = const PersonalDetailsStatus(complete: true, required: true);
      expect(go(p, Routes.accountCheck), Routes.home);
      expect(go(p, '/teams/t1'), isNull);
    });

    test('signed-out users are not sent to the check screen', () {
      final p = FakePersonalDetailsRepository()..checkFailed = true;
      expect(
        authRedirect(FakeAuthRepository(), Uri.parse('/teams/t1'), personal: p),
        '/sign-in?from=%2Fteams%2Ft1',
      );
    });

    test('the username comes first', () {
      final auth = FakeAuthRepository(user: testUser)..usernameMissing = true;
      final p = FakePersonalDetailsRepository(status: missing);
      expect(
        authRedirect(auth, Uri.parse('/teams/t1'), personal: p),
        '${Routes.chooseUsername}?from=%2Fteams%2Ft1',
      );
    });
  });

  group('agreeing to the guidelines and terms', () {
    String? go(
      FakeAgreementRepository a,
      String location, {
      FakePersonalDetailsRepository? personal,
      bool usernameMissing = false,
    }) => authRedirect(
      FakeAuthRepository(user: testUser)..usernameMissing = usernameMissing,
      Uri.parse(location),
      personal: personal,
      agreement: a,
    );

    test('everyone agrees first, then carries on where they were going', () {
      final a = FakeAgreementRepository(agreed: false);
      expect(go(a, '/teams/t1'), '${Routes.agreeTerms}?from=%2Fteams%2Ft1');
      expect(go(a, Routes.home), Routes.agreeTerms);
      expect(go(a, Routes.agreeTerms), isNull);
      a.agreed = true;
      expect(go(a, '${Routes.agreeTerms}?from=/teams/t1'), '/teams/t1');
      expect(go(a, Routes.agreeTerms), Routes.home);
      expect(go(a, '/teams/t1'), isNull);
    });

    test('an unknown answer holds nobody up', () {
      expect(go(FakeAgreementRepository(agreed: null), '/teams/t1'), isNull);
    });

    test('a failed check is not an unknown one: it blocks', () {
      final a = FakeAgreementRepository(agreed: null)..checkFailed = true;
      expect(go(a, '/teams/t1'), '${Routes.accountCheck}?from=%2Fteams%2Ft1');
      expect(go(a, Routes.home), Routes.accountCheck);
      expect(go(a, Routes.accountCheck), isNull);
      // Back to normal once a retry gets an answer.
      a
        ..checkFailed = false
        ..agreed = true;
      expect(go(a, '${Routes.accountCheck}?from=/teams/t1'), '/teams/t1');
      expect(go(a, Routes.accountCheck), Routes.home);
    });

    test('after the username, before personal details', () {
      final a = FakeAgreementRepository(agreed: false);
      expect(
        go(a, '/teams/t1', usernameMissing: true),
        '${Routes.chooseUsername}?from=%2Fteams%2Ft1',
      );
      final personal = FakePersonalDetailsRepository(
        status: const PersonalDetailsStatus(complete: false, required: true),
      );
      expect(
        go(a, '/teams/t1', personal: personal),
        '${Routes.agreeTerms}?from=%2Fteams%2Ft1',
      );
      a.agreed = true;
      expect(
        go(a, '/teams/t1', personal: personal),
        '${Routes.finishSignUp}?from=%2Fteams%2Ft1',
      );
    });
  });
}
