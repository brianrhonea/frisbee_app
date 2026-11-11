import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/playbook/view_models/play_editor_viewmodel.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakePlayRepository plays;

  PlayEditorViewModel create({TeamRole role = TeamRole.coach, String? playId}) {
    teams.teams['t1'] = teamWith({'owner': TeamRole.owner, 'u1': role});
    return PlayEditorViewModel(
      teamId: 't1',
      playId: playId,
      playRepository: plays,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
  }

  setUp(() {
    teams = FakeTeamRepository();
    plays = FakePlayRepository();
  });

  test('coaches can edit, players cannot', () async {
    final coach = create();
    await pumpEventQueue();
    expect(coach.canEdit, isTrue);

    final player = create(role: TeamRole.player);
    await pumpEventQueue();
    expect(player.canEdit, isFalse);
  });

  test('places numbered players and supports undo/redo', () {
    final vm = create()..setTool(EditorTool.offense);
    vm.placeAt(const FieldPoint(0.5, 0.5));
    vm.placeAt(const FieldPoint(0.6, 0.5));
    expect(vm.play.elements.map((e) => e.label), ['1', '2']);
    expect(vm.dirty, isTrue);

    vm.undo();
    expect(vm.play.elements, hasLength(1));
    vm.redo();
    expect(vm.play.elements, hasLength(2));
  });

  test('reuses the lowest free player number', () {
    final vm = create()..setTool(EditorTool.defense);
    vm
      ..placeAt(const FieldPoint(0.1, 0.1))
      ..placeAt(const FieldPoint(0.2, 0.2))
      ..placeAt(const FieldPoint(0.3, 0.3));
    vm.deleteItem(vm.play.elements[1].id);
    vm.placeAt(const FieldPoint(0.4, 0.4));
    expect(vm.play.elements.map((e) => e.label), ['1', '3', '2']);
  });

  test('clamps positions to the field', () {
    final vm = create()..setTool(EditorTool.cone);
    vm.placeAt(const FieldPoint(-1, 2));
    expect(vm.play.elements.single.position, const FieldPoint(0, 1));
  });

  test('throws become straight; tiny drags are ignored', () {
    final vm = create()..setTool(EditorTool.throw_);
    vm.addArrow(const [
      FieldPoint(0.1, 0.1),
      FieldPoint(0.3, 0.2),
      FieldPoint(0.5, 0.5),
    ]);
    expect(vm.play.arrows.single.points, hasLength(2));

    vm.addArrow(const [FieldPoint(0.5, 0.5), FieldPoint(0.505, 0.5)]);
    expect(vm.play.arrows, hasLength(1));

    vm.setTool(EditorTool.cut);
    vm.addArrow(const [
      FieldPoint(0.1, 0.1),
      FieldPoint(0.3, 0.2),
      FieldPoint(0.5, 0.5),
    ]);
    expect(vm.play.arrows.last.kind, ArrowKind.cut);
    expect(vm.play.arrows.last.points, hasLength(3));
  });

  test('a drag is a single undo step', () {
    final vm = create()..setTool(EditorTool.offense);
    vm.placeAt(const FieldPoint(0.5, 0.5));
    final id = vm.play.elements.single.id;
    vm.beginMove(id);
    vm.moveElement(id, const FieldPoint(0.6, 0.6));
    vm.moveElement(id, const FieldPoint(0.7, 0.7));
    vm.undo();
    expect(vm.play.elements.single.position, const FieldPoint(0.5, 0.5));
  });

  test('save assigns an id and clears dirty', () async {
    final vm = create()..setTool(EditorTool.disc);
    vm.placeAt(const FieldPoint(0.5, 0.5));
    await vm.save.execute();
    expect(vm.save.completed, isTrue);
    expect(vm.play.id, 'p1');
    expect(vm.dirty, isFalse);
    expect(plays.plays['p1']!.elements, hasLength(1));
  });

  test('loads an existing play', () async {
    plays.plays['p9'] = const Play(id: 'p9', name: 'Loaded');
    final vm = create(playId: 'p9');
    await pumpEventQueue();
    expect(vm.play.name, 'Loaded');
    expect(vm.load.completed, isTrue);
  });

  group('animation steps', () {
    PlayEditorViewModel withPlayers() {
      final vm = create()..setTool(EditorTool.offense);
      vm.placeAt(const FieldPoint(0.5, 0.5));
      vm.setTool(EditorTool.disc);
      vm.placeAt(const FieldPoint(0.2, 0.2));
      return vm;
    }

    void drag(PlayEditorViewModel vm, String id, List<FieldPoint> points) {
      vm.beginMove(id);
      for (final p in points) {
        vm.moveElement(id, p);
      }
    }

    test('dragging in a step records a path, not a new setup', () {
      final vm = withPlayers();
      final player = vm.play.elements.first.id;
      vm.addStep();
      expect(vm.step, 1);
      drag(vm, player, const [
        FieldPoint(0.5, 0.4),
        FieldPoint(0.6, 0.3),
        FieldPoint(0.7, 0.2),
      ]);
      expect(vm.play.elements.first.position, const FieldPoint(0.5, 0.5));
      expect(
        vm.play.steps.single.paths[player]!.last,
        const FieldPoint(0.7, 0.2),
      );
      expect(vm.displayed.elements.first.position, const FieldPoint(0.7, 0.2));
      expect(vm.trails.single.points.first, const FieldPoint(0.5, 0.5));
      expect(vm.ghosts.single.position, const FieldPoint(0.5, 0.5));
    });

    test('disc drags become straight throws', () {
      final vm = withPlayers();
      final disc = vm.play.elements.last.id;
      vm.addStep();
      drag(vm, disc, const [FieldPoint(0.3, 0.3), FieldPoint(0.6, 0.1)]);
      expect(vm.play.steps.single.paths[disc], [const FieldPoint(0.6, 0.1)]);
    });

    test('placement tools are disabled outside the setup', () {
      final vm = withPlayers()..addStep();
      expect(vm.tool, EditorTool.select);
      vm.setTool(EditorTool.offense);
      vm.placeAt(const FieldPoint(0.9, 0.9));
      expect(vm.play.elements, hasLength(2));
    });

    test('next step starts where the last one ended', () {
      final vm = withPlayers();
      final player = vm.play.elements.first.id;
      vm.addStep();
      drag(vm, player, const [FieldPoint(0.5, 0.2)]);
      vm.addStep();
      expect(vm.displayed.elements.first.position, const FieldPoint(0.5, 0.2));
      drag(vm, player, const [FieldPoint(0.8, 0.2)]);
      expect(vm.trails.single.points.first, const FieldPoint(0.5, 0.2));
    });

    test('erase clears movement; deleting a player strips its paths', () {
      final vm = withPlayers();
      final player = vm.play.elements.first.id;
      vm.addStep();
      drag(vm, player, const [FieldPoint(0.5, 0.2)]);
      vm.deleteItem(player);
      expect(vm.play.elements, hasLength(2));
      expect(vm.play.steps.single.paths, isEmpty);

      drag(vm, player, const [FieldPoint(0.5, 0.2)]);
      vm.selectStep(0);
      vm.deleteItem(player);
      expect(vm.play.steps.single.paths, isEmpty);
    });

    test('undo restores steps and keeps the step index valid', () {
      final vm = withPlayers()
        ..addStep()
        ..addStep();
      expect(vm.step, 2);
      vm.undo();
      expect(vm.stepCount, 1);
      expect(vm.step, 1);
    });

    test('step notes and deletion', () {
      final vm = withPlayers()..addStep();
      vm.setStepNote('Swing');
      expect(vm.stepNote, 'Swing');
      vm.deleteStep(1);
      expect(vm.stepCount, 0);
      expect(vm.editingSetup, isTrue);
    });
  });
}
