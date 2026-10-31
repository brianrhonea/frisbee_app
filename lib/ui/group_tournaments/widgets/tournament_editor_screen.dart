import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/team_event.dart';
import '../../../domain/models/team_post.dart';
import '../../../domain/tournament_engine/team_builder.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../teams/widgets/team_post_widgets.dart';
import '../view_models/tournament_editor_viewmodel.dart';
import 'tournament_widgets.dart';

/// Sets up a tournament: details and rules, players and teams, and the
/// schedule. Organizers only.
class TournamentEditorScreen extends StatefulWidget {
  const TournamentEditorScreen({super.key, required this.viewModel});

  final TournamentEditorViewModel viewModel;

  @override
  State<TournamentEditorScreen> createState() => _TournamentEditorScreenState();
}

class _TournamentEditorScreenState extends State<TournamentEditorScreen> {
  TournamentEditorViewModel get vm => widget.viewModel;
  late final _name = TextEditingController();
  bool _nameSynced = false;

  @override
  void initState() {
    super.initState();
    vm.save.addListener(_onSave);
    vm.publish.addListener(_onPublish);
    vm.addListener(_syncName);
  }

  @override
  void dispose() {
    vm.save.removeListener(_onSave);
    vm.publish.removeListener(_onPublish);
    vm.removeListener(_syncName);
    _name.dispose();
    super.dispose();
  }

  /// Fills the name field once loading (or picking an event) names it.
  void _syncName() {
    if (_name.text != vm.name && (!_nameSynced || _name.text.isEmpty)) {
      _name.text = vm.name;
      _nameSynced = vm.name.isNotEmpty;
    }
  }

