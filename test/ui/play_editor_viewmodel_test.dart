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
    vm.beginMove();
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
}
