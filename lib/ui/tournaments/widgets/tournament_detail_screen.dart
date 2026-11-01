import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/tournament.dart';
import '../../../routing/routes.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/usau_attribution.dart';
import '../../follow/widgets/follow_button.dart';
import '../view_models/tournament_detail_viewmodel.dart';
import 'event_schedule_widgets.dart';
import 'tournament_widgets.dart';

class TournamentDetailScreen extends StatelessWidget {
  const TournamentDetailScreen({super.key, required this.viewModel});

  final TournamentDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final t = vm.tournament;
        final leading = backOr(context, Routes.tournaments);
        if (vm.loading) {
          return Scaffold(
            appBar: AppBar(leading: leading),
            body: const LoadingView(),
          );
        }
        if (vm.error != null) {
          return Scaffold(
            appBar: AppBar(leading: leading),
            body: ErrorView(error: vm.error, onRetry: vm.retry),
          );
        }
        if (t == null) {
          return Scaffold(
            appBar: AppBar(leading: leading),
            body: const EmptyView(
              icon: Icons.event_busy,
              title: 'Tournament not found',
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            leading: leading,
            title: Text(t.name),
            actions: [
              if (vm.follow case final follow?)
                FollowControl(viewModel: follow, compact: true),
              if (vm.schedule != null)
                IconButton(
                  tooltip: 'Refresh scores',
                  icon: const Icon(Icons.refresh),
                  onPressed: vm.loadSchedule.running ? null : vm.refresh,
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              ConstrainedContent(maxWidth: 640, child: _Details(tournament: t)),
              _Schedule(viewModel: vm),
              const UsauAttribution(),
            ],
          ),
        );
      },
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(formatDateRange(t.startDate, t.endDate)),
          ),
          if (t.location.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(t.location),
            ),
          if (t.competitionLevel.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.military_tech_outlined),
              title: Text(t.competitionLevel),
            ),
          if (t.divisions.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(t.divisions.join(', ')),
            ),
          const SizedBox(height: 16),
          if (t.url.isNotEmpty)
            FilledButton.icon(
              onPressed: () async {
                final ok = await launchUrl(Uri.parse(t.url));
                if (!ok && context.mounted) {
                  showSnackBar(context, 'Could not open link');
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('View on USA Ultimate'),
            ),
        ],
      ),
    );
  }
}

/// The division picker, stage tabs and the selected stage's pools, games
/// and brackets. Shows nothing for tournaments without a USAU page.
class _Schedule extends StatelessWidget {
  const _Schedule({required this.viewModel});

  final TournamentDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);

    Widget centered(Widget child) => ConstrainedContent(
      maxWidth: 640,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: child,
      ),
    );

    Widget status(String text, {VoidCallback? onRetry, bool busy = false}) =>
        centered(
          Row(
            children: [
              if (busy)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (busy) const SizedBox(width: 12),
              Expanded(child: Text(text)),
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        );

    if (vm.tournament?.url.isEmpty ?? true) return const SizedBox.shrink();
    final header = centered(
      Text(
        'Schedule & brackets',
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
    if (vm.divisionsLoading) {
      return Column(
        children: [header, status('Checking for a schedule…', busy: true)],
      );
    }
    if (vm.divisionsError != null) {
      return Column(
        children: [
          header,
          status(
            'Couldn\'t load the schedule: ${errorMessage(vm.divisionsError)}',
            onRetry: vm.retry,
          ),
        ],
      );
    }
    final divisions = vm.divisions;
    if (divisions.isEmpty) {
      return Column(children: [header, status('No schedule posted yet.')]);
    }

    final schedule = vm.schedule;
    final stages = schedule?.stages ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        centered(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton(
              showSelectedIcon: false,
              segments: [
                for (final d in divisions)
                  ButtonSegment(value: d, label: Text(vm.divisionLabel(d))),
              ],
              selected: {?vm.selectedDivision},
              onSelectionChanged: (s) => vm.selectDivision(s.single),
            ),
          ),
        ),
        if (vm.scheduleLoading)
          status('Loading ${vm.selectedDivision?.title} schedule…', busy: true)
        else if (vm.scheduleError != null)
          status(
            'Couldn\'t load this division: ${errorMessage(vm.scheduleError)}',
            onRetry: vm.retry,
          )
        else if (stages.isEmpty)
          status('No games posted for this division yet.')
        else ...[
          DefaultTabController(
            // Rebuilt per division so the tab count and selection match.
            key: ValueKey(vm.selectedDivision),
            length: stages.length,
            initialIndex: vm.stageIndex,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              onTap: vm.selectStage,
              tabs: [for (final s in stages) Tab(text: s.title)],
            ),
          ),
          if (vm.stage case final stage?)
            StageView(stage: stage, layoutOf: vm.layoutOf),
        ],
      ],
    );
  }
}
