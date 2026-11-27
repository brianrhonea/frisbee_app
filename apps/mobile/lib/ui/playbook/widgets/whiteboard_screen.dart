import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/play.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/whiteboard_viewmodel.dart';
import 'field_painter.dart';
import 'playbook_parts.dart';
import 'whiteboard_canvas.dart';

enum _SaveAs { play, whiteboard }

/// The playbook's whiteboard: a field to sketch on for a chalk talk, saved
/// as a play or a whiteboard, or thrown away.
class WhiteboardScreen extends StatefulWidget {
  const WhiteboardScreen({super.key, required this.viewModel});

  final WhiteboardViewModel viewModel;

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  WhiteboardViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.saveAsPlay.addListener(_onSavedAsPlay);
    vm.saveWhiteboard.addListener(_onSavedWhiteboard);
  }

  @override
  void dispose() {
    vm.saveAsPlay.removeListener(_onSavedAsPlay);
    vm.saveWhiteboard.removeListener(_onSavedWhiteboard);
    super.dispose();
  }

  /// Shows a save's outcome; [onOk] gets the saved id.
  void _onSaved(Command<String> cmd, void Function(String id) onOk) {
    switch (cmd.result) {
      case Ok<String>(:final value):
        cmd.clearResult();
        onOk(value);
      case Error<String>():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  void _onSavedAsPlay() => _onSaved(vm.saveAsPlay, (id) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Saved as a play'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => context.go(Routes.play(vm.teamId, id)),
          ),
        ),
      );
  });

  void _onSavedWhiteboard() => _onSaved(
    vm.saveWhiteboard,
    (_) => showSnackBar(context, 'Whiteboard saved'),
  );

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.teamPlaybook(vm.teamId));
    }
  }

  Future<bool> _confirmDiscard() => confirmDialog(
    context,
    title: 'Discard sketch?',
    message: 'What you drew on the whiteboard won\'t be kept.',
    confirmLabel: 'Discard',
  );

  /// "Discard": throw the sketch away and go back to the playbook.
  Future<void> _discard() async {
    if (vm.hasUnsaved && !await _confirmDiscard()) return;
    if (mounted) _leave();
  }

  Future<void> _save(_SaveAs what) async {
    switch (what) {
      case _SaveAs.play:
        final details = await showDialog<PlayDetails>(
          context: context,
          builder: (_) => _SaveAsPlayDialog(initialName: vm.name),
        );
        if (details != null) vm.saveAsPlay.execute(details);
      case _SaveAs.whiteboard:
        // A saved whiteboard keeps its name; a new one is named first.
        if (vm.savedId != null && vm.name.isNotEmpty) {
          vm.saveWhiteboard.execute(vm.name);
          return;
        }
        final name = await showDialog<String>(
          context: context,
          builder: (_) => _NameDialog(
            initialName:
                'Whiteboard ${DateFormat.MMMd().format(DateTime.now())}',
          ),
        );
        if (name != null) vm.saveWhiteboard.execute(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        vm,
        vm.load,
        vm.saveAsPlay,
        vm.saveWhiteboard,
      ]),
      builder: (context, _) {
        if (vm.load.running) {
          return Scaffold(appBar: AppBar(), body: const LoadingState());
        }
        if (vm.load.error) {
          return Scaffold(
            appBar: AppBar(),
            body: ErrorState(error: vm.load.result, onRetry: vm.load.execute),
          );
        }
        final c = AppColors.of(context);
        final saving = vm.saveAsPlay.running || vm.saveWhiteboard.running;
        return PopScope(
          canPop: !vm.hasUnsaved,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            // Popping directly passes the PopScope, so back returns to
            // the playbook still on Whiteboard.
            if (await _confirmDiscard() && context.mounted) _leave();
          },
          child: Scaffold(
            appBar: AppBar(
              leading: backOr(context, Routes.teamPlaybook(vm.teamId)),
              title: _Title(viewModel: vm),
              actions: [
                TextButton(
                  onPressed: saving ? null : _discard,
                  style: TextButton.styleFrom(foregroundColor: c.ink2),
                  child: const Text('Discard'),
                ),
                if (vm.canSave)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PopupMenuButton<_SaveAs>(
                      tooltip: 'Save',
                      enabled: !saving && !vm.isEmpty,
                      onSelected: _save,
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _SaveAs.play,
                          child: Text('Save as play'),
                        ),
                        PopupMenuItem(
                          value: _SaveAs.whiteboard,
                          child: Text('Save whiteboard'),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Save',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: vm.isEmpty ? c.muted : c.accent,
                                ),
                              ),
                      ),
                    ),
                  ),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  _WhiteboardToolbar(viewModel: vm),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: WhiteboardCanvas(viewModel: vm),
                    ),
                  ),
                  _PenBar(viewModel: vm),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "Whiteboard" (or the saved one's name) over what's saved.
class _Title extends StatelessWidget {
  const _Title({required this.viewModel});

  final WhiteboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          vm.name.isEmpty ? 'Whiteboard' : vm.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: c.ink,
          ),
        ),
        Text(
          vm.savedId == null
              ? 'Not saved'
              : vm.dirty
              ? 'Unsaved changes'
              : 'Saved whiteboard',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
      ],
    );
  }
}

