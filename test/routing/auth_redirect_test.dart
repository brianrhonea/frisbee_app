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

  test('signed-in users leave auth screens for their destination', () {
    final auth = FakeAuthRepository(user: testUser);
    expect(redirect(auth, Routes.signIn), Routes.home);
    expect(redirect(auth, '/sign-in?from=/teams/t1'), '/teams/t1');
    expect(redirect(auth, '/splash'), Routes.home);
    expect(redirect(auth, '/rankings'), isNull);
  });
}
