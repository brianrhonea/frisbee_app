import 'package:flutter/material.dart';

import '../../../domain/models/play.dart';
import '../view_models/play_editor_viewmodel.dart';
import 'field_geometry.dart';
import 'field_painter.dart';

/// Field sized to fit its constraints at the correct aspect ratio, rotated to
/// landscape when there is more horizontal room.
class _FieldFrame extends StatelessWidget {
  const _FieldFrame({required this.builder});

  final Widget Function(Size size, bool horizontal) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final horizontal = c.maxWidth > c.maxHeight;
      // Long side / short side of the field.
      const ratio = 1 / FieldGeometry.aspect;
      final Size size;
      if (horizontal) {
        final w = c.maxWidth.clamp(0.0, c.maxHeight * ratio);
        size = Size(w, w / ratio);
      } else {
        final h = c.maxHeight.clamp(0.0, c.maxWidth * ratio);
        size = Size(h / ratio, h);
      }
      return Center(
        child: SizedBox.fromSize(size: size, child: builder(size, horizontal)),
      );
    },
  );
}

/// Read-only diagram, used for thumbnails and player view.
class PlayDiagram extends StatelessWidget {
  const PlayDiagram({super.key, required this.play});

  final Play play;

  @override
  Widget build(BuildContext context) => _FieldFrame(
    builder: (size, horizontal) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        size: size,
        painter: FieldPainter(play: play, horizontal: horizontal),
      ),
    ),
  );
}

/// Interactive diagram bound to a [PlayEditorViewModel].
class PlayCanvas extends StatefulWidget {
  const PlayCanvas({super.key, required this.viewModel});

  final PlayEditorViewModel viewModel;

  @override
  State<PlayCanvas> createState() => _PlayCanvasState();
}

class _PlayCanvasState extends State<PlayCanvas> {
  // Ephemeral gesture state; committed to the ViewModel on gesture end.
  String? _dragging;
  List<FieldPoint> _draft = const [];

  PlayEditorViewModel get vm => widget.viewModel;

  bool get _drawing =>
      vm.tool == EditorTool.cut || vm.tool == EditorTool.throw_;

  void _onTap(FieldGeometry g, Offset local) {
    final hit = g.hitTest(vm.play, local);
    switch (vm.tool) {
      case EditorTool.select:
        vm.select(hit);
      case EditorTool.erase:
        if (hit != null) vm.deleteItem(hit);
      case EditorTool.cut || EditorTool.throw_:
        break;
      case _:
        vm.placeAt(g.toField(local));
    }
  }

  void _onPanStart(FieldGeometry g, Offset local) {
    if (_drawing) {
      setState(() => _draft = [g.toField(local)]);
      return;
    }
    if (vm.tool == EditorTool.erase) return;
    final hit = g.hitTest(vm.play, local);
    if (hit != null && vm.play.elements.any((e) => e.id == hit)) {
      _dragging = hit;
      vm.beginMove();
      if (vm.tool == EditorTool.select) vm.select(hit);
    }
  }

  void _onPanUpdate(FieldGeometry g, Offset local) {
    final p = g.toField(local);
    if (_drawing && _draft.isNotEmpty) {
      final last = _draft.last;
      final dx = p.x - last.x, dy = p.y - last.y;
      if (dx * dx + dy * dy > 0.0002) setState(() => _draft = [..._draft, p]);
    } else if (_dragging != null) {
      vm.moveElement(_dragging!, p);
    }
  }

  void _onPanEnd() {
    if (_drawing && _draft.isNotEmpty) vm.addArrow(_draft);
    setState(() {
      _draft = const [];
      _dragging = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _FieldFrame(
      builder: (size, horizontal) {
        final g = FieldGeometry(size, horizontal: horizontal);
        return ListenableBuilder(
          listenable: vm,
          builder: (context, _) => MouseRegion(
            cursor: vm.tool == EditorTool.select
                ? SystemMouseCursors.basic
                : SystemMouseCursors.precise,
            child: GestureDetector(
              onTapUp: (d) => _onTap(g, d.localPosition),
              onPanStart: (d) => _onPanStart(g, d.localPosition),
              onPanUpdate: (d) => _onPanUpdate(g, d.localPosition),
              onPanEnd: (_) => _onPanEnd(),
              onPanCancel: _onPanEnd,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  size: size,
                  painter: FieldPainter(
                    play: vm.play,
                    horizontal: horizontal,
                    selectedId: vm.selectedId,
                    draft: _draft,
                    draftKind: switch (vm.tool) {
                      EditorTool.cut => ArrowKind.cut,
                      EditorTool.throw_ => ArrowKind.throw_,
                      _ => null,
                    },
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