  void _onSave() {
    final cmd = vm.save;
    if (vm.publish.running) return;
    switch (cmd.result) {
      case Ok():
        cmd.clearResult();
        showSnackBar(context, 'Saved');
      case Error():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  /// The schedule was never published before this publish.
  bool _firstPublish = false;

  Future<void> _onPublish() async {
    final cmd = vm.publish;
    switch (cmd.result) {
      case Ok<String>(:final value):
        cmd.clearResult();
        vm.save.clearResult();
        if (_firstPublish && vm.canAnnounce) await _offerPost();
        if (!mounted) return;
        context.pushReplacement(Routes.groupTournament(vm.groupId, value));
      case Error<String>():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  /// Suggests a feed post so people see the tournament and sign up.
  Future<void> _offerPost() async {
    final post = await confirmDialog(
      context,
      title: 'Tell the group?',
      message:
          'Post ${vm.name.trim()} to the group feed so people see it and '
          'sign up. You can edit the post first.',
      confirmLabel: 'Write post',
    );
    if (!post || !mounted) return;
    final draft = await showDialog<PostDraft>(
      context: context,
      builder: (_) => PostEditorDialog(
        initial: vm.announcement,
        suggested: true,
        pickImages: vm.pickImages,
        loadImage: (_) async => Result.error(Exception('No photo')),
      ),
    );
    if (draft == null) return;
    await vm.announce.execute(draft);
    if (!mounted) return;
    if (vm.announce.error) {
      showErrorSnackBar(context, vm.announce.result);
    } else {
      showSnackBar(context, 'Posted to the group feed');
    }
    vm.announce.clearResult();
  }

  Future<void> _publish() async {
    if (vm.wasPublished &&
        !await confirmDialog(
          context,
          title: 'Publish a new schedule?',
          message:
              'This replaces every game, including scores already '
              'entered.',
          confirmLabel: 'Replace schedule',
          destructive: true,
        )) {
      return;
    }
    _firstPublish = !vm.wasPublished;
    vm.publish.execute();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([vm, vm.load, vm.save, vm.publish]),
      builder: (context, _) {
        final busy = vm.save.running || vm.publish.running;
        return Scaffold(
          appBar: AppBar(
            title: Text(vm.isNew ? 'New tournament' : 'Tournament setup'),
            actions: [
              if (vm.load.completed)
                TextButton(
                  onPressed: busy || vm.saveProblem != null
                      ? null
                      : vm.save.execute,
                  child: const Text('Save'),
                ),
            ],
          ),
          body: switch (vm.load) {
            final l when l.running || l.result == null => const LoadingView(),
            final l when l.error => ErrorView(error: l.result),
            _ => ConstrainedContent(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                children: [
                  _Heading('Details'),
                  _Details(viewModel: vm, name: _name),
                  _Heading('Format, teams and rules'),
                  _Rules(viewModel: vm),
                  _Heading('Schedule'),
                  _SchedulePreview(viewModel: vm),
                  _Heading('Players'),
                  _Teams(viewModel: vm),
                ],
              ),
            ),
          },
          bottomNavigationBar: vm.load.completed
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            vm.problem ??
                                (vm.teamsChanged ? vm.saveProblem : null) ??
                                (vm.todo == null
                                    ? 'Ready to publish.'
                                    : '${vm.todo}. You can still publish '
                                          'and add players later.'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: busy || vm.problem != null
                              ? null
                              : _publish,
                          icon: vm.publish.running
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.publish),
                          label: Text(
                            vm.wasPublished
                                ? 'Republish schedule'
                                : 'Publish schedule',
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Details extends StatelessWidget {
  const _Details({required this.viewModel, required this.name});

  final TournamentEditorViewModel viewModel;
  final TextEditingController name;

  Future<DateTime?> _pickDateTime(
    BuildContext context,
    DateTime initial,
  ) async {
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 2),
    );
    if (day == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final s = vm.settings;
    final events = vm.tournamentEvents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: name,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Name'),
          textCapitalization: TextCapitalization.words,
          onChanged: vm.setName,
        ),
        DropdownButtonFormField<String?>(
          initialValue: vm.eventId,
          decoration: const InputDecoration(
            labelText: 'Tournament event',
            helperText: 'Players come from its RSVPs',
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('None')),
            for (final e in events)
              DropdownMenuItem(
                value: e.id,
                child: Text(
                  '${e.title} · ${DateFormat.MMMd().format(e.startsAt)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: vm.setEvent,
        ),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No upcoming Tournament events. Post one in Events so people '
              'can say whether they are coming.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.date_range_outlined),
          title: const Text('Dates'),
          subtitle: Text(tournamentDates(s)),
          onTap: () async {
            final range = await showDateRangePicker(
              context: context,
              initialDateRange: DateTimeRange(
                start: DateUtils.dateOnly(s.startsAt),
                end: DateUtils.dateOnly(s.days.last),
              ),
              firstDate: DateTime(s.startsAt.year - 1),
              lastDate: DateTime(s.startsAt.year + 2),
              helpText: 'First and last day of play',
            );
            if (range != null) vm.setDates(range.start, range.end);
          },
        ),
        for (final (i, day) in s.days.indexed)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 40),
            dense: true,
            leading: const Icon(Icons.schedule, size: 20),
            title: Text(
              s.days.length == 1
                  ? 'Start time'
                  : 'Day ${i + 1} · ${DateFormat('EEE, MMM d').format(day)}',
            ),
            trailing: Text(DateFormat.jm().format(day)),
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(day),
                helpText: s.days.length == 1
                    ? 'Start time'
                    : 'Day ${i + 1} starts',
              );
              if (t != null) {
                vm.setDayStart(i, hour: t.hour, minute: t.minute);
              }
            },
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Ideal end'),
          subtitle: Text(
            s.idealEndsAt == null ? 'Not set' : tournamentWhen(s.idealEndsAt!),
          ),
          trailing: s.idealEndsAt == null
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      vm.updateSettings(s.copyWith(idealEndsAt: () => null)),
                ),
          onTap: () async {
            final d = await _pickDateTime(
              context,
              s.idealEndsAt ?? s.days.last.add(const Duration(hours: 6)),
            );
            if (d != null) vm.updateSettings(s.copyWith(idealEndsAt: () => d));
          },
        ),
      ],
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules({required this.viewModel});

  final TournamentEditorViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final s = vm.settings;
    void set(TournamentSettings next) => vm.updateSettings(next);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<TournamentFormat>(
          groupValue: s.format,
          onChanged: (f) => set(s.copyWith(format: f)),
          child: Column(
            children: [
              for (final f in TournamentFormat.values)
                RadioListTile<TournamentFormat>(
                  contentPadding: EdgeInsets.zero,
                  value: f,
                  title: Text(f.label),
                  subtitle: Text(f.summary),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Players on the field',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final n in TournamentSettings.fieldSizes)
              ChoiceChip(
                label: Text('${n}v$n'),
                selected: s.playersOnField == n,
                onSelected: (_) => set(s.copyWith(playersOnField: n)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _Stepper(
          label: 'Teams',
          value: vm.teams.length,
          min: 2,
          max: TournamentSettings.maxTeams,
          onChanged: vm.setTeamCount,
        ),
        if (s.format == TournamentFormat.poolsSingleElim)
          _Stepper(
            label: 'Pools',
            value: s.poolCount,
            min: 1,
            max: (vm.teams.length ~/ 2).clamp(1, 8),
            onChanged: (v) => set(s.copyWith(poolCount: v)),
          ),
        _Stepper(
          label: 'Game length',
          value: s.gameMinutes,
          min: 10,
          max: 120,
          step: 5,
          unit: 'min',
          onChanged: (v) => set(s.copyWith(gameMinutes: v)),
        ),
        _Stepper(
          label: 'Break between games',
          value: s.breakMinutes,
          min: 0,
          max: 60,
          step: 5,
          unit: 'min',
          onChanged: (v) => set(s.copyWith(breakMinutes: v)),
        ),
        _Stepper(
          label: 'Game to',
          value: s.scoreCap,
          min: 3,
          max: 21,
          unit: 'points',
          onChanged: (v) => set(s.copyWith(scoreCap: v)),
        ),
        _Stepper(
          label: 'Timeouts per half',
          value: s.timeoutsPerHalf,
          min: 0,
          max: 4,
          onChanged: (v) => set(s.copyWith(timeoutsPerHalf: v)),
        ),
        _Stepper(
          label: 'Fields',
          value: s.fields,
          min: 1,
          max: 12,
          onChanged: (v) => set(s.copyWith(fields: v)),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.unit,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String? unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Less',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value - step >= min ? () => onChanged(value - step) : null,
        ),
        SizedBox(
          width: 72,
          child: Text(
            unit == null ? '$value' : '$value $unit',
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          tooltip: 'More',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value + step <= max ? () => onChanged(value + step) : null,
        ),
      ],
    ),
  );
}

class _Teams extends StatelessWidget {
  const _Teams({required this.viewModel});

  final TournamentEditorViewModel viewModel;

  Future<void> _assign(BuildContext context) async {
    final vm = viewModel;
    final players = vm.allPlayers.length;
    final teams = vm.teams.length;
    final each = players ~/ teams;
    final sizes = players % teams == 0 ? '$each' : '$each–${each + 1}';
    if (!await confirmDialog(
      context,
      title: 'Assign teams?',
      message:
          'All $players players are dealt at random into the $teams teams '
          '($sizes each), replacing who is on them now. Each team gets a '
          'random captain.',
      confirmLabel: 'Assign teams',
    )) {
      return;
    }
    vm.assignTeams();
  }

  Future<void> _addMember(BuildContext context) async {
    final vm = viewModel;
    final others = vm.otherMembers;
    final picked = await showDialog<TournamentPlayer>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add a member'),
        children: [
          if (others.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Every member is already in.'),
            ),
          for (final p in others)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, p),
              child: Text(p.name),
            ),
        ],
      ),
    );
    if (picked != null) vm.addToBench(picked);
  }

  Future<void> _rename(BuildContext context, TournamentTeam team) async {
    final c = TextEditingController(text: team.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Team name'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    c.dispose();
    if (name != null) viewModel.renameTeam(team.id, name);
  }

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final going = vm.rsvps(RsvpStatus.going);
    final maybe = vm.rsvps(RsvpStatus.maybe);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (vm.event != null)
          Card.outlined(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.how_to_reg_outlined),
              title: Text(
                '${going.length} attending · ${maybe.length} planning to attend',
              ),
              subtitle: const Text('From the event RSVPs'),
              trailing: FilledButton.tonal(
                onPressed: going.isEmpty && maybe.isEmpty
                    ? null
                    : () {
                        final n = vm.importRsvps();
                        showSnackBar(
                          context,
                          n == 0
                              ? 'Everyone is already in'
                              : 'Added $n player${n == 1 ? '' : 's'}',
                        );
                      },
                child: const Text('Import'),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _addMember(context),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add member'),
            ),
            FilledButton.icon(
              onPressed: vm.allPlayers.isEmpty || vm.teams.length < 2
                  ? null
                  : () => _assign(context),
              icon: const Icon(Icons.shuffle),
              label: const Text('Assign teams'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Players can be added before or after the schedule is published. '
          'Tap a player to move them or make them captain.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (vm.bench.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Not on a team (${vm.bench.length})',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final p in vm.bench)
                _PlayerChip(viewModel: vm, player: p, teamId: null),
            ],
          ),
        ],
        const SizedBox(height: 16),
        for (final t in vm.teams)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${t.name} (${t.playerIds.length})',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Rename',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _rename(context, t),
                      ),
                      IconButton(
                        tooltip: 'Remove team',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: vm.teams.length <= 2
                            ? null
                            : () => vm.removeTeam(t.id),
                      ),
                    ],
                  ),
                  if (t.playerIds.isEmpty)
                    Text('No players yet.', style: theme.textTheme.bodySmall),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final uid in t.playerIds)
                        _PlayerChip(
                          viewModel: vm,
                          player: (uid: uid, name: t.nameOf(uid)),
                          teamId: t.id,
                          captain: t.captainId == uid,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A player; tap to move them, make them captain or take them out.
class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.viewModel,
    required this.player,
    required this.teamId,
    this.captain = false,
  });

  final TournamentEditorViewModel viewModel;
  final TournamentPlayer player;
  final String? teamId;
  final bool captain;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return PopupMenuButton<String>(
      tooltip: 'Move ${player.name}',
      onSelected: (action) => switch (action) {
        'captain' => vm.setCaptain(teamId!, player.uid),
        'bench' => vm.movePlayerTo(player, null),
        'remove' => vm.removeFromBench(player.uid),
        final id => vm.movePlayerTo(player, id),
      },
      itemBuilder: (_) => [
        if (teamId != null && !captain)
          const PopupMenuItem(value: 'captain', child: Text('Make captain')),
        for (final t in vm.teams)
          if (t.id != teamId)
            PopupMenuItem(value: t.id, child: Text('Move to ${t.name}')),
        if (teamId != null)
          const PopupMenuItem(value: 'bench', child: Text('Take off team'))
        else
          const PopupMenuItem(value: 'remove', child: Text('Leave out')),
      ],
      child: Chip(
        avatar: captain ? const Icon(Icons.star, size: 18) : null,
        label: Text(captain ? '${player.name} (C)' : player.name),
      ),
    );
  }
}

