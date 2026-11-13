import 'package:flutter_test/flutter_test.dart';
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
}
