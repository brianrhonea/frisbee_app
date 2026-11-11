import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/hosted_tournament_form_viewmodel.dart';

const _currencies = ['USD', 'CAD', 'EUR', 'GBP', 'AUD', 'MXN'];

/// Hosting a tournament, or editing its details.
class HostedTournamentFormScreen extends StatefulWidget {
  const HostedTournamentFormScreen({super.key, required this.viewModel});

  final HostedTournamentFormViewModel viewModel;

  @override
  State<HostedTournamentFormScreen> createState() =>
      _HostedTournamentFormScreenState();
}

class _HostedTournamentFormScreenState
    extends State<HostedTournamentFormScreen> {
  HostedTournamentFormViewModel get vm => widget.viewModel;

  final _name = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _fee = TextEditingController();
  final _instructions = TextEditingController();
  bool _filled = false;

  @override
  void initState() {
    super.initState();
    vm.save.addListener(_onSave);
  }

  @override
  void dispose() {
    vm.save.removeListener(_onSave);
    for (final c in [_name, _location, _description, _fee, _instructions]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onSave() {
    final r = vm.save.result;
    if (r is Ok<String>) {
      vm.save.clearResult();
      if (vm.isNew) {
        context.pushReplacement(Routes.tournament(r.value));
      } else {
        context.pop();
      }
    } else if (vm.save.error) {
      showErrorSnackBar(context, r);
      vm.save.clearResult();
    }
  }

  /// Copies an existing tournament into the fields once it loads.
  void _fill() {
    if (_filled || (!vm.isNew && vm.existing == null)) return;
    _filled = true;
    _name.text = vm.name;
    _location.text = vm.location;
    _description.text = vm.description;
    _fee.text = vm.feeAmount;
    _instructions.text = vm.feeInstructions;
  }

  /// New events pick a type once: a tournament or a league, and whether
  /// teams apply or players sign up (players on a tournament make it a hat
  /// tournament). An existing one just shows what it is.
  Widget _typePicker(ThemeData theme) {
    if (!vm.isNew) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          spacing: 8,
          children: [
            Chip(label: Text(vm.kind.label)),
            Chip(
              label: Text(vm.takesPlayers ? 'Players sign up' : 'Teams apply'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<HostedKind>(
          segments: [
            for (final k in HostedKind.values)
              ButtonSegment(value: k, label: Text(k.label)),
          ],
          selected: {vm.kind},
          onSelectionChanged: (s) => vm.setKind(s.first),
        ),
        const SizedBox(height: 8),
        SegmentedButton<TournamentEntryType>(
          segments: const [
            ButtonSegment(
              value: TournamentEntryType.teams,
              label: Text('Teams apply'),
            ),
            ButtonSegment(
              value: TournamentEntryType.players,
              label: Text('Players sign up'),
            ),
          ],
          selected: {vm.entryType},
          onSelectionChanged: (s) => vm.setEntryType(s.first),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(switch ((vm.kind, vm.entryType)) {
            (HostedKind.tournament, TournamentEntryType.teams) =>
              'A weekend tournament for teams that apply.',
            (HostedKind.tournament, TournamentEntryType.players) =>
              'A hat tournament: players sign up and you draw balanced '
                  'teams from them.',
            (HostedKind.league, TournamentEntryType.teams) =>
              'A weekly league for teams that apply, with a minimum roster.',
            (HostedKind.league, TournamentEntryType.players) =>
              'A weekly league: players sign up and you draw balanced '
                  'teams, which become real teams with chat and a roster.',
          }, style: theme.textTheme.bodySmall),
        ),
        if (vm.entryType == TournamentEntryType.players) ...[
          SegmentedButton<DraftMode>(
            segments: [
              for (final m in DraftMode.values)
                ButtonSegment(value: m, label: Text(m.label)),
            ],
            selected: {vm.draftMode},
            onSelectionChanged: (s) => vm.setDraftMode(s.first),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              vm.draftMode == DraftMode.captains
                  ? 'You choose the captains, who take turns picking '
                        'players in a live draft. Each captain owns their team.'
                  : 'The app deals teams evened out by skill and gender.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }

  /// How long the season runs, and its playoffs.
  List<Widget> _seasonSettings(ThemeData theme) {
    final s = vm.season;
    Widget chips<T>(
      String label,
      List<T> options,
      T value,
      String Function(T) text,
      void Function(T) onChanged,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final o in options)
                ChoiceChip(
                  label: Text(text(o)),
                  selected: o == value,
                  onSelected: (_) => onChanged(o),
                ),
            ],
          ),
        ],
      ),
    );
    return [
      const SizedBox(height: 8),
      Row(
        children: [
          Text('Season', style: theme.textTheme.titleSmall),
          const Spacer(),
          IconButton(
            tooltip: 'Fewer weeks',
            onPressed: s.weeks <= 1
                ? null
                : () => vm.setSeason(s.copyWith(weeks: s.weeks - 1)),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('${s.weeks} weeks', style: theme.textTheme.titleMedium),
          IconButton(
            tooltip: 'More weeks',
            onPressed: s.weeks >= LeagueSeason.maxWeeks
                ? null
                : () => vm.setSeason(s.copyWith(weeks: s.weeks + 1)),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Skipped weeks', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final d in s.skipDates)
                  InputChip(
                    label: Text(DateFormat.MMMd().format(d)),
                    onDeleted: () => vm.setSeason(
                      s.copyWith(skipDates: [...s.skipDates]..remove(d)),
                    ),
                  ),
                if (s.skipDates.length < LeagueSeason.maxSkipDates)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Skip a week'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: vm.startsOn,
                        firstDate: vm.startsOn,
                        lastDate: DateTime(vm.startsOn.year + 2),
                        helpText: 'A night with no games',
                      );
                      if (d == null) return;
                      final day = DateTime(d.year, d.month, d.day);
                      if (!s.skipDates.contains(day)) {
                        vm.setSeason(
                          s.copyWith(skipDates: [...s.skipDates, day]),
                        );
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
      chips<int>(
        'Games a night',
        const [1, 2],
        s.gamesPerNight,
        (n) => '$n',
        (n) => vm.setSeason(s.copyWith(gamesPerNight: n)),
      ),
      chips<int>(
        'Playoffs',
        LeagueSeason.playoffSizes,
        s.playoffTeams,
        (n) => n == 0 ? 'None' : 'Top $n',
        (n) => vm.setSeason(
          s.copyWith(
            playoffTeams: n,
            playoffWeeks: n == 0
                ? 0
                : (s.playoffWeeks == 0 ? 1 : s.playoffWeeks),
          ),
        ),
      ),
      if (s.playoffTeams > 0)
        chips<int>(
          'Playoff weeks (the last weeks of the season)',
          [for (var w = 1; w <= LeagueSeason.maxPlayoffWeeks; w++) w],
          s.playoffWeeks,
          (n) => '$n',
          (n) => vm.setSeason(s.copyWith(playoffWeeks: n)),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Each division sets its own game night, field size and roster '
          'minimum on the event page.',
          style: theme.textTheme.bodySmall,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([vm, vm.save]),
      builder: (context, _) {
        if (!vm.loaded) {
          return Scaffold(appBar: AppBar(), body: const LoadingView());
        }
        if (vm.error != null) {
          return Scaffold(
            appBar: AppBar(),
            body: ErrorView(error: vm.error),
          );
        }
        _fill();
        final theme = Theme.of(context);
        final host = vm.host;
        final f = DateFormat('EEE, MMM d, y');
        final end = vm.endsOn;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              vm.isNew
                  ? 'Host ${vm.isLeague ? 'a league' : 'a tournament'}'
                  : 'Edit ${vm.isLeague ? 'league' : 'tournament'}',
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: vm.save.running || vm.problem != null
                      ? null
                      : vm.save.execute,
                  child: Text(vm.isNew ? 'Create' : 'Save'),
                ),
              ),
            ],
          ),
          body: ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
              children: [
                if (host != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.groups_outlined),
                    title: Text('Hosted by ${host.name}'),
                    subtitle: vm.canHost
                        ? null
                        : const Text(
                            'Only members who manage events can host.',
                          ),
                  ),
                _typePicker(theme),
                TextField(
                  controller: _name,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Spring Fling',
                  ),
                  onChanged: (v) {
                    vm.name = v;
                    setState(() {});
                  },
                ),
                if (vm.isLeague) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: const Text('First night'),
                    subtitle: Text(
                      end == null
                          ? f.format(vm.startsOn)
                          : '${f.format(vm.startsOn)} – ${f.format(end)}',
                    ),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: vm.startsOn,
                        firstDate: DateTime(vm.startsOn.year - 1),
                        lastDate: DateTime(vm.startsOn.year + 2),
                        helpText: 'First night of the season',
                      );
                      if (d != null) vm.setFirstNight(d);
                    },
                  ),
                  ..._seasonSettings(theme),
                ] else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.date_range_outlined),
                    title: const Text('Dates'),
                    subtitle: Text(
                      end == null
                          ? f.format(vm.startsOn)
                          : '${f.format(vm.startsOn)} – ${f.format(end)}',
                    ),
                    onTap: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        initialDateRange: DateTimeRange(
                          start: vm.startsOn,
                          end: end ?? vm.startsOn,
                        ),
                        firstDate: DateTime(vm.startsOn.year - 1),
                        lastDate: DateTime(vm.startsOn.year + 2),
                        helpText: 'First and last day',
                      );
                      if (range != null) vm.setDates(range.start, range.end);
                    },
                  ),
                TextField(
                  controller: _location,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    hintText: 'Fields or park, city',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  onChanged: (v) => vm.location = v,
                ),
                TextField(
                  controller: _description,
                  maxLength: 2000,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'About',
                    hintText: 'Format, parking, food, contacts…',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (v) => vm.description = v,
                ),
                const SizedBox(height: 16),
                Text('Who can play', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<TournamentVisibility>(
                  segments: [
                    for (final v in TournamentVisibility.values)
                      ButtonSegment(value: v, label: Text(v.label)),
                  ],
                  selected: {vm.visibility},
                  onSelectionChanged: (s) => vm.setVisibility(s.first),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${vm.visibility.summary}. The page, schedule, results '
                    'and news are public either way.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(vm.feeName),
                  subtitle: Text(
                    vm.takesPlayers
                        ? 'What each player pays to sign up. Players pay '
                              'you directly; you mark them paid.'
                        : 'What each team pays to hold its spot. Teams pay '
                              'you directly; you mark them paid.',
                  ),
                  value: vm.hasFee,
                  onChanged: vm.setHasFee,
                ),
                if (vm.hasFee) ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _fee,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Amount',
                            hintText: '250',
                            errorText:
                                _fee.text.isNotEmpty && vm.feeCents == null
                                ? 'Enter an amount'
                                : null,
                          ),
                          onChanged: (v) {
                            vm.feeAmount = v;
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: vm.currency,
                          decoration: const InputDecoration(
                            labelText: 'Currency',
                          ),
                          items: [
                            for (final c in {..._currencies, vm.currency})
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: (v) =>
                              v == null ? null : vm.setCurrency(v),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: _instructions,
                    maxLength: 500,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'How to pay',
                      hintText:
                          'e.g. Venmo @club-treasurer with your team name',
                    ),
                    onChanged: (v) => vm.feeInstructions = v,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_available_outlined),
                    title: const Text('Due'),
                    subtitle: Text(
                      vm.feeDue == null
                          ? 'No due date'
                          : DateFormat.yMMMd().format(vm.feeDue!),
                    ),
                    trailing: vm.feeDue == null
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () => vm.setFeeDue(null),
                          ),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate:
                            vm.feeDue ??
                            vm.startsOn.subtract(const Duration(days: 14)),
                        firstDate: DateTime(vm.startsOn.year - 1),
                        lastDate: vm.endsOn ?? vm.startsOn,
                      );
                      if (d != null) {
                        vm.setFeeDue(DateTime(d.year, d.month, d.day, 23, 59));
                      }
                    },
                  ),
                ],
                if (vm.isNew)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      "It starts as a draft only your managers see. Add "
                      'divisions on its page, then publish it to open '
                      '${vm.takesPlayers ? 'signups' : 'registration'}.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
