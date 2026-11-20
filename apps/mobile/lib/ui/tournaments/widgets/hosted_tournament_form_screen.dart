import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/hosted_tournament_form_viewmodel.dart';
import 'event_format_section.dart';

const _currencies = ['USD', 'CAD', 'EUR', 'GBP', 'AUD', 'MXN'];

/// Hosting a tournament, or editing its details.

/// Under the location and About (the website says the same): published
/// events are on the public website.
const publicDetailsHint =
    "The location and About are public: anyone can see them once it's "
    'published, even without an account.';

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
  final _teamFee = TextEditingController();
  bool _filled = false;

  @override
  void initState() {
    super.initState();
    vm.save.addListener(_onSave);
  }

  @override
  void dispose() {
    vm.save.removeListener(_onSave);
    for (final c in [
      _name,
      _location,
      _description,
      _fee,
      _instructions,
      _teamFee,
    ]) {
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
    _teamFee.text = vm.teamFeeAmount;
  }

  /// New events pick a type once: a tournament or a league (see also
  /// [_entryPicker]). An existing one just shows what it is.
  Widget _typePicker(ThemeData theme) {
    if (!vm.isNew) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(spacing: 8, children: [Chip(label: Text(vm.kind.label))]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SegmentedButton<HostedKind>(
        segments: [
          for (final k in HostedKind.values)
            ButtonSegment(value: k, label: Text(k.label)),
        ],
        selected: {vm.kind},
        onSelectionChanged: (s) => vm.setKind(s.first),
      ),
    );
  }

  /// Whether teams apply or players sign up (players on a tournament make
  /// it a hat tournament), and how player teams are made.
  Widget _entryPicker(ThemeData theme) {
    final c = AppColors.of(context);
    if (!vm.isNew) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(
          spacing: 8,
          children: [
            Chip(
              label: Text(vm.takesPlayers ? 'Players sign up' : 'Teams apply'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(switch ((vm.kind, vm.entryType)) {
            (HostedKind.tournament, TournamentEntryType.teams) =>
              'A weekend tournament for teams that apply.',
            (HostedKind.tournament, TournamentEntryType.players) =>
              'A hat tournament: players sign up on their own and are '
                  'drafted onto teams.',
            (HostedKind.league, TournamentEntryType.teams) =>
              'A weekly league for teams that apply, with a minimum roster.',
            (HostedKind.league, TournamentEntryType.players) =>
              'A weekly league: players sign up on their own and are '
                  'drafted onto teams, which become real teams with chat '
                  'and a roster.',
          }, style: TextStyle(fontSize: 12.5, color: c.muted)),
        ),
        if (vm.entryType == TournamentEntryType.players) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Teams can also reserve a spot'),
            subtitle: const Text(
              'A captain pays the team fee, names their team and invites '
              'their own players. Everyone else signs up on their own and '
              'is drafted into the remaining spots.',
            ),
            value: vm.teamEntry,
            onChanged: vm.setTeamEntry,
          ),
          const SizedBox(height: 4),
          SegmentedButton<DraftMode>(
            segments: [
              for (final m in DraftMode.values)
                ButtonSegment(value: m, label: Text(m.label)),
            ],
            selected: {vm.draftMode},
            onSelectionChanged: (s) => vm.setDraftMode(s.first),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              vm.draftMode == DraftMode.captains
                  ? 'You choose the captains, who take turns picking '
                        'players in a live draft. Each captain owns their team.'
                  : 'The app deals teams evened out by skill and gender.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
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
        final c = AppColors.of(context);
        final host = vm.host;
        final f = DateFormat('EEE, MMM d, y');
        final end = vm.endsOn;
        final small = TextStyle(fontSize: 12.5, color: c.muted);
        Widget dateField({
          required String label,
          required String value,
          required IconData icon,
          required VoidCallback onTap,
        }) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(controlRadius),
            onTap: onTap,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                suffixIcon: Icon(icon, size: 20),
              ),
              child: Text(value),
            ),
          ),
        );
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vm.isNew
                      ? 'Host ${vm.isLeague ? 'a league' : 'a tournament'}'
                      : 'Edit ${vm.isLeague ? 'league' : 'tournament'}',
                ),
                if (host != null)
                  Text(
                    'Hosted by ${host.name}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: c.muted,
                    ),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              color: c.card,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (vm.isNew)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'It starts as a draft only your managers see. Open '
                          'registration on its page when you are ready for '
                          '${vm.takesPlayers ? 'signups' : 'teams'}.',
                          textAlign: TextAlign.center,
                          style: small,
                        ),
                      ),
                    FilledButton(
                      onPressed: vm.save.running || vm.problem != null
                          ? null
                          : vm.save.execute,
                      child: Text(vm.isNew ? 'Create' : 'Save'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (host != null && !vm.canHost)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Only members who manage events can host.',
                      style: TextStyle(fontSize: 13, color: c.highlightInk),
                    ),
                  ),
                ..._formStep(
                  c,
                  number: 1,
                  title: 'Details',
                  children: [
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
                    const SizedBox(height: 4),
                    TextField(
                      controller: _description,
                      maxLength: 2000,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'About',
                        hintText: 'Format, parking, food, contacts…',
                        alignLabelWithHint: true,
                        helperText: publicDetailsHint,
                        helperMaxLines: 3,
                      ),
                      onChanged: (v) => vm.description = v,
                    ),
                  ],
                ),
                ..._formStep(
                  c,
                  number: 2,
                  title: 'When & where',
                  children: [
                    if (vm.isLeague) ...[
                      dateField(
                        label: 'First night',
                        icon: Icons.calendar_month_outlined,
                        value: end == null
                            ? f.format(vm.startsOn)
                            : '${f.format(vm.startsOn)} – ${f.format(end)}',
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
                      const SizedBox(height: 8),
                    ] else
                      dateField(
                        label: 'Dates',
                        icon: Icons.date_range_outlined,
                        value: end == null
                            ? f.format(vm.startsOn)
                            : '${f.format(vm.startsOn)} – ${f.format(end)}',
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
                          if (range != null) {
                            vm.setDates(range.start, range.end);
                          }
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
                  ],
                ),
                ..._formStep(
                  c,
                  number: 3,
                  title: 'Who can play',
                  children: [
                    _entryPicker(theme),
                    SegmentedButton<TournamentVisibility>(
                      segments: [
                        for (final v in TournamentVisibility.values)
                          ButtonSegment(value: v, label: Text(v.label)),
                      ],
                      selected: {vm.visibility},
                      onSelectionChanged: (s) => vm.setVisibility(s.first),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${vm.visibility.summary}. The page, schedule, '
                        'results and news are public either way.',
                        style: small,
                      ),
                    ),
                  ],
                ),
                ..._formStep(
                  c,
                  number: 4,
                  title: 'Format & divisions',
                  children: EventFormatSection(viewModel: vm).parts(context),
                ),
                ..._formStep(
                  c,
                  number: 5,
                  title: 'Fees',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(vm.feeName),
                      subtitle: Text(
                        vm.teamEntry
                            ? 'What each player who signs up pays, and what '
                                  'a team pays to reserve a spot. They pay '
                                  'you directly; you mark them paid.'
                            : vm.takesPlayers
                            ? 'What each player pays to sign up. Players pay '
                                  'you directly; you mark them paid.'
                            : 'What each team pays to hold its spot. Teams '
                                  'pay you directly; you mark them paid.',
                      ),
                      value: vm.hasFee,
                      onChanged: vm.setHasFee,
                    ),
                    if (vm.hasFee) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _fee,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: vm.teamEntry
                                    ? 'Per player'
                                    : 'Amount',
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
                              isExpanded: true,
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
                      if (vm.teamEntry) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _teamFee,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Per team spot',
                            hintText: '300',
                            errorText:
                                _teamFee.text.isNotEmpty &&
                                    vm.teamFeeCents == null
                                ? 'Enter an amount'
                                : null,
                          ),
                          onChanged: (v) {
                            vm.teamFeeAmount = v;
                            setState(() {});
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
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
                            vm.setFeeDue(
                              DateTime(d.year, d.month, d.day, 23, 59),
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One numbered part of the form, as a card ("2  When & where") cut
/// into rows, so the list lays out (and scrolls to) each field.
List<Widget> _formStep(
  AppColors c, {
  required int number,
  required String title,
  required List<Widget> children,
}) {
  const radius = Radius.circular(cardRadius);
  Widget slice(Widget child, {bool top = false, bool bottom = false}) =>
      Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.vertical(
            top: top ? radius : Radius.zero,
            bottom: bottom ? radius : Radius.zero,
          ),
        ),
        padding: EdgeInsets.fromLTRB(16, top ? 14 : 0, 16, bottom ? 16 : 0),
        child: child,
      );
  return [
    slice(
      top: true,
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.chipOn,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$number',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: c.onChipOn,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: c.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    for (final child in children) slice(child),
    slice(bottom: true, const SizedBox.shrink()),
    const SizedBox(height: 12),
  ];
}
