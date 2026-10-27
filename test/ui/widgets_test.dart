import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/auth/view_models/sign_in_viewmodel.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_in_screen.dart';
import 'package:frisbee_app/ui/playbook/view_models/play_editor_viewmodel.dart';
import 'package:frisbee_app/ui/playbook/widgets/play_canvas.dart';

import '../testing/fakes.dart';

void main() {
  testWidgets('sign-in validates and signs in', (tester) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(viewModel: SignInViewModel(authRepository: auth)),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
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
