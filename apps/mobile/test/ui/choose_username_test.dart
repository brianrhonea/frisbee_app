// "Your name and username": the step Google and Apple accounts (and new
// accounts without a name) see before anything else. The website's
// UsernameStep (apps/web/components/UsernameStep.tsx) does the same; the
// shared rules are checked by packages/shared/test/profile.test.ts.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/person_name.dart';
import 'package:frisbee_app/domain/models/personal_details.dart';
import 'package:frisbee_app/domain/models/username.dart';
import 'package:frisbee_app/routing/router.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/auth/view_models/choose_username_viewmodel.dart';
import 'package:frisbee_app/ui/auth/widgets/choose_username_screen.dart';
import 'package:frisbee_app/ui/personal/view_models/personal_details_viewmodel.dart';

import '../testing/fakes.dart';

void main() {
  FakeAuthRepository account({
    String? name,
    SignInMethod method = SignInMethod.google,
    bool usernameMissing = true,
  }) =>
      FakeAuthRepository(
          user: AppUser(uid: 'u1', email: 'pat@x.test', displayName: name),
        )
        ..method = method
        ..usernameMissing = usernameMissing;

  group('PersonName and Username.suggest', () {
    test('split the provider name for the boxes', () {
      expect(PersonName.split('Pat Lee'), (first: 'Pat', last: 'Lee'));
      expect(PersonName.split('Mary Ann Smith'), (
        first: 'Mary',
        last: 'Ann Smith',
      ));
      expect(PersonName.split(null), (first: '', last: ''));
      // An Apple relay address is never a name.
      expect(PersonName.split('x1@privaterelay.appleid.com'), (
        first: '',
        last: '',
      ));
      expect(PersonName.split('A' * 40).first.length, PersonName.maxFirst);
      expect(PersonName.join(' Pat ', ' Lee '), 'Pat Lee');
      expect(Username.suggest('Pat Lee'), 'pat.lee');
    });

    test('asks Google and Apple accounts, and anyone without a name', () {
      expect(PersonName.asks('Pat Lee', hasPassword: false), isTrue);
      expect(PersonName.asks('', hasPassword: true), isTrue);
      expect(PersonName.asks('Pat Lee', hasPassword: true), isFalse);
    });
  });

  group('ChooseUsernameViewModel', () {
    test('Google: asks the name, started from Google\'s', () {
      final vm = ChooseUsernameViewModel(
        authRepository: account(name: 'Pat Lee'),
      );
      addTearDown(vm.dispose);
      expect(vm.asksName, isTrue);
      expect(vm.needsUsername, isTrue);
      expect(vm.prefillName, (first: 'Pat', last: 'Lee'));
      expect(vm.suggestionFor('Pat', 'Lee'), 'pat.lee');
      expect(vm.title, 'Your name and username');
    });

    test('an email account with a name picks only a username', () {
      final vm = ChooseUsernameViewModel(
        authRepository: account(name: 'Pat Lee', method: SignInMethod.password),
      );
      addTearDown(vm.dispose);
      expect(vm.asksName, isFalse);
      expect(vm.title, 'Pick your username');
      expect(vm.suggestionFor('', ''), 'pat.lee');
    });

    test('saves the name, then claims the username', () async {
      final auth = account(name: 'Pat Lee');
      final personal = FakePersonalDetailsRepository();
      final vm = ChooseUsernameViewModel(
        authRepository: auth,
        personalRepository: personal,
      );
      addTearDown(vm.dispose);
      await vm.save.execute((
        firstName: ' Patricia ',
        lastName: 'Lee',
        username: 'plee',
      ));
      expect(vm.save.completed, isTrue);
      expect(auth.savedName, (first: 'Patricia', last: 'Lee'));
      expect(auth.currentUser?.displayName, 'Patricia Lee');
      expect(auth.currentUser?.username, 'plee');
      expect(auth.needsUsername, isFalse);
      // For "About you", which comes next.
      expect(personal.takeSignUpName(), (first: 'Patricia', last: 'Lee'));
    });

    test('an unchanged name isn\'t saved again', () async {
      final auth = account(name: 'Pat Lee');
      final vm = ChooseUsernameViewModel(authRepository: auth);
      addTearDown(vm.dispose);
      await vm.save.execute((
        firstName: 'Pat',
        lastName: 'Lee',
        username: 'pat',
      ));
      expect(auth.savedName, isNull);
      expect(auth.currentUser?.username, 'pat');
    });

    test('both names are required', () async {
      final auth = account();
      final vm = ChooseUsernameViewModel(authRepository: auth);
      addTearDown(vm.dispose);
      await vm.save.execute((firstName: 'Pat', lastName: ' ', username: 'pat'));
      expect(vm.save.error, isTrue);
      expect(auth.savedName, isNull);
      expect(auth.currentUser?.username, isNull);
    });
  });

  group('ChooseUsernameScreen', () {
    Future<void> pump(WidgetTester tester, ChooseUsernameViewModel vm) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ChooseUsernameScreen(viewModel: vm)),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }

    Finder field(String label) => find.widgetWithText(TextFormField, label);
    String usernameText(WidgetTester t) =>
        t.widget<TextFormField>(field('Username')).controller!.text;

    testWidgets('Google: the name is prefilled and the username follows it', (
      tester,
    ) async {
      final auth = account(name: 'Pat Lee');
      final personal = FakePersonalDetailsRepository();
      await pump(
        tester,
        ChooseUsernameViewModel(
          authRepository: auth,
          personalRepository: personal,
        ),
      );
      expect(find.text('Your name and username'), findsOneWidget);
      expect(find.text('Pat'), findsOneWidget);
      expect(find.text('Lee'), findsOneWidget);
      expect(usernameText(tester), 'pat.lee');
      expect(find.text('@pat.lee is available'), findsOneWidget);

      await tester.enterText(field('Last name'), 'Leeds');
      await tester.pump(const Duration(milliseconds: 500));
      expect(usernameText(tester), 'pat.leeds');

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(auth.currentUser?.displayName, 'Pat Leeds');
      expect(auth.currentUser?.username, 'pat.leeds');
      expect(personal.takeSignUpName(), (first: 'Pat', last: 'Leeds'));
    });

    testWidgets('an edited username stays as typed', (tester) async {
      final auth = account(name: 'Pat Lee');
      await pump(tester, ChooseUsernameViewModel(authRepository: auth));
      await tester.enterText(field('Username'), 'ultimate.pat');
      await tester.enterText(field('First name'), 'Patricia');
      await tester.pump(const Duration(milliseconds: 500));
      expect(usernameText(tester), 'ultimate.pat');
    });

    testWidgets('Apple with no name: both names are asked', (tester) async {
      final auth = account(method: SignInMethod.apple);
      await pump(tester, ChooseUsernameViewModel(authRepository: auth));
      expect(find.text('Your name and username'), findsOneWidget);
      expect(usernameText(tester), '');

      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('Enter your first name'), findsOneWidget);
      expect(find.text('Enter your last name'), findsOneWidget);
      expect(auth.savedName, isNull);

      await tester.enterText(field('First name'), 'Sam');
      await tester.enterText(field('Last name'), 'Rivera');
      await tester.pump(const Duration(milliseconds: 500));
      expect(usernameText(tester), 'sam.rivera');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(auth.currentUser?.displayName, 'Sam Rivera');
      expect(auth.currentUser?.username, 'sam.rivera');
    });

    testWidgets('a username but no name: only the name is asked', (
      tester,
    ) async {
      final auth = account(method: SignInMethod.apple, usernameMissing: false);
      await pump(tester, ChooseUsernameViewModel(authRepository: auth));
      expect(find.text('Your name'), findsOneWidget);
      expect(field('Username'), findsNothing);
      await tester.enterText(field('First name'), 'Sam');
      await tester.enterText(field('Last name'), 'Rivera');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(auth.currentUser?.displayName, 'Sam Rivera');
      expect(auth.needsName, isFalse);
    });
  });

  group('router', () {
    const newAccount = PersonalDetailsStatus(complete: false, required: true);
    const olderAccount = PersonalDetailsStatus(
      complete: false,
      required: false,
    );

    test('a new account without a name is asked it first', () {
      final auth = account(method: SignInMethod.apple, usernameMissing: false);
      final p = FakePersonalDetailsRepository(status: newAccount);
      expect(
        authRedirect(auth, Uri.parse('/teams/t1'), personal: p),
        '${Routes.chooseUsername}?from=%2Fteams%2Ft1',
      );
      expect(
        authRedirect(auth, Uri.parse(Routes.chooseUsername), personal: p),
        isNull,
      );

      // Named: on, and from there to "About you".
      auth.setUser(
        const AppUser(uid: 'u1', displayName: 'Sam Rivera', username: 'sam'),
      );
      expect(
        authRedirect(auth, Uri.parse(Routes.chooseUsername), personal: p),
        Routes.home,
      );
      expect(
        authRedirect(auth, Uri.parse(Routes.home), personal: p),
        Routes.finishSignUp,
      );
    });

    test('older accounts keep today\'s rules', () {
      final auth = account(method: SignInMethod.apple, usernameMissing: false);
      final p = FakePersonalDetailsRepository(status: olderAccount);
      expect(authRedirect(auth, Uri.parse('/teams/t1'), personal: p), isNull);
      // Without a username they're asked (and the step asks the name too).
      auth.usernameMissing = true;
      expect(
        authRedirect(auth, Uri.parse(Routes.home), personal: p),
        Routes.chooseUsername,
      );
    });
  });

  test('"About you" starts the legal name from the name just typed', () {
    final auth = account(name: 'Mary Ann Smith');
    final personal = FakePersonalDetailsRepository(
      status: const PersonalDetailsStatus(complete: false, required: true),
    )..signUpName = (first: 'Mary Ann', last: 'Smith');
    final vm = PersonalDetailsViewModel(
      personalRepository: personal,
      authRepository: auth,
      finishing: true,
    );
    addTearDown(vm.dispose);
    expect(vm.prefillName, (first: 'Mary Ann', last: 'Smith'));

    // Without it (the app was restarted), the profile name split.
    final again = PersonalDetailsViewModel(
      personalRepository: personal,
      authRepository: auth,
      finishing: true,
    );
    addTearDown(again.dispose);
    expect(again.prefillName, (first: 'Mary', last: 'Ann Smith'));
  });
}
