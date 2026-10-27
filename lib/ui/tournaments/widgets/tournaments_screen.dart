import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/tournament.dart';
import '../../../routing/routes.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/usau_attribution.dart';
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

class TournamentsScreen extends StatelessWidget {
  const TournamentsScreen({super.key, required this.viewModel});

  final TournamentsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Scaffold(
      appBar: AppBar(title: const Text('Tournaments')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (vm.loading) return const LoadingView();
          if (vm.error != null) {
            return ErrorView(error: vm.error, onRetry: vm.retry);
          }
          if (vm.isEmpty) {
            return const EmptyView(
              icon: Icons.emoji_events_outlined,
              title: 'No tournaments yet',
              message:
                  'Tournament data from USA Ultimate syncs daily. '
                  'Check back soon.',
            );
          }
          final list = vm.tournaments;
          return ConstrainedContent(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _Filters(viewModel: vm)),
                if (list.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyView(
                      icon: Icons.search_off,
                      title: 'No matching tournaments',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverList.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _TournamentCard(tournament: list[i]),
                    ),
                  ),
                const SliverToBoxAdapter(child: UsauAttribution()),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.viewModel});

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

class _TournamentCard extends StatelessWidget {
  const _TournamentCard({required this.tournament});

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
        onTap: () => context.go(Routes.tournament(t.id)),
      ),
    );
  }
}