class _SchedulePreview extends StatelessWidget {
  const _SchedulePreview({required this.viewModel});

  final TournamentEditorViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final plan = vm.plan;
    final names = {for (final t in vm.teams) t.id: t.name};
    final numbers = {
      for (final g in plan?.games ?? const <GroupGame>[]) g.id: g.order + 1,
    };
    String side(GroupGame g, {required bool a}) {
      final team = a ? g.teamA : g.teamB;
      if (team != null) return names[team] ?? 'TBD';
      return switch (a ? g.sourceA : g.sourceB) {
        WinnerOf(:final gameId) => 'Winner of game ${numbers[gameId]}',
        LoserOf(:final gameId) => 'Loser of game ${numbers[gameId]}',
        PoolRank(:final poolId, :final rank) => 'Pool $poolId #$rank',
        null => 'TBD',
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: vm.teams.length < 2 ? null : vm.previewSchedule,
            icon: const Icon(Icons.calendar_view_day_outlined),
            label: Text(plan == null ? 'Preview schedule' : 'Refresh preview'),
          ),
        ),
        if (vm.planError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              errorMessage(vm.planError),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (plan != null) ...[
          const SizedBox(height: 8),
          Text(
            plan.days.length == 1
                ? '${plan.games.length} games · ends about '
                      '${DateFormat.jm().format(plan.endsAt)}'
                : '${plan.games.length} games over ${plan.days.length} days',
            style: theme.textTheme.bodyMedium,
          ),
          if (vm.overrunMinutes > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Runs ${vm.overrunMinutes} min past the ideal end. '
                      'Add fields, shorten games or use fewer teams.',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          for (final g in plan.games) ...[
            if (plan.days.length > 1)
              for (final (i, day) in plan.days.indexed)
                if (day.games > 0 &&
                    g.order ==
                        plan.days
                            .take(i)
                            .fold<int>(0, (sum, d) => sum + d.games))
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      'Day ${i + 1} · '
                      '${DateFormat('EEE, MMM d').format(day.startsAt)} · '
                      '${day.games} games, '
                      '${DateFormat.jm().format(day.startsAt)}–'
                      '${DateFormat.jm().format(day.endsAt)}',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Game ${g.order + 1} · ${gameTime(g.startsAt)} · Field ${g.field} · '
                '${g.label}: ${side(g, a: true)} vs ${side(g, a: false)}'
                '${g.ifNeeded ? ' (if needed)' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ],
    );
  }
}
