import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/playbook/view_models/play_editor_viewmodel.dart';
import 'package:frisbee_app/ui/playbook/widgets/field_geometry.dart';
import 'package:frisbee_app/ui/playbook/widgets/play_canvas.dart';

import '../testing/fakes.dart';

/// Phone-sized field: about what's left of an iPhone screen under the
/// app bar, toolbar and timeline.
const _field = Size(164, 451);

void main() {
  late PlayEditorViewModel vm;

  setUp(() {
    final teams = FakeTeamRepository();
    teams.teams['t1'] = teamWith({'owner': TeamRole.owner});
    vm = PlayEditorViewModel(
      teamId: 't1',
      playId: null,
      playRepository: FakePlayRepository(),
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
  });

  Future<Offset> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: _field,
              child: PlayCanvas(viewModel: vm),
            ),
          ),
        ),
      ),
    );
    return tester.getTopLeft(find.byType(PlayCanvas));
  }

  Offset at(Offset origin, FieldPoint p) =>
      origin + FieldGeometry(_field, horizontal: false).toCanvas(p);

  /// A finger drag in small steps, like a real touch.
  Future<void> fingerDrag(
    WidgetTester tester,
    Offset from,
    Offset by, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) async {
    final g = await tester.startGesture(from, kind: kind);
    const steps = 20;
    for (var i = 0; i < steps; i++) {
      await g.moveBy(by / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();
  }

  testWidgets('a finger drag in a step moves the player from the start', (
    tester,
  ) async {
    vm
      ..setTool(EditorTool.offense)
      ..placeAt(const FieldPoint(0.5, 0.5))
      ..addStep();
    final id = vm.play.elements.single.id;
    final origin = await pump(tester);

    await fingerDrag(
      tester,
      at(origin, const FieldPoint(0.5, 0.5)),
      const Offset(0, -80),
    );

    final path = vm.play.steps.single.paths[id];
    expect(path, isNotNull, reason: 'the drag should record a cut');
    expect(path!.last.y, closeTo(0.5 - 80 / _field.height, 0.02));
  });

  testWidgets('a finger slightly off the dot still grabs it', (tester) async {
    vm
      ..setTool(EditorTool.offense)
      ..placeAt(const FieldPoint(0.5, 0.5))
      ..addStep();
    final id = vm.play.elements.single.id;
    final origin = await pump(tester);

    await fingerDrag(
      tester,
      at(origin, const FieldPoint(0.5, 0.5)) + const Offset(16, 8),
      const Offset(0, -80),
    );
    expect(vm.play.steps.single.paths[id], isNotNull);
  });

  testWidgets('a short finger drag in the setup moves the player', (
    tester,
  ) async {
    vm
      ..setTool(EditorTool.offense)
      ..placeAt(const FieldPoint(0.5, 0.5))
      ..setTool(EditorTool.select);
    final origin = await pump(tester);

    await fingerDrag(
      tester,
      at(origin, const FieldPoint(0.5, 0.5)),
      const Offset(0, -25),
    );
    expect(
      vm.play.elements.single.position.y,
      closeTo(0.5 - 25 / _field.height, 0.02),
    );
  });

  testWidgets('a finger-drawn cut starts where the finger went down', (
    tester,
  ) async {
    vm.setTool(EditorTool.cut);
    final origin = await pump(tester);
    final start = at(origin, const FieldPoint(0.5, 0.5));

    await fingerDrag(tester, start, const Offset(0, -120));

    final arrow = vm.play.arrows.single;
    expect(arrow.points.first.y, closeTo(0.5, 0.02));
  });
}
