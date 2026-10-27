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

class _PlayEditorScreenState extends State<PlayEditorScreen> {
  PlayEditorViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.save.addListener(_onSave);
  }

  @override
  void dispose() {
    vm.save.removeListener(_onSave);
    super.dispose();
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
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                  vm.undo,
              const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                  vm.undo,
              const SingleActivator(LogicalKeyboardKey.keyY, control: true):
                  vm.redo,
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ): vm.redo,
              const SingleActivator(LogicalKeyboardKey.delete):
                  vm.deleteSelected,
              const SingleActivator(LogicalKeyboardKey.backspace):
                  vm.deleteSelected,
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
                      if (editable) _Toolbar(viewModel: vm),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: editable
                              ? PlayCanvas(viewModel: vm)
                              : PlayDiagram(play: vm.play),
                        ),
                      ),
                    ],
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
