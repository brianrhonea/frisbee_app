import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/play.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/play_editor_viewmodel.dart';
import 'play_canvas.dart';

class PlayEditorScreen extends StatefulWidget {
  const PlayEditorScreen({super.key, required this.viewModel});

  final PlayEditorViewModel viewModel;

  @override
  State<PlayEditorScreen> createState() => _PlayEditorScreenState();
}

class _PlayEditorScreenState extends State<PlayEditorScreen>
    with SingleTickerProviderStateMixin {
  PlayEditorViewModel get vm => widget.viewModel;

  static const _stepDuration = Duration(milliseconds: 1400);

  // Playback is view state: the controller's value maps onto the play's
  // timeline (0 = setup, 1 = end of the last step).
  late final AnimationController _anim = AnimationController(vsync: this);

  /// True while showing a playback frame instead of the selected step.
  bool _timeline = false;
  double _speed = 1;

  double get _t => _anim.value * vm.stepCount;

  @override
  void initState() {
    super.initState();
    vm.save.addListener(_onSave);
  }

  @override
  void dispose() {
    vm.save.removeListener(_onSave);
    _anim.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final n = vm.stepCount;
    if (n == 0) return;
    if (_anim.isAnimating) {
      _anim.stop();
      setState(() {});
      return;
    }
    // Resume a paused frame, otherwise play from the selected step.
    var from = _timeline
        ? _t
        : (vm.step == 0 || vm.step == n ? 0.0 : vm.step - 1.0);
    if (from >= n) from = 0;
    _anim
      ..duration = _stepDuration * (n / _speed)
      ..value = from / n;
    setState(() => _timeline = true);
    _anim.forward().whenCompleteOrCancel(() {
      if (!mounted || _anim.value < 1) return;
      vm.selectStep(n);
      setState(() => _timeline = false);
    });
  }

  void _scrub(double t) {
    _anim.stop();
    _anim.value = t / vm.stepCount;
    setState(() => _timeline = true);
  }

  void _setSpeed(double speed) {
    final playing = _anim.isAnimating;
    _anim.stop();
    setState(() => _speed = speed);
    if (playing) _togglePlay();
  }

  /// Leaves playback and shows [step] for editing.
  void _showStep(int step) {
    _anim.stop();
    setState(() => _timeline = false);
    vm.selectStep(step);
  }

  void _addStep() {
    _anim.stop();
    setState(() => _timeline = false);
    vm.addStep();
  }

  void _onSave() {
    final cmd = vm.save;
    switch (cmd.result) {
      case Ok<String>(:final value):
        cmd.clearResult();
        showSnackBar(context, 'Play saved');
        // Swap /plays/new for the real id so refresh/back work as expected.
        if (vm.playId == null) {
          context.replace(Routes.play(vm.teamId, value));
        }
      case Error<String>():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  Future<void> _editDetails() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PlayDetailsDialog(viewModel: vm),
    );
  }

  Future<bool> _confirmDiscard() => confirmDialog(
    context,
    title: 'Discard changes?',
    message: 'You have unsaved changes to this play.',
    confirmLabel: 'Discard',
    destructive: true,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([vm, vm.load, vm.save]),
      builder: (context, _) {
        if (vm.load.running) {
          return Scaffold(appBar: AppBar(), body: const LoadingView());
        }
        if (vm.load.error) {
          return Scaffold(
            appBar: AppBar(),
            body: ErrorView(error: vm.load.result, onRetry: vm.load.execute),
          );
        }
        final editable = vm.canEdit;
        return PopScope(
          canPop: !vm.dirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (await _confirmDiscard() && context.mounted) {
              context.go(Routes.team(vm.teamId));
            }
          },
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                  _UndoIntent(),
              SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                  _UndoIntent(),
              SingleActivator(LogicalKeyboardKey.keyY, control: true):
                  _RedoIntent(),
              SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
                  _RedoIntent(),
              SingleActivator(LogicalKeyboardKey.delete): _DeleteIntent(),
              SingleActivator(LogicalKeyboardKey.backspace): _DeleteIntent(),
            },
            child: Actions(
              actions: {
                _UndoIntent: _DiagramAction<_UndoIntent>(vm.undo),
                _RedoIntent: _DiagramAction<_RedoIntent>(vm.redo),
                _DeleteIntent: _DiagramAction<_DeleteIntent>(vm.deleteSelected),
              },
              child: Focus(
                autofocus: true,
                child: Scaffold(
                  appBar: AppBar(
                    title: GestureDetector(
                      onTap: editable ? _editDetails : null,
                      child: Text(
                        vm.play.name.isEmpty ? 'Untitled play' : vm.play.name,
                      ),
                    ),
                    actions: [
                      IconButton(
                        tooltip: editable ? 'Details' : 'Notes',
                        icon: const Icon(Icons.notes),
                        onPressed: editable
                            ? _editDetails
                            : () => showDialog<void>(
                                context: context,
                                builder: (_) => _NotesDialog(play: vm.play),
                              ),
                      ),
                      if (editable) ...[
                        IconButton(
                          tooltip: 'Undo',
                          icon: const Icon(Icons.undo),
                          onPressed: vm.canUndo ? vm.undo : null,
                        ),
                        IconButton(
                          tooltip: 'Redo',
                          icon: const Icon(Icons.redo),
                          onPressed: vm.canRedo ? vm.redo : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: FilledButton.icon(
                            onPressed: vm.save.running || !vm.dirty
                                ? null
                                : vm.save.execute,
                            icon: vm.save.running
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('Save'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  body: SafeArea(
                    child: Column(
                      children: [
                        if (editable && !_timeline) _Toolbar(viewModel: vm),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _timeline
                                ? AnimatedBuilder(
                                    animation: _anim,
                                    builder: (context, _) => PlayDiagram(
                                      play: vm.frameAt(_t),
                                      trails: vm.trailsFor(
                                        _t.floor().clamp(0, vm.stepCount - 1),
                                      ),
                                    ),
                                  )
                                : editable
                                ? PlayCanvas(viewModel: vm)
                                : PlayDiagram(
                                    play: vm.displayed,
                                    trails: vm.trails,
                                    ghosts: vm.ghosts,
                                  ),
                          ),
                        ),
                        if (editable || vm.stepCount > 0)
                          AnimatedBuilder(
                            animation: _anim,
                            builder: (context, _) => _Timeline(
                              viewModel: vm,
                              editable: editable,
                              playing: _anim.isAnimating,
                              time: _timeline ? _t : null,
                              speed: _speed,
                              onPlay: _togglePlay,
                              onScrub: _scrub,
                              onSpeed: _setSpeed,
                              onStep: _showStep,
                              onAddStep: _addStep,
                            ),
                          ),
                      ],
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

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

/// Diagram shortcut that stands aside while a text field has focus, so
/// typing a step caption doesn't delete players or undo the diagram.
class _DiagramAction<T extends Intent> extends Action<T> {
  _DiagramAction(this._callback);

  final VoidCallback _callback;

  @override
  bool isEnabled(T intent) =>
      FocusManager.instance.primaryFocus?.context?.widget is! EditableText;

  @override
  Object? invoke(T intent) {
    _callback();
    return null;
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.viewModel});

  final PlayEditorViewModel viewModel;

  static const _tools = [
    (EditorTool.select, Icons.near_me_outlined, 'Select / move'),
    (EditorTool.offense, Icons.circle, 'Offense player'),
    (EditorTool.defense, Icons.circle, 'Defense player'),
    (EditorTool.disc, Icons.album_outlined, 'Disc'),
    (EditorTool.cone, Icons.change_history, 'Cone'),
    (EditorTool.cut, Icons.trending_up, 'Draw cut'),
    (EditorTool.throw_, Icons.more_horiz, 'Draw throw'),
    (EditorTool.erase, Icons.auto_fix_normal_outlined, 'Erase'),
  ];

  Color? _iconColor(EditorTool t) => switch (t) {
    EditorTool.offense => Colors.blue,
    EditorTool.defense => Colors.red,
    EditorTool.cone => Colors.orange,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    if (!vm.editingSetup) return _StepToolbar(viewModel: vm);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            for (final (tool, icon, label) in _tools)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: IconButton(
                  tooltip: label,
                  isSelected: vm.tool == tool,
                  style: IconButton.styleFrom(
                    backgroundColor: vm.tool == tool
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : null,
                  ),
                  icon: Icon(icon, color: _iconColor(tool)),
                  onPressed: () => vm.setTool(tool),
                ),
              ),
            const SizedBox(height: 32, child: VerticalDivider()),
            IconButton(
              tooltip: 'Delete selected',
              icon: const Icon(Icons.delete_outline),
              onPressed: vm.selectedId == null ? null : vm.deleteSelected,
            ),
            IconButton(
              tooltip: 'Clear field',
              icon: const Icon(Icons.layers_clear_outlined),
              onPressed: vm.play.elements.isEmpty && vm.play.arrows.isEmpty
                  ? null
                  : vm.clearDiagram,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tools while recording a step: drag to move, erase to undo a movement.
class _StepToolbar extends StatelessWidget {
  const _StepToolbar({required this.viewModel});

  final PlayEditorViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final selected = vm.selectedId;
    Widget tool(EditorTool t, IconData icon, String label) => IconButton(
      tooltip: label,
      isSelected: vm.tool == t,
      style: IconButton.styleFrom(
        backgroundColor: vm.tool == t
            ? theme.colorScheme.secondaryContainer
            : null,
      ),
      icon: Icon(icon),
      onPressed: () => vm.setTool(t),
    );
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            tool(EditorTool.select, Icons.open_with, 'Record movement'),
            tool(
              EditorTool.erase,
              Icons.auto_fix_normal_outlined,
              'Erase movement',
            ),
            if (vm.movesInStep(selected))
              TextButton.icon(
                onPressed: () => vm.clearMovement(selected!),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset move'),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                vm.tool == EditorTool.erase
                    ? 'Tap a player to remove their movement in this step.'
                    : 'Drag players to record cuts. Drag the disc to throw.',
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step chips, playback controls and the current step's caption.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.viewModel,
    required this.editable,
    required this.playing,
    required this.time,
    required this.speed,
    required this.onPlay,
    required this.onScrub,
    required this.onSpeed,
    required this.onStep,
    required this.onAddStep,
  });

  final PlayEditorViewModel viewModel;
  final bool editable;
  final bool playing;

  /// Playback position, or null when a step is selected for editing.
  final double? time;
  final double speed;
  final VoidCallback onPlay;
  final ValueChanged<double> onScrub;
  final ValueChanged<double> onSpeed;
  final ValueChanged<int> onStep;
  final VoidCallback onAddStep;

  static const _speeds = [0.5, 1.0, 2.0];

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final n = vm.stepCount;
    final t = time;
    // Step being played, or the selected one.
    final active = t == null ? vm.step : (t == 0 ? 0 : t.ceil().clamp(1, n));
    final caption = t == null
        ? vm.stepNote
        : (n == 0 ? '' : vm.play.steps[t.floor().clamp(0, n - 1)].note);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton.filled(
                  tooltip: playing ? 'Pause' : 'Play',
                  onPressed: n == 0 ? null : onPlay,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                PopupMenuButton<double>(
                  tooltip: 'Playback speed',
                  initialValue: speed,
                  onSelected: onSpeed,
                  itemBuilder: (_) => [
                    for (final s in _speeds)
                      PopupMenuItem(value: s, child: Text('${_fmt(s)}×')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${_fmt(speed)}×',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ),
                Expanded(
                  child: n == 0
                      ? Text(
                          editable
                              ? 'Add a step to animate this play.'
                              : 'This play has no animation.',
                          style: theme.textTheme.bodySmall,
                        )
                      : Slider(
                          value: (t ?? vm.step.toDouble()).clamp(0, n * 1.0),
                          max: n.toDouble(),
                          onChanged: onScrub,
                        ),
                ),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i <= n; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(i == 0 ? 'Setup' : 'Step $i'),
                        selected: active == i,
                        onSelected: (_) => onStep(i),
                      ),
                    ),
                  if (editable && n < PlayEditorViewModel.maxSteps)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Add step'),
                      onPressed: onAddStep,
                    ),
                ],
              ),
            ),
            if (editable && t == null && vm.step > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _StepNoteField(
                        key: ValueKey('note-${vm.play.steps[vm.step - 1].id}'),
                        initial: vm.stepNote,
                        onChanged: vm.setStepNote,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete step',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => vm.deleteStep(vm.step),
                    ),
                  ],
                ),
              )
            else if (caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(caption, style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }

  static String _fmt(double s) =>
      s == s.roundToDouble() ? '${s.toInt()}' : '$s';
}

class _StepNoteField extends StatefulWidget {
  const _StepNoteField({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_StepNoteField> createState() => _StepNoteFieldState();
}

class _StepNoteFieldState extends State<_StepNoteField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    maxLength: 200,
    onChanged: widget.onChanged,
    decoration: const InputDecoration(
      isDense: true,
      counterText: '',
      hintText: 'Describe this step, e.g. "Break-side swing"',
    ),
  );
}

class _PlayDetailsDialog extends StatefulWidget {
  const _PlayDetailsDialog({required this.viewModel});

  final PlayEditorViewModel viewModel;

  @override
  State<_PlayDetailsDialog> createState() => _PlayDetailsDialogState();
}

class _PlayDetailsDialogState extends State<_PlayDetailsDialog> {
  late final _name = TextEditingController(text: widget.viewModel.play.name);
  late final _notes = TextEditingController(text: widget.viewModel.play.notes);
  late PlayCategory _category = widget.viewModel.play.category;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _apply() {
    widget.viewModel
      ..setName(_name.text.trim())
      ..setCategory(_category)
      ..setNotes(_notes.text);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Play details'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PlayCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in PlayCategory.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _apply, child: const Text('Done')),
    ],
  );
}

class _NotesDialog extends StatelessWidget {
  const _NotesDialog({required this.play});

  final Play play;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(play.name),
    content: Text(play.notes.isEmpty ? 'No notes.' : play.notes),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
