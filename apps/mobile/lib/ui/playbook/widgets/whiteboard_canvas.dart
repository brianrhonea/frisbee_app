import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/play.dart';
import '../view_models/whiteboard_viewmodel.dart';
import 'field_geometry.dart';
import 'field_painter.dart';
import 'play_canvas.dart';
import '../../core/themes/theme.dart';

/// The whiteboard's field: the pen draws, piece tools drop and drag pieces,
/// the eraser removes what it touches. Bound to a [WhiteboardViewModel].
class WhiteboardCanvas extends StatefulWidget {
  const WhiteboardCanvas({super.key, required this.viewModel});

  final WhiteboardViewModel viewModel;

  @override
  State<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends State<WhiteboardCanvas> {
  // Ephemeral gesture state; committed to the ViewModel on gesture end.
  String? _dragging;
  List<FieldPoint> _draft = const [];
  bool _erasing = false;

  /// Whether the current eraser drag removed a stroke.
  bool _erased = false;

  Offset? _panFrom;
  double _panDistance = 0;

  /// As on the play editor's canvas: drags start after this much movement.
  static const _dragSlop = 4.0;

  WhiteboardViewModel get vm => widget.viewModel;

  bool get _pen => vm.tool == WhiteboardTool.pen;

  void _onTap(FieldGeometry g, Offset local) {
    switch (vm.tool) {
      case WhiteboardTool.erase:
        if (g.hitTest(vm.board, local) case final id?) vm.erase(id);
      case WhiteboardTool.move || WhiteboardTool.pen:
        break;
      case _:
        vm.placeAt(g.toField(local));
    }
  }

  void _onPanStart(FieldGeometry g, Offset local) {
    _panFrom = local;
    _panDistance = 0;
    if (_pen) {
      setState(() => _draft = [g.toField(local)]);
      return;
    }
    if (vm.tool == WhiteboardTool.erase) {
      _erasing = true;
      _erased = false;
      _eraseAt(g, local);
      return;
    }
    // Move and the piece tools pick up a piece under the finger.
    if (g.hitElement(vm.board, local) case final id?) {
      _dragging = id;
      vm.beginMove(id);
    }
  }

  void _onPanUpdate(FieldGeometry g, Offset local) {
    if (_panFrom case final from?) _panDistance = (local - from).distance;
    final p = g.toField(local);
    if (_pen && _draft.isNotEmpty) {
      final last = _draft.last;
      final dx = p.x - last.x, dy = p.y - last.y;
      if (dx * dx + dy * dy > 0.0001) setState(() => _draft = [..._draft, p]);
    } else if (_erasing) {
      _eraseAt(g, local);
    } else if (_dragging case final id?) {
      vm.moveToken(id, p);
    }
  }

  /// A drag with the eraser wipes the strokes it crosses.
  void _eraseAt(FieldGeometry g, Offset local) {
    if (g.hitDrawing(vm.board, local) case final id?) {
      vm.erase(id);
      _erased = true;
    }
  }

  void _onPanEnd(FieldGeometry g) {
    if (_pen && _draft.length > 1) vm.addStroke(_draft);
    // A shaky tap that became a pan, didn't grab anything and barely moved
    // counts as the tap (drops a piece, or erases one).
    final from = _panFrom;
    if (!_pen &&
        _dragging == null &&
        from != null &&
        _panDistance < kTouchSlop &&
        !_erased) {
      _onTap(g, from);
    }
    setState(() {
      _draft = const [];
      _dragging = null;
      _erasing = false;
      _erased = false;
      _panFrom = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FieldFrame(
      builder: (size, horizontal) {
        final g = FieldGeometry(size, horizontal: horizontal);
        return ListenableBuilder(
          listenable: vm,
          builder: (context, _) => MouseRegion(
            cursor: vm.tool == WhiteboardTool.move
                ? SystemMouseCursors.basic
                : SystemMouseCursors.precise,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                gestureSettings: const DeviceGestureSettings(
                  touchSlop: _dragSlop / 2,
                ),
              ),
              child: GestureDetector(
                dragStartBehavior: DragStartBehavior.down,
                onTapUp: (d) => _onTap(g, d.localPosition),
                onPanStart: (d) => _onPanStart(g, d.localPosition),
                onPanUpdate: (d) => _onPanUpdate(g, d.localPosition),
                onPanEnd: (_) => _onPanEnd(g),
                onPanCancel: () => _onPanEnd(g),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  child: CustomPaint(
                    size: size,
                    painter: FieldPainter(
                      play: vm.board,
                      horizontal: horizontal,
                      draftStroke: _draft,
                      draftColor: vm.color,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
