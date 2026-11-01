import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/tournament.dart';
import '../../../routing/routes.dart';
import '../view_models/tournaments_viewmodel.dart';

String formatDateRange(DateTime? start, DateTime? end) {
  if (start == null) return 'Date TBA';
  final md = DateFormat.MMMd();
  if (end == null || DateUtils.isSameDay(start, end)) {
    return DateFormat.yMMMd().format(start);
  }
  if (start.year == end.year && start.month == end.month) {
    return '${md.format(start)}–${end.day}, ${end.year}';
  }
  return '${md.format(start)} – ${DateFormat.yMMMd().format(end)}';
}

/// Search, upcoming/past and level/division filters for the USAU list.
class TournamentFilters extends StatelessWidget {
  const TournamentFilters({super.key, required this.viewModel});

  final TournamentsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name or location',
            ),
            onChanged: vm.setQuery,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Upcoming')),
                  ButtonSegment(value: true, label: Text('Past')),
                ],
                selected: {vm.showPast},
                onSelectionChanged: (s) => vm.setShowPast(s.first),
              ),
              if (vm.levels.isNotEmpty)
                _DropdownChip(
                  label: 'Level',
                  value: vm.level,
                  options: vm.levels,
                  onChanged: vm.setLevel,
                ),
              if (vm.divisions.isNotEmpty)
                _DropdownChip(
                  label: 'Division',
                  value: vm.division,
                  options: vm.divisions,
                  onChanged: vm.setDivision,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DropdownChip extends StatelessWidget {
  const _DropdownChip({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      onSelected: (v) => onChanged(v == '' ? null : v),
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: Text('All ${label.toLowerCase()}s')),
        for (final o in options) PopupMenuItem(value: o, child: Text(o)),
      ],
      child: Chip(
        avatar: value == null ? null : const Icon(Icons.check, size: 16),
        label: Text(value ?? label),
        deleteIcon: const Icon(Icons.arrow_drop_down),
        onDeleted: null,
      ),
    );
  }
}

/// One USA Ultimate tournament; opens its detail page.
class TournamentCard extends StatelessWidget {
  const TournamentCard({super.key, required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(t.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatDateRange(t.startDate, t.endDate)),
            if (t.location.isNotEmpty) Text(t.location),
            if (t.competitionLevel.isNotEmpty || t.divisions.isNotEmpty)
              Text(
                [
                  if (t.competitionLevel.isNotEmpty) t.competitionLevel,
                  ...t.divisions,
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.tournament(t.id)),
      ),
    );
  }
}
