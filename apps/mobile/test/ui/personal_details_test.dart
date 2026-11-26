import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/account_gate/account_gate.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/personal_details.dart';
import 'package:frisbee_app/ui/auth/view_models/sign_up_viewmodel.dart';
import 'package:frisbee_app/ui/personal/view_models/personal_details_viewmodel.dart';
import 'package:frisbee_app/ui/personal/widgets/personal_details_screen.dart';

import '../testing/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakePersonalDetailsRepository personal;

  Future<PersonalDetailsViewModel> pump(
    WidgetTester tester, {
    bool finishing = true,
    DateTime? birth,
    DateTime? savedBirth,
    bool offline = false,
    AccountGate? gate,
  }) async {
    tester.view.physicalSize = const Size(500, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    auth = FakeAuthRepository(
      user: const AppUser(
        uid: 'u1',
        displayName: 'Pat Lee',
        email: 'pat@x.test',
      ),
    );
    personal =
        FakePersonalDetailsRepository(
            status: const PersonalDetailsStatus(
              complete: false,
              required: true,
            ),
          )
          ..email = 'pat@x.test'
          ..signUpBirthDate = birth
          ..savedSignUpBirthDate = savedBirth
          ..failLoad = offline;
    final vm = PersonalDetailsViewModel(
      personalRepository: personal,
      authRepository: auth,
      finishing: finishing,
      accountGate: gate,
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(home: PersonalDetailsScreen(viewModel: vm)),
    );
    await tester.pumpAndSettle();
    return vm;
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> fillAdultFields(WidgetTester tester) async {
    await tester.tap(find.text('Gender'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prefer not to say').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Phone').first, '555-010-2030');
    await tester.enterText(field('Street address'), '1 Main St');
    await tester.enterText(field('City'), 'Boston');
    await tester.enterText(field('State'), 'MA');
    await tester.enterText(field('ZIP code'), '02110');
  }

  testWidgets('starts from the profile name and the sign-up birthday', (
    tester,
  ) async {
    await pump(tester, birth: DateTime(1995, 4, 2));
    expect(find.text('Pat'), findsOneWidget);
    expect(find.text('Lee'), findsOneWidget);
    expect(find.text('pat@x.test'), findsOneWidget);
    expect(find.text('Parent or guardian'), findsNothing);

    await fillAdultFields(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    final saved = personal.saved.single;
    expect(saved.legalFirstName, 'Pat');
    expect(saved.birthDate, DateTime(1995, 4, 2));
    expect(saved.address.country, 'US');
    expect(personal.mustComplete, isFalse);
  });

  testWidgets('there is no guardian step: under 18 is the dead end', (
    tester,
  ) async {
    final now = DateTime.now();
    final gate = AccountGate();
    await pump(tester, birth: DateTime(now.year - 15, 1, 1), gate: gate);
    expect(find.text('Parent or guardian'), findsNothing);
    await fillAdultFields(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    // Nothing is sent or removed; the router shows the adults-only screen.
    expect(gate.underAge, isTrue);
    expect(personal.saved, isEmpty);
    expect(auth.deleted, isFalse);
    expect(auth.currentUser, isNotNull);
  });

  testWidgets('refused by the API as under 18: the dead end, no delete', (
    tester,
  ) async {
    final gate = AccountGate();
    await pump(tester, birth: DateTime(1995, 4, 2), gate: gate);
    personal.refuseTooYoung = true;
    await fillAdultFields(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(gate.underAge, isTrue);
    expect(auth.deleted, isFalse);
    expect(auth.currentUser, isNotNull);
  });

  testWidgets('from Settings, an under-18 date is refused with the message', (
    tester,
  ) async {
    final now = DateTime.now();
    await pump(tester, finishing: false, birth: DateTime(now.year - 15, 1, 1));
    expect(find.text('Personal details'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    await fillAdultFields(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text(adultOnlyMessage), findsOneWidget);
    expect(personal.saved, isEmpty);
  });

  group('the birth date once saved', () {
    testWidgets('is shown read-only, with where to write', (tester) async {
      await pump(tester, savedBirth: DateTime(1995, 4, 2));
      expect(find.text(birthDateLockedHint), findsOneWidget);
      await tester.tap(find.text('Date of birth'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('a date only typed at sign-up (not saved) is editable', (
      tester,
    ) async {
      await pump(tester, birth: DateTime(1996, 5, 6), offline: true);
      expect(find.text(birthDateLockedHint), findsNothing);
      await tester.tap(find.text('Date of birth'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('a refused change shows the message and support hint', (
      tester,
    ) async {
      await pump(tester, birth: DateTime(1995, 4, 2), offline: true);
      personal.refuseLocked = true;
      await fillAdultFields(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text(birthDateLockedHint), findsOneWidget);
      expect(personal.saved, isEmpty);
    });
  });

  group('the sign-up birthday', () {
    SignUpForm form(DateTime birth) => (
      firstName: 'Pat',
      lastName: 'Lee',
      username: 'patlee',
      email: 'pat@x.test',
      password: 'correct horse battery',
      birthDate: birth,
    );

    test('email sign-up saves it, without completing the details', () async {
      final auth = FakeAuthRepository();
      final personal = FakePersonalDetailsRepository(
        status: const PersonalDetailsStatus(complete: false, required: true),
      );
      final vm = SignUpViewModel(
        authRepository: auth,
        personalRepository: personal,
      );
      addTearDown(vm.dispose);
      await vm.signUp.execute(form(DateTime(1995, 4, 2)));
      expect(vm.signUp.completed, isTrue);
      expect(personal.savedSignUpBirthDate, DateTime(1995, 4, 2));
      expect(personal.mustComplete, isTrue);
    });

    test('the birth date is saved before the username is claimed', () async {
      final auth = FakeAuthRepository();
      final personal = FakePersonalDetailsRepository();
      final vm = SignUpViewModel(
        authRepository: auth,
        personalRepository: personal,
      );
      addTearDown(vm.dispose);
      await vm.signUp.execute(form(DateTime(1995, 4, 2)));
      expect(personal.savedSignUpBirthDate, DateTime(1995, 4, 2));
      expect(auth.events, ['account-created', 'claim-username']);
    });

    test('a save that cannot be reached never holds up sign-up', () async {
      final auth = FakeAuthRepository();
      final personal = FakePersonalDetailsRepository()
        ..saveBirthDateError = Exception('offline');
      final vm = SignUpViewModel(
        authRepository: auth,
        personalRepository: personal,
      );
      addTearDown(vm.dispose);
      await vm.signUp.execute(form(DateTime(1995, 4, 2)));
      expect(vm.signUp.completed, isTrue);
      expect(auth.currentUser, isNotNull);
      expect(personal.savedSignUpBirthDate, isNull);
    });

    test(
      'refused by the server as under 18: nothing else is written',
      () async {
        final auth = FakeAuthRepository();
        final personal = FakePersonalDetailsRepository()..refuseTooYoung = true;
        final vm = SignUpViewModel(
          authRepository: auth,
          personalRepository: personal,
        );
        addTearDown(vm.dispose);
        await vm.signUp.execute(form(DateTime(1995, 4, 2)));
        expect(auth.events, ['account-created']);
        expect(personal.savedSignUpBirthDate, isNull);
      },
    );

    test('18 and over only: under 18 makes no account', () async {
      final auth = FakeAuthRepository();
      final vm = SignUpViewModel(
        authRepository: auth,
        personalRepository: FakePersonalDetailsRepository(),
      );
      addTearDown(vm.dispose);
      final now = DateTime.now();
      // 17 years and 11 months old: still refused.
      expect(
        vm.birthDateProblemOn(DateTime(now.year - 18, now.month + 1, 1)),
        adultOnlyMessage,
      );
      expect(vm.birthDateProblemOn(DateTime(now.year - 18, 1, 1)), isNull);
      await vm.signUp.execute(form(DateTime(now.year - 15, 1, 1)));
      expect(vm.signUp.error, isTrue);
      expect(auth.currentUser, isNull);
      expect(auth.events, isEmpty);
    });

    test('nothing is saved when no account was made', () async {
      final auth = FakeAuthRepository()..takenUsernames.add('patlee');
      final personal = FakePersonalDetailsRepository();
      final vm = SignUpViewModel(
        authRepository: auth,
        personalRepository: personal,
      );
      addTearDown(vm.dispose);
      await vm.signUp.execute(form(DateTime(1995, 4, 2)));
      expect(vm.signUp.error, isTrue);
      expect(personal.savedSignUpBirthDate, isNull);
    });

    testWidgets('About you starts from the saved one after a fresh start', (
      tester,
    ) async {
      // Nothing in memory (a restart, another device): only the API's copy.
      final vm = await pump(tester, savedBirth: DateTime(1995, 4, 2));
      expect(vm.prefillBirthDate, DateTime(1995, 4, 2));
      await fillAdultFields(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(personal.saved.single.birthDate, DateTime(1995, 4, 2));
    });

    testWidgets('offline, it starts from the one in memory', (tester) async {
      final vm = await pump(tester, birth: DateTime(1996, 5, 6), offline: true);
      expect(vm.load.completed, isTrue);
      expect(vm.prefillBirthDate, DateTime(1996, 5, 6));
      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    });
  });
}
