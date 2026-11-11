import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/team.dart';
import '../view_models/hosted_tournament_form_viewmodel.dart';

/// The one format every division of an event plays (field size, roster
/// minimum, scoring, game length, fields and the first game's time), and
/// which divisions are open, as checkboxes.
class EventFormatSection extends StatelessWidget {
  const EventFormatSection({super.key, required this.viewModel});

  final HostedTournamentFormViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final f = vm.format;
    final s = vm.settings;
    final editable = vm.formatEditable;

    Widget number(
      String label,
      int value,
      List<int> options,
      void Function(int) onChanged, {
      String Function(int)? text,
    }) => DropdownButtonFormField<int>(
      key: ValueKey('$label$value'),
      initialValue: options.contains(value) ? value : null,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final o in {...options, value}.toList()..sort())
          DropdownMenuItem(value: o, child: Text(text?.call(o) ?? '$o')),
      ],
      onChanged: editable ? (v) => v == null ? null : onChanged(v) : null,
    );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text, style: theme.textTheme.titleSmall),
    );

    Widget pair(Widget a, Widget b) => Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    );

    final time = DateFormat.jm().format(s.startsAt);
    final night = DateFormat('EEEE').format(vm.startsOn);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Text('Format', style: theme.textTheme.titleMedium),
        Text(
          editable
              ? 'Every division plays this. Change it here and every '
                    'division follows, until its schedule is out.'
              : 'The schedule is out, so the format is set.',
          style: theme.textTheme.bodySmall,
        ),
        heading('Players on the field'),
        Wrap(
          spacing: 8,
          children: [
            for (final n in TournamentSettings.fieldSizes)
              ChoiceChip(
                label: Text('${n}v$n'),
                selected: s.playersOnField == n,
                onSelected: editable ? (_) => vm.setFieldSize(n) : null,
              ),
          ],
        ),
        const SizedBox(height: 8),
        pair(
          DropdownButtonFormField<CompetitionLevel>(
            key: ValueKey(f.level),
            initialValue: f.level,
            decoration: const InputDecoration(labelText: 'Level'),
            items: [
              for (final l in CompetitionLevel.values)
                DropdownMenuItem(value: l, child: Text(l.label)),
            ],
            onChanged: editable
                ? (v) => v == null ? null : vm.setFormat(f.copyWith(level: v))
                : null,
          ),
          number(
            'Teams per division',
            f.maxTeams,
            TournamentDivision.teamCaps,
            (v) => vm.setFormat(f.copyWith(maxTeams: v)),
            text: (v) => '$v teams',
          ),
        ),
        if (!vm.takesPlayers || vm.teamEntry) ...[
          const SizedBox(height: 8),
          number(
            'Roster minimum',
            f.effectiveMinRoster,
            [for (var n = 2; n <= 20; n++) n],
            (v) => vm.setFormat(f.copyWith(minRoster: () => v)),
            text: (v) => '$v players',
          ),
        ],
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: Text(
            vm.isLeague ? 'Game night: ${night}s at $time' : 'First game $time',
          ),
          subtitle: Text(
            vm.isLeague
                ? 'Weekly, on the first night\'s day. Tap to change the time.'
                : 'Each day. Tap to change.',
          ),
          onTap: editable
              ? () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(s.startsAt),
                    helpText: vm.isLeague
                        ? 'First game each night'
                        : 'First game each day',
                  );
                  if (t != null) vm.setFirstGame(t.hour, t.minute);
                }
              : null,
        ),
        if (!vm.isLeague) ...[
          DropdownButtonFormField<TournamentFormat>(
            key: ValueKey(s.format),
            initialValue: s.format,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Format',
              helperText: s.format.summary,
            ),
            items: [
              for (final x in TournamentFormat.values)
                DropdownMenuItem(value: x, child: Text(x.label)),
            ],
            onChanged: editable
                ? (v) =>
                      v == null ? null : vm.setSettings(s.copyWith(format: v))
                : null,
          ),
          if (s.format == TournamentFormat.poolsSingleElim ||
              s.format == TournamentFormat.poolsPlacement) ...[
            const SizedBox(height: 8),
            number(
              'Pools',
              s.poolCount,
              [1, 2, 3, 4, 5, 6, 8],
              (v) => vm.setSettings(s.copyWith(poolCount: v)),
              text: (v) => v == 1 ? 'One pool' : '$v pools',
            ),
          ],
        ],
        heading('Scoring'),
        SegmentedButton<ScoringMode>(
          segments: [
            for (final m in ScoringMode.values)
              ButtonSegment(value: m, label: Text(m.label)),
          ],
          selected: {s.scoring},
          onSelectionChanged: editable
              ? (v) => vm.setSettings(s.copyWith(scoring: v.first))
              : null,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            s.timed
                ? 'Most points when time runs out wins. Tied at time, they '
                      'play one more point.'
                : 'First to the score wins; the time cap keeps the night on '
                      'schedule.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        pair(
          s.timed
              ? number(
                  'Game length',
                  s.gameMinutes,
                  [15, 20, 25, 30, 40, 45, 50, 60, 75, 90],
                  (v) => vm.setSettings(s.copyWith(gameMinutes: v)),
                  text: (v) => '$v min',
                )
              : number('Game to', s.scoreCap, [
                  5,
                  7,
                  9,
                  11,
                  13,
                  15,
                  17,
                  21,
                ], (v) => vm.setSettings(s.copyWith(scoreCap: v))),
          s.timed
              ? number(
                  'Timeouts per half',
                  s.timeoutsPerHalf,
                  [0, 1, 2, 3],
                  (v) => vm.setSettings(s.copyWith(timeoutsPerHalf: v)),
                )
              : number(
                  'Time cap',
                  s.gameMinutes,
                  [20, 25, 30, 40, 45, 50, 60, 75, 90, 100, 120],
                  (v) => vm.setSettings(s.copyWith(gameMinutes: v)),
                  text: (v) => '$v min',
                ),
        ),
        const SizedBox(height: 8),
        pair(
          number('Fields', s.fields, [
            for (var i = 1; i <= 16; i++) i,
          ], (v) => vm.setSettings(s.copyWith(fields: v))),
          number(
            'Break between games',
            s.breakMinutes,
            [0, 5, 10, 15, 20, 30],
            (v) => vm.setSettings(s.copyWith(breakMinutes: v)),
            text: (v) => '$v min',
          ),
        ),
        if (!s.timed) ...[
          const SizedBox(height: 8),
          number(
            'Timeouts per half',
            s.timeoutsPerHalf,
            [0, 1, 2, 3],
            (v) => vm.setSettings(s.copyWith(timeoutsPerHalf: v)),
          ),
        ],
        const Divider(height: 32),
        Text('Divisions', style: theme.textTheme.titleMedium),
        Text(
          'Tick each division to open. Each takes its own '
          '${vm.takesPlayers ? 'signups' : 'teams'} and gets its own '
          'schedule.',
          style: theme.textTheme.bodySmall,
        ),
        for (final d in EventFormat.divisionChoices)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: vm.isOpen(d),
            title: Text('${f.level.label} ${d.label}'),
            subtitle: switch (vm.isOpen(d) ? vm.lockedReason(d) : null) {
              final reason? => Text(reason),
              null => null,
            },
            onChanged: vm.isOpen(d) && vm.lockedReason(d) != null
                ? null
                : (v) => vm.setOpen(d, v ?? false),
          ),
      ],
    );
  }
}
