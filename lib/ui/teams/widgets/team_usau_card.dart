import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/usau_team.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../view_models/team_usau_viewmodel.dart';

/// A compact USA Ultimate summary on the team page: ranking and record
/// side by side, then the next (or latest) few tournaments.
class TeamUsauCard extends StatelessWidget {
  const TeamUsauCard({super.key, required this.viewModel});

  final TeamUsauViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final rank = vm.ranking;
    final record = vm.record;
    final schedule = vm.schedule;
    return SectionCard(
      title: 'USA Ultimate',
      action: CardLink(
        label: 'Full schedule',
        onTap: () =>
            context.push(Routes.searchedUsauTeam(vm.url, name: vm.name)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: rank == null ? '—' : '#${rank.rank}',
                  label: vm.division ?? 'Ranking',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  value: record == null
                      ? '—'
                      : '${record.wins}–${record.losses}',
                  label: 'Record',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!vm.loaded)
            Text(
              'Loading from USA Ultimate…',
              style: TextStyle(fontSize: 12, color: c.muted),
            )
          else if (vm.error != null)
            Text(
              "Couldn't load the USA Ultimate schedule.",
              style: TextStyle(fontSize: 12, color: c.muted),
            )
          else if (schedule.isEmpty)
            Text(
              'No tournaments listed yet.',
              style: TextStyle(fontSize: 12, color: c.muted),
            )
          else
            for (final e in schedule)
              _EventRow(event: e, upcoming: vm.isUpcoming(e)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: c.ink,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: c.muted),
          ),
        ],
      ),
    );
  }
}

/// One tournament: date, name and where the team finished (or "Upcoming").
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.upcoming});

  final UsauEvent event;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final e = event;
    final start = e.startDate;
    final finish = e.placement.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (start != null)
            DateBadge(date: start.toLocal(), size: 30)
          else
            const SizedBox(width: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: c.ink,
                  ),
                ),
                if (e.location.isNotEmpty)
                  Text(
                    e.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            upcoming ? 'Upcoming' : (finish.isEmpty ? '—' : _place(finish)),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: e.won && !upcoming ? c.highlight : c.muted,
            ),
          ),
        ],
      ),
    );
  }

  /// "5" → "5th"; already-suffixed placements stay as printed.
  static String _place(String p) {
    final n = int.tryParse(p);
    if (n == null) return p;
    final teen = n % 100 >= 11 && n % 100 <= 13;
    final suffix = teen
        ? 'th'
        : switch (n % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
    return '$n$suffix';
  }
}
