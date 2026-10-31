import 'package:flutter/material.dart';

import '../../../domain/models/stats.dart';

/// "Game to" picker for new games. It can be changed later from the game.
class GameToField extends StatelessWidget {
  const GameToField({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    initialValue: value,
    decoration: const InputDecoration(
      labelText: 'Game to',
      prefixIcon: Icon(Icons.flag_outlined),
      helperText: 'Stats lock when someone reaches it',
    ),
    items: [
      for (final t in StatsGame.targets)
        DropdownMenuItem(value: t, child: Text('$t')),
    ],
    onChanged: (v) => onChanged(v!),
  );
}

/// Timeouts each team gets per half. It can be changed later from the game.
class TimeoutsField extends StatelessWidget {
  const TimeoutsField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    initialValue: value,
    decoration: const InputDecoration(
      labelText: 'Timeouts per half',
      prefixIcon: Icon(Icons.timer_outlined),
    ),
    items: [
      for (final n in StatsGame.timeoutChoices)
        DropdownMenuItem(value: n, child: Text(n == 0 ? 'None' : '$n')),
    ],
    onChanged: (v) => onChanged(v!),
  );
}
