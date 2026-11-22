import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/playbook/view_models/whiteboard_viewmodel.dart';
import 'package:frisbee_app/ui/playbook/widgets/field_geometry.dart';
import 'package:frisbee_app/ui/playbook/widgets/playbook_tab.dart';
import 'package:frisbee_app/ui/playbook/widgets/whiteboard_canvas.dart';
import 'package:frisbee_app/ui/playbook/widgets/whiteboard_screen.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';
import 'package:go_router/go_router.dart';

import '../testing/fakes.dart';

const _field = Size(164, 451);

void main() {
  late FakeTeamRepository teams;
  late FakePlayRepository plays;
  final auth = FakeAuthRepository(user: testUser);

  void seed(TeamRole role) {
    teams = FakeTeamRepository();
    plays = FakePlayRepository();
    teams.teams['t1'] = teamWith({'owner': TeamRole.owner, 'u1': role});
    plays.plays['p1'] = const Play(id: 'p1', name: 'Ho stack');
    plays.plays['w1'] = const Play(
      id: 'w1',
      name: 'Zone talk',
      kind: PlayKind.whiteboard,
    );
  }

  WhiteboardViewModel board() => WhiteboardViewModel(
    teamId: 't1',
    playId: null,
    playRepository: plays,
    teamRepository: teams,
    authRepository: auth,
  );

  /// [child] on a route pushed over a home page, so it can be left.
  Future<void> pumpRouted(WidgetTester tester, Widget child) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Playbook home')),
          routes: [GoRoute(path: 'wb', builder: (_, _) => child)],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    router.push('/wb');
    await tester.pumpAndSettle();
  }

  group('playbook tab', () {
    testWidgets('switches between plays and the whiteboard', (tester) async {
      seed(TeamRole.coach);
      final vm = TeamDetailViewModel(
        teamId: 't1',
        teamRepository: teams,
        playRepository: plays,
        eventRepository: FakeEventRepository(),
        authRepository: auth,
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaybookTab(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Plays'), findsOneWidget);
      expect(find.text('Whiteboard'), findsOneWidget);
      // Plays: the play, not the saved whiteboard.
      expect(find.text('Ho stack'), findsOneWidget);
      expect(find.text('Zone talk'), findsNothing);
      expect(find.text('New play'), findsOneWidget);

      await tester.tap(find.text('Whiteboard'));
      await tester.pumpAndSettle();
      expect(find.text('Blank whiteboard'), findsOneWidget);
      expect(find.text('Open whiteboard'), findsOneWidget);
      expect(find.text('Saved whiteboards'), findsOneWidget);
      expect(find.text('Zone talk'), findsOneWidget);
      expect(find.text('Ho stack'), findsNothing);
      expect(find.text('New play'), findsNothing);
    });
  });

  group('whiteboard', () {
    testWidgets('a finger drag with the pen draws a stroke', (tester) async {
      seed(TeamRole.player);
      final vm = board();
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: _field,
                child: WhiteboardCanvas(viewModel: vm),
              ),
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(find.byType(WhiteboardCanvas));
      final g = FieldGeometry(_field, horizontal: false);
      Offset at(FieldPoint p) => origin + g.toCanvas(p);

      Future<void> drag(FieldPoint from, Offset by) async {
        final gesture = await tester.startGesture(at(from));
        for (var i = 0; i < 20; i++) {
          await gesture.moveBy(by / 20);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pump();
      }

      await drag(const FieldPoint(0.2, 0.3), const Offset(80, 120));
      expect(vm.strokes, hasLength(1));
      expect(vm.strokes.single.points.length, greaterThan(2));

      // A piece tool taps a player down; a drag from it moves it, and
      // doesn't draw.
      vm.setTool(WhiteboardTool.offense);
      await tester.tapAt(at(const FieldPoint(0.5, 0.8)));
      await tester.pump();
      expect(vm.tokens, hasLength(1));
      vm.setTool(WhiteboardTool.move);
      await drag(const FieldPoint(0.5, 0.8), const Offset(0, -60));
      expect(vm.strokes, hasLength(1));
      expect(vm.tokens.single.position.y, lessThan(0.8));

      // The eraser wipes the stroke it's dragged across.
      vm.setTool(WhiteboardTool.erase);
      final mid =
          vm.strokes.single.points[vm.strokes.single.points.length ~/ 2];
      await drag(mid, const Offset(6, 0));
      expect(vm.strokes, isEmpty);
      expect(vm.tokens, hasLength(1));
    });

    testWidgets('Discard leaves at once when nothing is drawn', (tester) async {
      seed(TeamRole.coach);
      final vm = board();
      addTearDown(vm.dispose);
      await pumpRouted(tester, WhiteboardScreen(viewModel: vm));

      // Nothing drawn: Discard just leaves.
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Playbook home'), findsOneWidget);
    });

    testWidgets('Discard on a sketch asks "Discard sketch?"', (tester) async {
      seed(TeamRole.coach);
      final vm = board();
      addTearDown(vm.dispose);
      await pumpRouted(tester, WhiteboardScreen(viewModel: vm));
      vm.addStroke(const [FieldPoint(0.1, 0.1), FieldPoint(0.6, 0.6)]);
      await tester.pump();

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Discard sketch?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(WhiteboardScreen), findsOneWidget);

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Playbook home'), findsOneWidget);
    });

    testWidgets('back with a sketch asks first too', (tester) async {
      seed(TeamRole.player);
      final vm = board();
      addTearDown(vm.dispose);
      await pumpRouted(tester, WhiteboardScreen(viewModel: vm));
      vm.addStroke(const [FieldPoint(0.1, 0.1), FieldPoint(0.6, 0.6)]);
      await tester.pump();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard sketch?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Playbook home'), findsOneWidget);
    });

    testWidgets('editors save from a menu; players only sketch', (
      tester,
    ) async {
      seed(TeamRole.coach);
      final vm = board();
      addTearDown(vm.dispose);
      await pumpRouted(tester, WhiteboardScreen(viewModel: vm));
      vm.addStroke(const [FieldPoint(0.1, 0.1), FieldPoint(0.6, 0.6)]);
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Save as play'), findsOneWidget);
      await tester.tap(find.text('Save whiteboard'));
      await tester.pumpAndSettle();
      // Named first, then saved as a whiteboard.
      await tester.enterText(find.byType(TextField), 'Zone D');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = plays.plays[vm.savedId]!;
      expect(saved.name, 'Zone D');
      expect(saved.isWhiteboard, isTrue);
      expect(find.text('Whiteboard saved'), findsOneWidget);

      seed(TeamRole.player);
      final viewer = board();
      addTearDown(viewer.dispose);
      await pumpRouted(tester, WhiteboardScreen(viewModel: viewer));
      expect(find.text('Save'), findsNothing);
      expect(find.textContaining('Only the team\'s admins'), findsOneWidget);
    });
  });
}
