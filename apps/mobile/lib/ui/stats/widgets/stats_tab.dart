import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/stats.dart';
import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/scoreboard.dart';
import '../../core/ui/status_views.dart';
import '../view_models/stats_viewmodel.dart';
import 'game_screen.dart' show confirmDeleteGame;
import 'game_to_field.dart';
import 'stat_sheet.dart';
import 'stats_glossary.dart';
import '../../core/ui/time_picker.dart';

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
              title: const Text('Track a tournament'),
              subtitle: const Text(
                'Stats for every game you play at one tournament',
              ),
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
      final empty = TextStyle(
        fontSize: 13.5,
        color: AppColors.of(context).muted,
      );
      final standalone = vm.standaloneGames;
      return Scaffold(
        floatingActionButton: vm.canEdit
            ? FloatingActionButton.extended(
                heroTag: 'new-stats',
                onPressed: () => _add(context),
                icon: const Icon(Icons.add),
                label: const Text('Track stats'),
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
                SectionHeader('Tournament stats'),
                if (vm.tournaments.isEmpty)
                  Text('No tournaments tracked yet.', style: empty)
                else
                  for (final t in vm.tournaments)
                    _TournamentFolder(
                      tournament: t,
                      games: vm.gamesIn(t.id),
                      onOpen: () =>
                          context.push(Routes.statsTournament(vm.teamId, t.id)),
                      onDelete: vm.canDelete
                          ? () async {
                              if (await confirmDeleteTournament(
                                context,
                                t,
                                vm.gamesIn(t.id).length,
                              )) {
                                if (!context.mounted) return;
                                await runDelete(
                                  context,
                                  vm.deleteTournament,
                                  () => vm.deleteTournament.execute(t.id),
                                );
                              }
                            }
                          : null,
                    ),
                const SizedBox(height: 20),
                SectionHeader('Games'),
                if (standalone.isEmpty)
                  Text('No standalone games yet.', style: empty)
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (i, g) in standalone.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          GameRow(
                            game: g,
                            onTap: () =>
                                context.push(Routes.statsGame(vm.teamId, g.id)),
                            onDelete: vm.canDelete
                                ? () async {
                                    if (await confirmDeleteGame(context, g)) {
                                      if (!context.mounted) return;
                                      await runDelete(
                                        context,
                                        vm.deleteGame,
                                        () => vm.deleteGame.execute(g.id),
                                      );
                                    }
                                  }
                                : null,
                          ),
                        ],
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

  static String _pct(double? v) => v == null ? '–' : '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    final sheet = vm.seasonSheet;
    final leaders = sheet.ranked.take(3).toList();
    Widget number(String value, String label, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScoreText(value, size: 32, color: color),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Season',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: c.muted,
                    ),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: c.accent),
                  onPressed: () => context.push(Routes.seasonStats(vm.teamId)),
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('Season stats'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                children: [
                  number('${vm.wins}–${vm.losses}', 'Record'),
                  number(_pct(sheet.team.oEfficiency), 'O efficiency'),
                  number(_pct(sheet.team.breakRate), 'Break rate'),
                ],
              ),
            ),
            if (leaders.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Top +/-',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 4),
              for (final (i, p) in leaders.indexed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 6, 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: ScoreText('${i + 1}', size: 17, color: c.muted),
                      ),
                      Expanded(
                        child: Text(
                          vm.nameOf(p.playerId),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                      ),
                      Text(
                        '${p.goals}G ${p.assists}A '
                        '${p.handBlocks + p.breakups}D',
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                      const SizedBox(width: 12),
                      ScoreText('+${p.plusMinus}', size: 20, color: c.accent),
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

/// Asks before deleting tournament [t] and its [games] games.
Future<bool> confirmDeleteTournament(
  BuildContext context,
  StatsTournament t,
  int games,
) => confirmDialog(
  context,
  title: 'Delete ${t.name}?',
  message:
      'This permanently deletes the tournament, its roster and lines, and '
      '${games == 1 ? 'its game' : 'all $games of its games'} with every '
      'stat in them.',
  confirmLabel: 'Delete',
  destructive: true,
);

/// Runs a delete [command] and reports a failure.
Future<void> runDelete(
  BuildContext context,
  Command<void> command,
  Future<void> Function() execute,
) async {
  await execute();
  if (command.error && context.mounted) {
    showErrorSnackBar(context, command.result);
  }
  command.clearResult();
}

/// The menu on a game or tournament row; for admins.
class _DeleteMenu extends StatelessWidget {
  const _DeleteMenu({required this.label, required this.onDelete});

  final String label;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => PopupMenuButton<bool>(
    tooltip: 'More',
    onSelected: (_) => onDelete(),
    itemBuilder: (_) => [
      PopupMenuItem<bool>(
        value: true,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.delete_outline,
            color: AppColors.of(context).ink2,
          ),
          title: Text(label),
        ),
      ),
    ],
  );
}

class _TournamentFolder extends StatelessWidget {
  const _TournamentFolder({
    required this.tournament,
    required this.games,
    required this.onOpen,
    this.onDelete,
  });

  final StatsTournament tournament;
  final List<StatsGame> games;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final wins = games.where((g) => g.won == true).length;
    final losses = games.where((g) => g.won == false).length;
    final c = AppColors.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onOpen,
        contentPadding: const EdgeInsets.only(left: 14, right: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.accentSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.emoji_events_outlined, color: c.accentInk),
        ),
        title: Text(
          t.name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        subtitle: Text(
          [
            DateFormat.MMMd().format(t.startDate),
            '${games.length} game${games.length == 1 ? '' : 's'}',
            if (wins + losses > 0) '$wins–$losses',
          ].join(' · '),
          style: TextStyle(fontSize: 12.5, color: c.muted),
        ),
        trailing: onDelete == null
            ? const Icon(Icons.chevron_right)
            : _DeleteMenu(label: 'Delete tournament', onDelete: onDelete!),
      ),
    );
  }
}

/// One game "file": opponent, date, score and result. [onDelete] adds a
/// menu to delete it.
class GameRow extends StatelessWidget {
  const GameRow({
    super.key,
    required this.game,
    required this.onTap,
    this.onDelete,
  });

  final StatsGame game;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = game;
    final live = g.won == null && !g.finished;
    // A win is turf, a loss or tie plain; red only for a game still live.
    final (badge, bg, fg) = switch (g.won) {
      true => ('W', c.accentSoft, c.accentInk),
      false => ('L', c.field, c.ink2),
      null when g.finished => ('T', c.field, c.ink2),
      null => ('LIVE', c.liveSoft, c.liveInk),
    };
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.only(left: 14, right: 4),
      title: Text(
        'vs ${g.opponent}',
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: c.ink,
        ),
      ),
      subtitle: Text(
        DateFormat.MMMd().add_jm().format(g.date),
        style: TextStyle(fontSize: 12.5, color: c.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScoreText('${g.ourScore}–${g.theirScore}', size: 22),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (live) ...[const LiveDot(size: 6), const SizedBox(width: 4)],
                Text(
                  badge,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            _DeleteMenu(label: 'Delete game', onDelete: onDelete!),
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
      title: Text(widget.tournament ? 'Track a tournament' : 'New game'),
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
    final t = await showTypedTimePicker(context: context, initialTime: _time);
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
