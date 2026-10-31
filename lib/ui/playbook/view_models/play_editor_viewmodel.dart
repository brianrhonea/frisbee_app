import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/playbook/play_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/play.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

enum EditorTool { select, offense, defense, disc, cone, cut, throw_, erase }

typedef _Snapshot = ({
  List<PlayElement> elements,
  List<PlayArrow> arrows,
  List<PlayStep> steps,
});

/// A movement path drawn behind the elements in a step view.
typedef Trail = ({ElementKind kind, List<FieldPoint> points});

class PlayEditorViewModel extends ChangeNotifier {
  PlayEditorViewModel({
    required this.teamId,
    required this.playId,
    required PlayRepository playRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _plays = playRepository,
       _auth = authRepository {
    load = Command0<void>(_load)..execute();
    save = Command0<String>(_save);
    _teamSub = teamRepository.watchTeam(teamId).listen((t) {
      _team = t;
      notifyListeners();
    }, onError: (_) {});
  }

  final String teamId;

  /// Null when creating a new play.
  final String? playId;
  final PlayRepository _plays;
  final AuthRepository _auth;
  late final StreamSubscription<Team?> _teamSub;
  static const _uuid = Uuid();
  static const _maxHistory = 100;

  late final Command0<void> load;

  /// Result value is the saved play id.
  late final Command0<String> save;

  Team? _team;

  Play _play = const Play(id: '', name: 'New play');
  Play get play => _play;

  EditorTool _tool = EditorTool.select;
  EditorTool get tool => _tool;

  String? _selectedId;
  String? get selectedId => _selectedId;

  /// 0 shows the setup; k shows the end of step k with its movement trails.
  int _step = 0;
  int get step => _step;
  int get stepCount => _play.steps.length;
  bool get editingSetup => _step == 0;

  /// Element being recorded by the current drag in a step view.
  String? _recording;

  static const maxSteps = 30;
  static const _maxPathPoints = 48;

  bool _dirty = false;
  bool get dirty => _dirty;

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  String get _uid => _auth.currentUser?.uid ?? '';
  bool get canEdit => _team?.canEdit(_uid) ?? false;

  Future<Result<void>> _load() async {
    final id = playId;
    if (id == null) return const Result.ok(null);
    final result = await _plays.getPlay(teamId, id);
    if (result case Ok(:final value)) {
      _play = value;
      notifyListeners();
    }
    return result;
  }

  Future<Result<String>> _save() async {
    final result = await _plays.savePlay(teamId, _play, _uid);
    if (result case Ok(:final value)) {
      _play = _play.copyWith(id: value);
      _dirty = false;
      notifyListeners();
    }
    return result;
  }

  // ---- Metadata --------------------------------------------------------

  void setName(String name) {
    if (name == _play.name) return;
    _play = _play.copyWith(name: name);
    _markDirty();
  }

  void setCategory(PlayCategory category) {
    _play = _play.copyWith(category: category);
    _markDirty();
  }

  void setNotes(String notes) {
    if (notes == _play.notes) return;
    _play = _play.copyWith(notes: notes);
    _markDirty();
  }

  // ---- Tools & selection ----------------------------------------------

  void setTool(EditorTool tool) {
    _tool = tool;
    if (tool != EditorTool.select) _selectedId = null;
    notifyListeners();
  }

  void select(String? id) {
    _selectedId = id;
    notifyListeners();
  }

  // ---- Diagram edits ---------------------------------------------------

  /// Places an element for the active placement tool at [at].
  void placeAt(FieldPoint at) {
    final kind = switch (_tool) {
      EditorTool.offense => ElementKind.offense,
      EditorTool.defense => ElementKind.defense,
      EditorTool.disc => ElementKind.disc,
      EditorTool.cone => ElementKind.cone,
      _ => null,
    };
    if (kind == null || !editingSetup) return;
    _pushHistory();
    _play = _play.copyWith(
      elements: [
        ..._play.elements,
        PlayElement(
          id: _uuid.v4(),
          kind: kind,
          position: _clamp(at),
          label: _nextLabel(kind),
        ),
      ],
    );
    _markDirty();
  }

  String _nextLabel(ElementKind kind) {
    if (kind != ElementKind.offense && kind != ElementKind.defense) return '';
    final used = _play.elements
        .where((e) => e.kind == kind)
        .map((e) => int.tryParse(e.label))
        .whereType<int>()
        .toSet();
    var n = 1;
    while (used.contains(n)) {
      n++;
    }
    return '$n';
  }

  /// Call once when a drag of [id] starts so the whole drag is one undo
  /// step. In a step view the drag records [id]'s movement for that step,
  /// extending any path it already has.
  void beginMove(String id) {
    _pushHistory();
    _recording = editingSetup ? null : id;
  }

  void moveElement(String id, FieldPoint to) {
    if (!editingSetup) {
      _recordPoint(id, _clamp(to));
      return;
    }
    _play = _play.copyWith(
      elements: [
        for (final e in _play.elements)
          e.id == id ? e.copyWith(position: _clamp(to)) : e,
      ],
    );
    _markDirty();
  }

  /// Adds an arrow for the active cut/throw tool. Ignores tiny drags.
  void addArrow(List<FieldPoint> points) {
    final kind = switch (_tool) {
      EditorTool.cut => ArrowKind.cut,
      EditorTool.throw_ => ArrowKind.throw_,
      _ => null,
    };
    if (kind == null || points.length < 2 || !editingSetup) return;
    final first = points.first, last = points.last;
    final dx = first.x - last.x, dy = first.y - last.y;
    if (dx * dx + dy * dy < 0.0004) return;
    // Throws are drawn straight; cuts keep their path.
    final path = kind == ArrowKind.throw_ ? [first, last] : points;
    _pushHistory();
    _play = _play.copyWith(
      arrows: [
        ..._play.arrows,
        PlayArrow(
          id: _uuid.v4(),
          kind: kind,
          points: [for (final p in path) _clamp(p)],
        ),
      ],
    );
    _markDirty();
  }

  void _recordPoint(String id, FieldPoint p) {
    if (_recording != id) return;
    final index = _step - 1;
    final st = _play.steps[index];
    final isDisc = _play.elements.any(
      (e) => e.id == id && e.kind == ElementKind.disc,
    );
    var path = [...?st.paths[id]];
    if (isDisc) {
      // Throws fly straight to wherever the disc is dropped.
      path = [p];
    } else {
      final prev = path.length >= 2
          ? path[path.length - 2]
          : _play.positionsAfter(index)[id] ?? p;
      final dx = p.x - prev.x, dy = p.y - prev.y;
      // Move the tip until the drag goes far enough for a new waypoint, so
      // paths stay light but always end exactly under the finger.
      if (path.isNotEmpty && dx * dx + dy * dy < 0.0004) {
        path[path.length - 1] = p;
      } else {
        path.add(p);
      }
      if (path.length > _maxPathPoints) {
        path = [
          for (var i = 0; i < path.length; i++)
            if (i.isEven || i == path.length - 1) path[i],
        ];
      }
    }
    _setStep(index, st.copyWith(paths: {...st.paths, id: path}));
  }

  void deleteItem(String id) {
    if (!editingSetup) {
      clearMovement(id);
      return;
    }
    final hasElement = _play.elements.any((e) => e.id == id);
    final hasArrow = _play.arrows.any((a) => a.id == id);
    if (!hasElement && !hasArrow) return;
    _pushHistory();
    _play = _play.copyWith(
      elements: _play.elements.where((e) => e.id != id).toList(),
      arrows: _play.arrows.where((a) => a.id != id).toList(),
      steps: [
        for (final st in _play.steps)
          st.copyWith(paths: {...st.paths}..remove(id)),
      ],
    );
    if (_selectedId == id) _selectedId = null;
    _markDirty();
  }

  // ---- Animation steps -------------------------------------------------

  void selectStep(int step) {
    if (step < 0 || step > stepCount) return;
    _step = step;
    _selectedId = null;
    if (step > 0) _tool = _stepTool(_tool);
    notifyListeners();
  }

  /// Only moving and erasing make sense once the setup is done.
  static EditorTool _stepTool(EditorTool t) =>
      t == EditorTool.erase ? t : EditorTool.select;

  /// Appends an empty step and shows it, ready for recording.
  void addStep() {
    if (stepCount >= maxSteps) return;
    _pushHistory();
    _play = _play.copyWith(
      steps: [
        ..._play.steps,
        PlayStep(id: _uuid.v4()),
      ],
    );
    _step = stepCount;
    _selectedId = null;
    _tool = _stepTool(_tool);
    _markDirty();
  }

  /// Removes step [step] (1-based); later steps start from wherever the
  /// remaining steps leave each element.
  void deleteStep(int step) {
    if (step < 1 || step > stepCount) return;
    _pushHistory();
    _play = _play.copyWith(steps: [..._play.steps]..removeAt(step - 1));
    _step = _step.clamp(0, stepCount);
    _selectedId = null;
    _markDirty();
  }

  void setStepNote(String note) {
    if (editingSetup) return;
    final st = _play.steps[_step - 1];
    if (st.note == note) return;
    _setStep(_step - 1, st.copyWith(note: note));
  }

  /// Removes [id]'s movement in the current step.
  void clearMovement(String id) {
    if (editingSetup) return;
    final st = _play.steps[_step - 1];
    if (!st.paths.containsKey(id)) return;
    _pushHistory();
    _setStep(_step - 1, st.copyWith(paths: {...st.paths}..remove(id)));
  }

  void _setStep(int index, PlayStep st) {
    _play = _play.copyWith(
      steps: [
        for (var i = 0; i < _play.steps.length; i++)
          i == index ? st : _play.steps[i],
      ],
    );
    _markDirty();
  }

  /// Whether [id] moves in the current step.
  bool movesInStep(String? id) =>
      !editingSetup && _play.steps[_step - 1].paths.containsKey(id);

  /// Caption of the current step.
  String get stepNote => editingSetup ? '' : _play.steps[_step - 1].note;

  /// The diagram as shown for the current step: elements where the step
  /// leaves them, static arrows only in the setup.
  Play get displayed => frameAt(_step.toDouble());

  /// Animation frame at time [t] (see [Play.positionsAt]).
  Play frameAt(double t) => _play.copyWith(
    elements: _play.elementsAt(t),
    arrows: t == 0 ? _play.arrows : const [],
  );

  /// Movement paths of steps[index] (0-based).
  List<Trail> trailsFor(int index) {
    if (index < 0 || index >= stepCount) return const [];
    final kinds = {for (final e in _play.elements) e.id: e.kind};
    return [
      for (final id in _play.steps[index].paths.keys)
        if (kinds[id] case final kind?)
          (kind: kind, points: _play.pathIn(index, id)),
    ];
  }

  /// Trails for the current step view.
  List<Trail> get trails => trailsFor(_step - 1);

  /// Where the elements that move in the current step started.
  List<PlayElement> get ghosts {
    if (editingSetup) return const [];
    final index = _step - 1;
    final start = _play.positionsAfter(index);
    final moving = _play.steps[index].paths.keys.toSet();
    return [
      for (final e in _play.elements)
        if (moving.contains(e.id)) e.copyWith(position: start[e.id]),
    ];
  }

  void deleteSelected() {
    final id = _selectedId;
    if (id != null) deleteItem(id);
  }

  void clearDiagram() {
    if (_play.elements.isEmpty && _play.arrows.isEmpty) return;
    _pushHistory();
    _play = _play.copyWith(
      elements: const [],
      arrows: const [],
      steps: const [],
    );
    _selectedId = null;
    _step = 0;
    _markDirty();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  }

  _Snapshot _snapshot() =>
      (elements: _play.elements, arrows: _play.arrows, steps: _play.steps);

  void _pushHistory() {
    _undo.add(_snapshot());
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(_Snapshot s) {
    _play = _play.copyWith(
      elements: s.elements,
      arrows: s.arrows,
      steps: s.steps,
    );
    _selectedId = null;
    _step = _step.clamp(0, stepCount);
    _markDirty();
  }

  void _markDirty() {
    _dirty = true;
    notifyListeners();
  }

  static FieldPoint _clamp(FieldPoint p) =>
      FieldPoint(p.x.clamp(0.0, 1.0), p.y.clamp(0.0, 1.0));

  @override
  void dispose() {
    _teamSub.cancel();
    super.dispose();
  }
}
