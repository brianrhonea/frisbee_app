import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/stats.dart';
import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/stats_viewmodel.dart';
import 'game_to_field.dart';
import 'stat_sheet.dart';
import 'stats_glossary.dart';

class StatsTab extends StatelessWidget {
  const StatsTab({super.key, required this.viewModel});

  final StatsViewModel viewModel;

  Future<void> _add(BuildContext context) async {
    final vm = viewModel;
    final kind = await showModalBottomSheet<EventType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New tournament'),
              subtitle: const Text('A folder for its games, roster and lines'),
              onTap: () => Navigator.pop(context, EventType.tournament),
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('New game'),
              subtitle: const Text('A standalone game or scrimmage'),
              onTap: () => Navigator.pop(context, EventType.game),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (kind == null || !context.mounted) return;
    final draft = await showDialog<_Draft>(
      context: context,
      builder: (_) => _NewDialog(
        tournament: kind == EventType.tournament,
        events: vm.linkableEvents(kind),
        linesFor: (e) => vm.linesForEvent(e).length,
        onCreateEvent: vm.canCreateEvents
            ? (e) async {
                await vm.createEvent.execute(e);
                final r = vm.createEvent.result;
                if (r case Ok(:final value)) return value;
                if (context.mounted) showErrorSnackBar(context, r);
                return null;
              }
            : null,
      ),
    );
    if (draft == null || !context.mounted) return;
    if (kind == EventType.tournament) {
      await vm.createTournament.execute((
        name: draft.name,
        startDate: draft.date,
        event: draft.event,
      ));
      final r = vm.createTournament.result;
      if (!context.mounted) return;
      if (r case Ok(:final value)) {
        context.push(Routes.statsTournament(vm.teamId, value));
      } else {
        showErrorSnackBar(context, r);
      }
    } else {
      await vm.createGame.execute((
        opponent: draft.name,
        date: draft.date,
        gameTo: draft.gameTo,
        timeoutsPerHalf: draft.timeouts,
        event: draft.event,
      ));
      final r = vm.createGame.result;
      if (!context.mounted) return;
      if (r case Ok(:final value)) {
        context.push(Routes.statsGame(vm.teamId, value));
      } else {
        showErrorSnackBar(context, r);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      if (!vm.loaded) return const LoadingView();
      if (vm.error != null) return ErrorView(error: vm.error);
      final theme = Theme.of(context);
      final standalone = vm.standaloneGames;
      return Scaffold(
        floatingActionButton: vm.canEdit
            ? FloatingActionButton.extended(
                heroTag: 'new-stats',
                onPressed: () => _add(context),
                icon: const Icon(Icons.add),
                label: const Text('Game / tournament'),
              )
            : null,
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                const Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: StatsHelpButton(),
                ),
                _SeasonCard(viewModel: vm),
                const SizedBox(height: 20),
                Text('Tournaments', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (vm.tournaments.isEmpty)
                  const Text('No tournaments yet.')
                else
                  for (final t in vm.tournaments)
                    _TournamentFolder(
                      tournament: t,
                      games: vm.gamesIn(t.id),
                      onOpen: () =>
                          context.push(Routes.statsTournament(vm.teamId, t.id)),
                    ),
                const SizedBox(height: 20),
                Text('Games', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (standalone.isEmpty)
                  const Text('No standalone games yet.')
                else
                  Card.outlined(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final g in standalone)
                          GameRow(
                            game: g,
                            onTap: () =>
                                context.push(Routes.statsGame(vm.teamId, g.id)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({required this.viewModel});

  final StatsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final leaders = vm.seasonSheet.ranked.take(3).toList();
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Season', style: theme.textTheme.labelLarge),
                      Text(
                        '${vm.wins}–${vm.losses}',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => context.push(Routes.seasonStats(vm.teamId)),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('Season stats'),
                ),
              ],
            ),
            if (leaders.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Top +/-', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final (i, p) in leaders.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(width: 24, child: Text('${i + 1}.')),
                      Expanded(child: Text(vm.nameOf(p.playerId))),
                      Text(
                        '${p.goals}G ${p.assists}A '
                        '${p.handBlocks + p.breakups}D',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '+${p.plusMinus}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TournamentFolder extends StatelessWidget {
  const _TournamentFolder({
    required this.tournament,
    required this.games,
    required this.onOpen,
  });

  final StatsTournament tournament;
  final List<StatsGame> games;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final wins = games.where((g) => g.won == true).length;
    final losses = games.where((g) => g.won == false).length;
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onOpen,
        leading: Icon(Icons.folder, color: Colors.amber.shade700, size: 32),
        title: Text(t.name),
        subtitle: Text(
          [
            DateFormat.MMMd().format(t.startDate),
            '${games.length} game${games.length == 1 ? '' : 's'}',
            if (wins + losses > 0) '$wins–$losses',
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// One game "file": opponent, date, score and result.
class GameRow extends StatelessWidget {
  const GameRow({super.key, required this.game, required this.onTap});

  final StatsGame game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final g = game;
    final (badge, color) = switch (g.won) {
      true => ('W', Colors.green.shade600),
      false => ('L', scheme.error),
      null => (g.finished ? 'T' : 'LIVE', scheme.tertiary),
    };
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.description_outlined),
      title: Text('vs ${g.opponent}'),
      subtitle: Text(DateFormat.MMMd().add_jm().format(g.date)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${g.ourScore}–${g.theirScore}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _Draft = ({
  String name,
  DateTime date,
  int gameTo,
  int timeouts,
  TeamEvent? event,
});

class _NewDialog extends StatefulWidget {
  const _NewDialog({
    required this.tournament,
    required this.events,
    required this.linesFor,
    required this.onCreateEvent,
  });

  final bool tournament;
  final List<TeamEvent> events;

  /// How many saved lines come with linking an event.
  final int Function(TeamEvent? event) linesFor;

  /// Adds an event to the schedule and returns it, or null if that
  /// failed. Null when the user can't add events.
  final Future<TeamEvent?> Function(NewEvent event)? onCreateEvent;

  @override
  State<_NewDialog> createState() => _NewDialogState();
}

class _NewDialogState extends State<_NewDialog> {
  final _name = TextEditingController();
  late final List<TeamEvent> _events = [...widget.events];
  DateTime _date = DateTime.now();
  int _gameTo = 15;
  int _timeouts = 2;
  TeamEvent? _event;
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _link(TeamEvent? e) => setState(() {
    _event = e;
    if (e != null) {
      _date = e.startsAt;
      if (_name.text.trim().isEmpty && widget.tournament) _name.text = e.title;
    }
  });

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _newEvent() async {
    final draft = await showDialog<NewEvent>(
      context: context,
      builder: (_) => _NewEventDialog(
        tournament: widget.tournament,
        title: widget.tournament ? _name.text.trim() : '',
        date: _date,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _creating = true);
    final event = await widget.onCreateEvent!(draft);
    if (!mounted) return;
    setState(() {
      _creating = false;
      if (event != null) _events.insert(0, event);
    });
    if (event != null) _link(event);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = widget.linesFor(_event);
    return AlertDialog(
      title: Text(widget.tournament ? 'New tournament' : 'New game'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<TeamEvent?>(
                // Re-created when an event is added so it shows the pick.
                key: ValueKey(_event?.id),
                initialValue: _event,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Link to schedule event',
                  prefixIcon: Icon(Icons.event_outlined),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  for (final e in _events)
                    DropdownMenuItem(
                      value: e,
                      child: Text(
                        '${e.title} · ${e.type.label} · '
                        '${DateFormat.MMMd().format(e.startsAt)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _link,
              ),
              if (widget.onCreateEvent != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _creating ? null : _newEvent,
                    icon: _creating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(
                      _events.isEmpty
                          ? 'No events yet. Create one'
                          : 'Create a new event',
                    ),
                  ),
                ),
              if (lines > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '$lines saved line${lines == 1 ? '' : 's'} from this '
                    'event will be imported.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: widget.tournament ? 'Tournament name' : 'Opponent',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(DateFormat.yMMMEd().format(_date)),
                onTap: _pickDate,
              ),
              if (!widget.tournament) ...[
                GameToField(
                  value: _gameTo,
                  onChanged: (v) => setState(() => _gameTo = v),
                ),
                const SizedBox(height: 12),
                TimeoutsField(
                  value: _timeouts,
                  onChanged: (v) => setState(() => _timeouts = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop<_Draft>(context, (
                  name: _name.text.trim(),
                  date: _date,
                  gameTo: _gameTo,
                  timeouts: _timeouts,
                  event: _event,
                )),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// Quick schedule event, e.g. a scrimmage that comes up during practice.
class _NewEventDialog extends StatefulWidget {
  const _NewEventDialog({
    required this.tournament,
    required this.title,
    required this.date,
  });

  final bool tournament;
  final String title;
  final DateTime date;

  @override
  State<_NewEventDialog> createState() => _NewEventDialogState();
}

class _NewEventDialogState extends State<_NewEventDialog> {
  late final _title = TextEditingController(
    text: widget.title.isNotEmpty
        ? widget.title
        : widget.tournament
        ? ''
        : 'Scrimmage',
  );
  late EventType _type = widget.tournament
      ? EventType.tournament
      : EventType.practice;
  late DateTime _day = DateUtils.dateOnly(widget.date);
  late TimeOfDay _time = TimeOfDay.fromDateTime(DateTime.now());

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _day = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New schedule event'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Event title'),
            ),
            const SizedBox(height: 12),
            if (!widget.tournament)
              SegmentedButton<EventType>(
                segments: [
                  for (final t in const [
                    EventType.practice,
                    EventType.game,
                    EventType.scrimmage,
                    EventType.other,
                  ])
                    ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {_type},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(DateFormat.yMMMEd().format(_day)),
              onTap: _pickDay,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(_time.format(context)),
              onTap: _pickTime,
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
      FilledButton(
        onPressed: _title.text.trim().isEmpty
            ? null
            : () => Navigator.pop<NewEvent>(context, (
                title: _title.text.trim(),
                type: _type,
                startsAt: DateTime(
                  _day.year,
                  _day.month,
                  _day.day,
                  _time.hour,
                  _time.minute,
                ),
              )),
        child: const Text('Add to schedule'),
      ),
    ],
  );
}

class SeasonStatsScreen extends StatelessWidget {
  const SeasonStatsScreen({super.key, required this.viewModel});

  final StatsViewModel viewModel;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Season stats')),
    body: ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => viewModel.loaded
          ? StatSheetTable(
              sheet: viewModel.seasonSheet,
              nameOf: viewModel.nameOf,
            )
          : const LoadingView(),
    ),
  );
}
