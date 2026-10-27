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

typedef _Snapshot = ({List<PlayElement> elements, List<PlayArrow> arrows});

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
    if (kind == null) return;
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

  /// Call once when a drag starts so the whole drag is one undo step.
  void beginMove() => _pushHistory();

  void moveElement(String id, FieldPoint to) {
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
    if (kind == null || points.length < 2) return;
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

  void deleteItem(String id) {
    final hasElement = _play.elements.any((e) => e.id == id);
    final hasArrow = _play.arrows.any((a) => a.id == id);
    if (!hasElement && !hasArrow) return;
    _pushHistory();
    _play = _play.copyWith(
      elements: _play.elements.where((e) => e.id != id).toList(),
      arrows: _play.arrows.where((a) => a.id != id).toList(),
    );
    if (_selectedId == id) _selectedId = null;
    _markDirty();
  }

  void deleteSelected() {
    final id = _selectedId;
    if (id != null) deleteItem(id);
  }

  void clearDiagram() {
    if (_play.elements.isEmpty && _play.arrows.isEmpty) return;
    _pushHistory();
    _play = _play.copyWith(elements: const [], arrows: const []);
    _selectedId = null;
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

  _Snapshot _snapshot() => (elements: _play.elements, arrows: _play.arrows);

  void _pushHistory() {
    _undo.add(_snapshot());
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(_Snapshot s) {
    _play = _play.copyWith(elements: s.elements, arrows: s.arrows);
    _selectedId = null;
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
