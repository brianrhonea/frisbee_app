import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/personal_details.dart';
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
    personal = FakePersonalDetailsRepository(
      status: const PersonalDetailsStatus(complete: false, required: true),
    )..signUpBirthDate = birth;
    final vm = PersonalDetailsViewModel(
      personalRepository: personal,
      authRepository: auth,
      finishing: finishing,
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
    expect(saved.guardian, isNull);
    expect(personal.mustComplete, isFalse);
  });

  testWidgets('a minor adds a parent or guardian', (tester) async {
    final now = DateTime.now();
    await pump(tester, birth: DateTime(now.year - 15, 1, 1));
    expect(find.text('Parent or guardian'), findsOneWidget);
    await fillAdultFields(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(personal.saved, isEmpty);
    expect(find.text("Enter your parent or guardian's name."), findsOneWidget);
  });

  testWidgets('an under-13 birthday when finishing removes the account', (
    tester,
  ) async {
    final now = DateTime.now();
    // As after Google sign-in: no birthday was asked before.
    await pump(tester, birth: DateTime(now.year - 10, 1, 1));
    auth.reauthenticated = true; // Just signed up.
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining(tooYoungMessage), findsOneWidget);
    expect(auth.deleted, isTrue);
    expect(personal.saved, isEmpty);
  });

  testWidgets('if removing needs a fresh sign-in, they are signed out', (
    tester,
  ) async {
    final now = DateTime.now();
    await pump(tester, birth: DateTime(now.year - 10, 1, 1));
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(auth.deleted, isFalse);
    expect(auth.currentUser, isNull);
  });

  testWidgets('refused by the API as under 13: the new account is removed', (
    tester,
  ) async {
    await pump(tester, birth: DateTime(1995, 4, 2));
    personal.refuseTooYoung = true;
    auth.reauthenticated = true; // Just signed up.
    await fillAdultFields(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining(tooYoungMessage), findsOneWidget);
    expect(auth.deleted, isTrue);
  });

  testWidgets('from Settings, an under-13 date is refused and nothing else', (
    tester,
  ) async {
    await pump(tester, finishing: false);
    expect(find.text('Personal details'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    personal.refuseTooYoung = true;
    await fillAdultFields(tester);
    await tester.tap(find.text('Date of birth'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      '04/02/1995',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text(tooYoungMessage), findsOneWidget); // The snack bar.
    expect(auth.deleted, isFalse);
    expect(auth.currentUser, isNotNull);
  });
}
