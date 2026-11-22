import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/playbook/view_models/whiteboard_viewmodel.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakePlayRepository plays;

  WhiteboardViewModel create({TeamRole role = TeamRole.coach, String? id}) {
    teams.teams['t1'] = teamWith({'owner': TeamRole.owner, 'u1': role});
    return WhiteboardViewModel(
      teamId: 't1',
      playId: id,
      playRepository: plays,
      teamRepository: teams,
      authRepository: FakeAuthRepository(user: testUser),
    );
  }

  const a = FieldPoint(0.2, 0.2), b = FieldPoint(0.5, 0.4);

  setUp(() {
    teams = FakeTeamRepository();
    plays = FakePlayRepository();
  });

  test('coaches can save, players only sketch', () async {
    final coach = create();
    await pumpEventQueue();
    expect(coach.canSave, isTrue);
    final player = create(role: TeamRole.player);
    await pumpEventQueue();
    expect(player.canSave, isFalse);
    player
      ..setTool(WhiteboardTool.pen)
      ..addStroke([a, b]);
    expect(player.strokes, hasLength(1));
  });

  test('draws strokes in the chosen colour, ignoring dots', () {
    final vm = create()..setColor(DrawingColor.turf);
    expect(vm.tool, WhiteboardTool.pen);
    vm.addStroke([a]);
    vm.addStroke([a, a]);
    expect(vm.strokes, isEmpty);
    expect(vm.dirty, isFalse);

    vm.addStroke([a, b, const FieldPoint(1.4, -0.1)]);
    final s = vm.strokes.single;
    expect(s.color, DrawingColor.turf);
    // Clamped to the field.
    expect(s.points.last, const FieldPoint(1, 0));
    expect(vm.dirty, isTrue);
    expect(vm.hasUnsaved, isTrue);
  });

  test('thins long strokes to the cap, keeping the ends', () {
    final vm = create();
    final pts = [for (var i = 0; i < 1000; i++) FieldPoint(i / 1000, 0.5)];
    vm.addStroke(pts);
    final s = vm.strokes.single.points;
    expect(s.length, lessThanOrEqualTo(Play.maxDrawingPoints));
    expect(s.first, pts.first);
    expect(s.last, pts.last);
  });

  test('stops at the stroke cap', () {
    final vm = create();
    for (var i = 0; i < Play.maxDrawings + 5; i++) {
      vm.addStroke([a, b]);
    }
    expect(vm.strokes, hasLength(Play.maxDrawings));
    expect(vm.strokesFull, isTrue);
  });

  test('drops numbered pieces and drags them as one undo step', () {
    final vm = create()..setTool(WhiteboardTool.offense);
    vm
      ..placeAt(a)
      ..placeAt(b);
    vm.setTool(WhiteboardTool.disc);
    vm.placeAt(const FieldPoint(0.5, 0.5));
    expect(vm.tokens.map((e) => e.label), ['1', '2', '']);
    // The pen and move tools don't drop anything.
    vm
      ..setTool(WhiteboardTool.pen)
      ..placeAt(a)
      ..setTool(WhiteboardTool.move)
      ..placeAt(a);
    expect(vm.tokens, hasLength(3));

    final id = vm.tokens.first.id;
    vm.beginMove(id);
    vm.moveToken(id, const FieldPoint(0.3, 0.3));
    vm.moveToken(id, const FieldPoint(0.9, 0.9));
    expect(vm.tokens.first.position, const FieldPoint(0.9, 0.9));
    vm.undo();
    expect(vm.tokens.first.position, a);
  });

  test('erases strokes and pieces, undo brings them back, clear wipes all', () {
    final vm = create();
    vm
      ..addStroke([a, b])
      ..addStroke([b, a])
      ..setTool(WhiteboardTool.cone)
      ..placeAt(a);
    final first = vm.strokes.first.id;
    vm.erase(first);
    expect(vm.strokes.map((s) => s.id), isNot(contains(first)));
    vm.erase(vm.tokens.single.id);
    expect(vm.tokens, isEmpty);
    vm.erase('nothing');

    vm
      ..undo()
      ..undo();
    expect(vm.strokes, hasLength(2));
    expect(vm.tokens, hasLength(1));

    vm.clear();
    expect(vm.isEmpty, isTrue);
    // A blank board drawn on and wiped has nothing to discard.
    expect(vm.hasUnsaved, isFalse);
    vm.undo();
    expect(vm.strokes, hasLength(2));
    expect(vm.canUndo, isTrue);
  });

  test('save as play: pieces as the setup, strokes kept, no steps', () async {
    final vm = create();
    vm
      ..setColor(DrawingColor.amber)
      ..addStroke([a, b])
      ..setTool(WhiteboardTool.defense)
      ..placeAt(b);

    final play = vm.toPlay(
      kind: PlayKind.play,
      name: 'Zone O',
      category: PlayCategory.endzone,
    );
    expect(play.isNew, isTrue);
    expect(play.kind, PlayKind.play);
    expect(play.category, PlayCategory.endzone);
    expect(play.steps, isEmpty);
    expect(play.arrows, isEmpty);
    expect(play.elements.single.position, b);
    expect(play.positionsAfter(0), {play.elements.single.id: b});
    expect(play.drawings.single.color, DrawingColor.amber);

    await vm.saveAsPlay.execute((
      name: ' Zone O ',
      category: PlayCategory.endzone,
    ));
    final saved = plays.plays.values.single;
    expect(saved.name, 'Zone O');
    expect(saved.isWhiteboard, isFalse);
    expect(saved.drawings, hasLength(1));
    expect(vm.dirty, isFalse);
    // Still a sketch, not a saved whiteboard.
    expect(vm.savedId, isNull);
  });

  test('save whiteboard creates one, then updates the same one', () async {
    final vm = create()..addStroke([a, b]);
    await vm.saveWhiteboard.execute('Chalk talk');
    expect(vm.savedId, 'p1');
    expect(vm.name, 'Chalk talk');
    expect(plays.plays['p1']!.kind, PlayKind.whiteboard);
    expect(plays.plays['p1']!.steps, isEmpty);

    vm.addStroke([b, a]);
    expect(vm.hasUnsaved, isTrue);
    await vm.saveWhiteboard.execute('Chalk talk');
    expect(plays.plays.keys, ['p1']);
    expect(plays.plays['p1']!.drawings, hasLength(2));
    expect(vm.hasUnsaved, isFalse);
  });

  test('opens a saved whiteboard, unchanged until edited', () async {
    plays.plays['w1'] = const Play(
      id: 'w1',
      name: 'Zone talk',
      kind: PlayKind.whiteboard,
      elements: [PlayElement(id: 'o1', kind: ElementKind.offense, position: a)],
      drawings: [
        PlayDrawing(id: 'k1', color: DrawingColor.white, points: [a, b]),
      ],
    );
    final vm = create(id: 'w1');
    await pumpEventQueue();
    expect(vm.name, 'Zone talk');
    expect(vm.strokes.single.id, 'k1');
    expect(vm.tokens.single.id, 'o1');
    expect(vm.hasUnsaved, isFalse);
    vm.clear();
    // Wiping a saved one is a change to it.
    expect(vm.hasUnsaved, isTrue);
  });

  test('a play opened here is only a starting sketch', () async {
    plays.plays['p9'] = Play(
      id: 'p9',
      name: 'Ho stack',
      elements: const [
        PlayElement(id: 'o1', kind: ElementKind.offense, position: a),
      ],
      steps: [
        PlayStep(
          id: 's1',
          paths: {
            'o1': [b],
          },
        ),
      ],
    );
    final vm = create(id: 'p9');
    await pumpEventQueue();
    expect(vm.tokens, hasLength(1));
    expect(vm.savedId, isNull);
    await vm.saveWhiteboard.execute('Board');
    // Saved as a new whiteboard; the play keeps its steps.
    expect(vm.savedId, isNot('p9'));
    expect(plays.plays['p9']!.steps, hasLength(1));
  });
}
