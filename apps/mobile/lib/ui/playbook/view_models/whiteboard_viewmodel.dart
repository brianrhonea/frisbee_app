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

enum WhiteboardTool { move, pen, offense, defense, disc, cone, erase }

typedef _Snapshot = ({List<PlayDrawing> strokes, List<PlayElement> tokens});

/// What "Save as play" asks for.
typedef PlayDetails = ({String name, PlayCategory category});

/// The playbook's whiteboard: freehand pen strokes plus pieces to drop and
/// drag, for chalk talks. Anyone who can see the playbook can sketch; only
/// those who can edit plays can save, as a new play or as a saved
/// whiteboard (a [Play] of kind [PlayKind.whiteboard], no steps).
class WhiteboardViewModel extends ChangeNotifier {
  WhiteboardViewModel({
    required this.teamId,
    required this.playId,
    required PlayRepository playRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _plays = playRepository,
       _auth = authRepository {
    load = Command0<void>(_load)..execute();
    saveAsPlay = Command1<String, PlayDetails>(_saveAsPlay);
    saveWhiteboard = Command1<String, String>(_saveWhiteboard);
    _teamSub = teamRepository.watchTeam(teamId).listen((t) {
      _team = t;
      notifyListeners();
    }, onError: (_) {});
  }

  final String teamId;

  /// The saved whiteboard opened, or null for a blank one.
  final String? playId;
  final PlayRepository _plays;
  final AuthRepository _auth;
  late final StreamSubscription<Team?> _teamSub;
  static const _uuid = Uuid();
  static const _maxHistory = 100;

  late final Command0<void> load;

  /// Saves the sketch as a new play (its pieces as the setup, the strokes
  /// kept). Result value is the new play's id.
  late final Command1<String, PlayDetails> saveAsPlay;

  /// Saves the sketch as a whiteboard, updating the one opened or saved
  /// before. Result value is its id.
  late final Command1<String, String> saveWhiteboard;

  Team? _team;

  /// Id of this sketch's saved whiteboard, once there is one.
  String? _savedId;
  String? get savedId => _savedId;

  String _name = '';

  /// The saved whiteboard's name; empty until saved.
  String get name => _name;

  List<PlayDrawing> _strokes = const [];
  List<PlayDrawing> get strokes => _strokes;

  List<PlayElement> _tokens = const [];
  List<PlayElement> get tokens => _tokens;

  WhiteboardTool _tool = WhiteboardTool.pen;
  WhiteboardTool get tool => _tool;

  DrawingColor _color = DrawingColor.white;
  DrawingColor get color => _color;

  bool _dirty = false;

  /// Changed since it was opened or last saved.
  bool get dirty => _dirty;

  bool get isEmpty => _strokes.isEmpty && _tokens.isEmpty;

  /// Whether leaving should ask "Discard sketch?": changes not saved, and
  /// not a blank board that was drawn on and then cleared.
  bool get hasUnsaved => _dirty && !(_savedId == null && isEmpty);

  final List<_Snapshot> _undo = [];
  bool get canUndo => _undo.isNotEmpty;

  String get _uid => _auth.currentUser?.uid ?? '';

  /// Whether the user may save (the same permission as editing plays).
  bool get canSave => _team?.canEdit(_uid) ?? false;

  bool get strokesFull => _strokes.length >= Play.maxDrawings;
  bool get tokensFull => _tokens.length >= Play.maxElements;

  /// The board as a diagram, for painting and hit tests.
  Play get board => Play(
    id: _savedId ?? '',
    name: _name,
    kind: PlayKind.whiteboard,
    elements: _tokens,
    drawings: _strokes,
  );

  Future<Result<void>> _load() async {
    final id = playId;
    if (id == null) return const Result.ok(null);
    final result = await _plays.getPlay(teamId, id);
    if (result case Ok(:final value)) {
      // Only a whiteboard is saved back over; anything else opened here is
      // a starting sketch, so a save never overwrites a play's steps.
      if (value.isWhiteboard) {
        _savedId = value.id;
        _name = value.name;
      }
      _strokes = value.drawings;
      _tokens = value.elements;
      notifyListeners();
    }
    return result;
  }

  /// The sketch as a play to save: the pieces where they stand (the setup,
  /// step 0) and the pen strokes, with no steps or arrows. A whiteboard
  /// keeps the saved one's id so saving updates it; a play is always new.
  Play toPlay({
    required PlayKind kind,
    required String name,
    PlayCategory category = PlayCategory.offense,
  }) => Play(
    id: kind == PlayKind.whiteboard ? (_savedId ?? '') : '',
    name: name,
    kind: kind,
    category: category,
    elements: _tokens,
    drawings: _strokes,
  );

  Future<Result<String>> _saveAsPlay(PlayDetails d) async {
    final play = toPlay(
      kind: PlayKind.play,
      name: d.name.trim(),
      category: d.category,
    );
    final result = await _plays.savePlay(teamId, play, _uid);
    if (result is Ok<String>) {
      _dirty = false;
      notifyListeners();
    }
    return result;
  }

  Future<Result<String>> _saveWhiteboard(String name) async {
    final trimmed = name.trim();
    final result = await _plays.savePlay(
      teamId,
      toPlay(kind: PlayKind.whiteboard, name: trimmed),
      _uid,
    );
    if (result case Ok(:final value)) {
      _savedId = value;
      _name = trimmed;
      _dirty = false;
      notifyListeners();
    }
    return result;
  }

  // ---- Tools -----------------------------------------------------------

  void setTool(WhiteboardTool tool) {
    _tool = tool;
    notifyListeners();
  }

  /// Picks a pen colour, and the pen with it.
  void setColor(DrawingColor color) {
    _color = color;
    _tool = WhiteboardTool.pen;
    notifyListeners();
  }

  // ---- Edits -----------------------------------------------------------

  /// Adds a pen stroke in the current colour. Ignores dots and tiny
  /// scribbles; thins long strokes to [Play.maxDrawingPoints].
  void addStroke(List<FieldPoint> points) {
    if (points.length < 2 || strokesFull) return;
    var len = 0.0;
    for (var i = 1; i < points.length; i++) {
      final dx = points[i].x - points[i - 1].x;
      final dy = points[i].y - points[i - 1].y;
      len += dx * dx + dy * dy;
    }
    if (len < 0.00005) return;
    var pts = [for (final p in points) _clamp(p)];
    while (pts.length > Play.maxDrawingPoints) {
      pts = [
        for (var i = 0; i < pts.length; i++)
          if (i.isEven || i == pts.length - 1) pts[i],
      ];
    }
    _pushHistory();
    _strokes = [
      ..._strokes,
      PlayDrawing(id: _uuid.v4(), color: _color, points: pts),
    ];
    _markDirty();
  }

  /// Drops a piece for the active piece tool at [at].
  void placeAt(FieldPoint at) {
    final kind = switch (_tool) {
      WhiteboardTool.offense => ElementKind.offense,
      WhiteboardTool.defense => ElementKind.defense,
      WhiteboardTool.disc => ElementKind.disc,
      WhiteboardTool.cone => ElementKind.cone,
      _ => null,
    };
    if (kind == null || tokensFull) return;
    _pushHistory();
    _tokens = [
      ..._tokens,
      PlayElement(
        id: _uuid.v4(),
        kind: kind,
        position: _clamp(at),
        label: _nextLabel(kind),
      ),
    ];
    _markDirty();
  }

  String _nextLabel(ElementKind kind) {
    if (kind != ElementKind.offense && kind != ElementKind.defense) return '';
    final used = _tokens
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

  /// Call once when a drag of [id] starts, so the drag is one undo step.
  void beginMove(String id) {
    if (!_tokens.any((e) => e.id == id)) return;
    _pushHistory();
  }

  void moveToken(String id, FieldPoint to) {
    _tokens = [
      for (final e in _tokens)
        e.id == id ? e.copyWith(position: _clamp(to)) : e,
    ];
    _markDirty();
  }

  /// Removes the stroke or piece [id].
  void erase(String id) {
    final stroke = _strokes.any((d) => d.id == id);
    final token = _tokens.any((e) => e.id == id);
    if (!stroke && !token) return;
    _pushHistory();
    _strokes = [
      for (final d in _strokes)
        if (d.id != id) d,
    ];
    _tokens = [
      for (final e in _tokens)
        if (e.id != id) e,
    ];
    _markDirty();
  }

  /// Wipes the board (undoable).
  void clear() {
    if (isEmpty) return;
    _pushHistory();
    _strokes = const [];
    _tokens = const [];
    _markDirty();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    _strokes = s.strokes;
    _tokens = s.tokens;
    _markDirty();
  }

  void _pushHistory() {
    _undo.add((strokes: _strokes, tokens: _tokens));
    if (_undo.length > _maxHistory) _undo.removeAt(0);
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
