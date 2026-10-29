import 'package:flutter/material.dart';

import '../../../domain/models/roster_player.dart';
import '../../../domain/models/stats.dart';
import 'player_chooser.dart';

typedef LineChoice = ({List<String> players, String? saveAs, Side? side});

/// Opens the line picker: import a saved line or build a custom one.
/// Returns null if cancelled.
Future<LineChoice?> showLinePicker(
  BuildContext context, {
  required List<RosterPlayer> available,
  List<StatLine> saved = const [],
  List<String> initial = const [],
  bool canSave = false,
  String title = 'Pick a line',
  bool requireName = false,
  Side? defaultSide,
}) => showModalBottomSheet<LineChoice>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _LinePicker(
    available: available,
    saved: saved,
    initial: initial,
    canSave: canSave,
    title: title,
    requireName: requireName,
    defaultSide: defaultSide,
  ),
);

class _LinePicker extends StatefulWidget {
  const _LinePicker({
    required this.available,
    required this.saved,
    required this.initial,
    required this.canSave,
    required this.title,
    required this.requireName,
    this.defaultSide,
  });

  final List<RosterPlayer> available;
  final List<StatLine> saved;
  final List<String> initial;
  final bool canSave;
  final String title;

  /// Building a saved line rather than picking one for a point.
  final bool requireName;

  /// O/D tag preselected when saving.
  final Side? defaultSide;

  @override
  State<_LinePicker> createState() => _LinePickerState();
}

class _LinePickerState extends State<_LinePicker> {
  late final Set<String> _picked = {...widget.initial};
  final _name = TextEditingController();
  late Side? _side = widget.defaultSide;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ready =>
      _picked.length == StatLine.size &&
      (!widget.requireName || _name.text.trim().isNotEmpty);

  void _toggle(String id) => setState(() {
    if (!_picked.remove(id) && _picked.length < StatLine.size) _picked.add(id);
  });

  void _done() => Navigator.pop<LineChoice>(context, (
    players: [
      for (final p in widget.available)
        if (_picked.contains(p.id)) p.id,
    ],
    saveAs: _name.text.trim().isEmpty ? null : _name.text.trim(),
    side: _side,
  ));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final full = _picked.length == StatLine.size;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                if (widget.saved.isNotEmpty && !widget.requireName) ...[
                  const SizedBox(height: 16),
                  Text('Saved lines', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final l in widget.saved)
                    Card.outlined(
                      child: ListTile(
                        leading: const Icon(Icons.groups_outlined),
                        title: Text(l.name),
                        subtitle: Text(
                          [
                            for (final id in l.players)
                              widget.available
                                      .where((p) => p.id == id)
                                      .firstOrNull
                                      ?.name
                                      .split(' ')
                                      .first ??
                                  '?',
                          ].join(', '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          onPressed: () => Navigator.pop<LineChoice>(context, (
                            players: l.players,
                            saveAs: null,
                            side: l.side,
                          )),
                          child: const Text('Use'),
                        ),
                        onTap: () => setState(() {
                          _picked
                            ..clear()
                            ..addAll(l.players);
                        }),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.requireName ? 'Players' : 'Custom line',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      '${_picked.length}/${StatLine.size}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: full ? Colors.green.shade600 : scheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_picked.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(_picked.clear),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                PlayerChooser(
                  players: widget.available,
                  selected: _picked,
                  onToggle: _toggle,
                  max: StatLine.size,
                ),
                if (widget.canSave || widget.requireName) ...[
                  const SizedBox(height: 16),
                  SegmentedButton<Side?>(
                    segments: const [
                      ButtonSegment(value: Side.offense, label: Text('O line')),
                      ButtonSegment(value: Side.defense, label: Text('D line')),
                      ButtonSegment(value: null, label: Text('Either')),
                    ],
                    selected: {_side},
                    onSelectionChanged: (s) => setState(() => _side = s.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    maxLength: 40,
                    decoration: InputDecoration(
                      labelText: widget.requireName
                          ? 'Line name'
                          : 'Save as line (optional)',
                      hintText: 'e.g. O-line, D-line 2, Zone',
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _ready ? _done : null,
                      child: Text(
                        full
                            ? (widget.requireName ? 'Save line' : 'Use line')
                            : 'Pick ${StatLine.size - _picked.length} more',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
