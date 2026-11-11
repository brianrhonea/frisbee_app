import 'package:flutter/material.dart';

import '../../../domain/models/roster_player.dart';

enum PlayerSort { name, position }

/// [players] alphabetically, or grouped Handlers → Cutters → Hybrids with
/// each group alphabetical.
List<(PlayerPosition?, List<RosterPlayer>)> sortPlayers(
  List<RosterPlayer> players,
  PlayerSort sort,
) {
  int byName(RosterPlayer a, RosterPlayer b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  final sorted = [...players]..sort(byName);
  if (sort == PlayerSort.name) return [(null, sorted)];
  return [
    for (final pos in PlayerPosition.values)
      if (sorted.where((p) => p.position == pos).toList() case final group
          when group.isNotEmpty)
        (pos, group),
  ];
}

/// A player's jersey number in a circle, scaled down so two- and
/// three-digit numbers stay centered inside it.
class JerseyNumber extends StatelessWidget {
  const JerseyNumber(this.number, {super.key});

  final int number;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: FittedBox(
        child: Text(
          '$number',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}

/// Tap-to-select chips for building a line of [max] players, with an
/// A–Z / position sort toggle.
class PlayerChooser extends StatefulWidget {
  const PlayerChooser({
    super.key,
    required this.players,
    required this.selected,
    required this.onToggle,
    required this.max,
  });

  final List<RosterPlayer> players;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final int max;

  @override
  State<PlayerChooser> createState() => _PlayerChooserState();
}

class _PlayerChooserState extends State<PlayerChooser> {
  // Ephemeral view state.
  PlayerSort _sort = PlayerSort.name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = widget.selected.length >= widget.max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<PlayerSort>(
          segments: const [
            ButtonSegment(
              value: PlayerSort.name,
              label: Text('A–Z'),
              icon: Icon(Icons.sort_by_alpha),
            ),
            ButtonSegment(
              value: PlayerSort.position,
              label: Text('Handler / Cutter'),
              icon: Icon(Icons.category_outlined),
            ),
          ],
          selected: {_sort},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _sort = s.first),
        ),
        for (final (pos, group) in sortPlayers(widget.players, _sort)) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              pos == null ? 'All players' : '${pos.label}s',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in group)
                FilterChip(
                  avatar: p.number == null ? null : JerseyNumber(p.number!),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  labelStyle: theme.textTheme.bodyLarge,
                  label: Text(p.name),
                  selected: widget.selected.contains(p.id),
                  onSelected: full && !widget.selected.contains(p.id)
                      ? null
                      : (_) => widget.onToggle(p.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
