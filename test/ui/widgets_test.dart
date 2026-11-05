import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/auth/view_models/choose_username_viewmodel.dart';
import 'package:frisbee_app/ui/auth/view_models/sign_in_viewmodel.dart';
import 'package:frisbee_app/ui/auth/view_models/sign_up_viewmodel.dart';
import 'package:frisbee_app/ui/auth/widgets/choose_username_screen.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_in_screen.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_up_screen.dart';
import 'package:frisbee_app/ui/playbook/view_models/play_editor_viewmodel.dart';
import 'package:frisbee_app/ui/playbook/widgets/play_canvas.dart';

import '../testing/fakes.dart';

void main() {
  testWidgets('sign-up asks for names, a free username and a strong password', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = FakeAuthRepository()..takenUsernames.add('pat');
    final vm = SignUpViewModel(authRepository: auth);
    addTearDown(vm.dispose);
    await tester.pumpWidget(MaterialApp(home: SignUpScreen(viewModel: vm)));
    await tester.pumpAndSettle();

    Finder field(String label) => find.widgetWithText(TextFormField, label);
    await tester.enterText(field('First name'), 'Pat');
    await tester.enterText(field('Last name'), 'Lee');
    await tester.enterText(field('Username'), 'Pat');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('@pat is taken'), findsOneWidget);

    await tester.enterText(field('Username'), 'pat.lee');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('@pat.lee is available'), findsOneWidget);

    await tester.enterText(field('Email'), 'pat@example.com');
    await tester.enterText(field('Password'), 'pull1234');
    await tester.pump();
    expect(find.text('Fair'), findsOneWidget);
    await tester.enterText(field('Confirm password'), 'pull12345');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text("Passwords don't match"), findsOneWidget);
    expect(auth.currentUser, isNull);

    await tester.enterText(field('Confirm password'), 'pull1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(auth.currentUser?.displayName, 'Pat Lee');
    expect(auth.currentUser?.username, 'pat.lee');
    expect(auth.needsUsername, isFalse);
  });

  testWidgets('Google and Apple sign-ups pick a username', (tester) async {
    final auth = FakeAuthRepository(
      user: const AppUser(uid: 'u1', displayName: 'Brian Honea'),
    )..usernameMissing = true;
    auth.takenUsernames.add('brian.honea');
    final vm = ChooseUsernameViewModel(authRepository: auth);
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ChooseUsernameScreen(viewModel: vm)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    // Suggested from their name, but taken.
    expect(find.text('@brian.honea is taken'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'bhonea');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(auth.needsUsername, isFalse);
    expect(auth.currentUser?.username, 'bhonea');
  });

  testWidgets('sign-in validates and signs in', (tester) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(viewModel: SignInViewModel(authRepository: auth)),
      ),
    );

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(auth.currentUser?.email, 'a@b.com');
  });

  testWidgets('sign-in shows repository errors', (tester) async {
    final auth = FakeAuthRepository()..nextError = Exception('Bad password');
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(viewModel: SignInViewModel(authRepository: auth)),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'nope');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Bad password'), findsOneWidget);
  });

  testWidgets('tapping the field places a player', (tester) async {
    final teams = FakeTeamRepository();
    teams.teams['t1'] = teamWith({'u1': TeamRole.owner});
    final vm = PlayEditorViewModel(
      teamId: 't1',
      playId: null,
      playRepository: FakePlayRepository(),
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    )..setTool(EditorTool.offense);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: PlayCanvas(viewModel: vm),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(PlayCanvas));
    await tester.pump();
    expect(vm.play.elements, hasLength(1));
    final p = vm.play.elements.single.position;
    expect(p.x, closeTo(0.5, 0.02));
    expect(p.y, closeTo(0.5, 0.02));

    // Tapping the same spot with select picks the element.
    vm.setTool(EditorTool.select);
    await tester.tap(find.byType(PlayCanvas));
    await tester.pump();
    expect(vm.selectedId, vm.play.elements.single.id);
  });
}