class _WhiteboardToolbar extends StatelessWidget {
  const _WhiteboardToolbar({required this.viewModel});

  final WhiteboardViewModel viewModel;

  static const _tools = [
    (WhiteboardTool.move, Icons.near_me_outlined, 'Move', 'Move pieces'),
    (WhiteboardTool.pen, Icons.edit_outlined, 'Pen', 'Draw'),
    (WhiteboardTool.offense, Icons.circle, 'Offense', 'Offense player'),
    (WhiteboardTool.defense, Icons.circle, 'Defense', 'Defense player'),
    (WhiteboardTool.disc, Icons.album_outlined, 'Disc', 'Disc'),
    (WhiteboardTool.cone, Icons.change_history, 'Cone', 'Cone'),
    (WhiteboardTool.erase, Icons.auto_fix_normal_outlined, 'Erase', 'Erase'),
  ];

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Navy needs a light ring to show on a dark card.
    final navy = dark
        ? Color.lerp(FieldColors.defense, Colors.white, 0.45)
        : FieldColors.defense;
    return PlaybookBar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            for (final (tool, icon, label, tooltip) in _tools)
              ToolTile(
                icon: icon,
                label: label,
                tooltip: tooltip,
                selected: vm.tool == tool,
                iconColor: switch (tool) {
                  // The pen shows its colour (white would vanish).
                  WhiteboardTool.pen => switch (vm.color) {
                    DrawingColor.white => null,
                    DrawingColor.ink => navy,
                    final other => penColor(other),
                  },
                  WhiteboardTool.offense => FieldColors.offense,
                  WhiteboardTool.defense => navy,
                  WhiteboardTool.cone => FieldColors.cone,
                  _ => null,
                },
                onPressed: () => vm.setTool(tool),
              ),
          ],
        ),
      ),
    );
  }
}

/// Under the field: pen colours, Undo and Clear, and a note when saving
/// isn't open to the user or the board is full.
class _PenBar extends StatelessWidget {
  const _PenBar({required this.viewModel});

  final WhiteboardViewModel viewModel;

  static const _colors = [
    (DrawingColor.white, 'White pen'),
    (DrawingColor.ink, 'Navy pen'),
    (DrawingColor.turf, 'Turf pen'),
    (DrawingColor.amber, 'Amber pen'),
  ];

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    final note = vm.strokesFull
        ? 'The whiteboard is full: erase a line to draw another.'
        : vm.tokensFull
        ? "That's the most pieces a whiteboard holds."
        : !vm.canSave
        ? "Sketch away. Only the team's admins can save whiteboards."
        : null;
    return PlaybookBar(
      top: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 0, 4),
                child: Text(
                  note,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
            Row(
              children: [
                for (final (color, label) in _colors)
                  ColorDot(
                    color: penColor(color),
                    label: label,
                    selected:
                        vm.tool == WhiteboardTool.pen && vm.color == color,
                    onPressed: () => vm.setColor(color),
                  ),
                const Spacer(),
                ToolTile(
                  icon: Icons.undo,
                  label: 'Undo',
                  tooltip: 'Undo',
                  onPressed: vm.canUndo ? vm.undo : null,
                ),
                ToolTile(
                  icon: Icons.layers_clear_outlined,
                  label: 'Clear',
                  tooltip: 'Clear whiteboard',
                  onPressed: vm.isEmpty ? null : vm.clear,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Save whiteboard": its name.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initialName});

  final String initialName;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save whiteboard'),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 100,
        decoration: const InputDecoration(labelText: 'Name', counterText: ''),
        onSubmitted: (_) => _done(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      ListenableBuilder(
        listenable: _name,
        builder: (context, _) => FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _done,
          child: const Text('Save'),
        ),
      ),
    ],
  );
}

/// "Save as play": a name and a category.
class _SaveAsPlayDialog extends StatefulWidget {
  const _SaveAsPlayDialog({required this.initialName});

  final String initialName;

  @override
  State<_SaveAsPlayDialog> createState() => _SaveAsPlayDialogState();
}

class _SaveAsPlayDialogState extends State<_SaveAsPlayDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  PlayCategory _category = PlayCategory.offense;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop<PlayDetails>(context, (name: name, category: _category));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save as play'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Play name',
              counterText: '',
            ),
            onSubmitted: (_) => _done(),
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
          Text(
            'The pieces become the play\'s setup and your lines are kept. '
            'Add steps in the play editor.',
            style: TextStyle(fontSize: 12, color: AppColors.of(context).muted),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      ListenableBuilder(
        listenable: _name,
        builder: (context, _) => FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _done,
          child: const Text('Save'),
        ),
      ),
    ],
  );
}
