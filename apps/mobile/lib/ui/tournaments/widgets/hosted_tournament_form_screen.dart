import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../payments/widgets/payment_widgets.dart';
import '../view_models/hosted_tournament_form_viewmodel.dart';
import 'director_section.dart';
import 'event_format_section.dart';
import '../../core/ui/app_segmented_button.dart';

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
    vm.publish.addListener(_onPublish);
  }

  @override
  void dispose() {
    vm.save.removeListener(_onSave);
    vm.publish.removeListener(_onPublish);
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

  void _onPublish() {
    final r = vm.publish.result;
    if (r is Ok<String>) {
      vm.publish.clearResult();
      if (vm.isNew) {
        context.pushReplacement(Routes.tournament(r.value));
      } else {
        context.pop();
      }
    } else if (vm.publish.error) {
      showErrorSnackBar(context, r);
      vm.publish.clearResult();
      // Created but not published: open the draft rather than create it
      // again from here.
      if (vm.createdDraftId case final id?) {
        context.pushReplacement(Routes.tournament(id));
      }
    }
  }

  /// The last step: everything at a glance, each part with Edit to go
  /// back to its step, and what's still missing.
  List<Widget> _review(AppColors c) {
    final f = DateFormat('EEE, MMM d, y');
    final end = vm.endsOn;
    final why = vm.problem ?? vm.publishProblem;
    String money(int? cents) => cents == null
        ? 'amount missing'
        : '${(cents / 100).toStringAsFixed(cents % 100 == 0 ? 0 : 2)} '
              '${vm.currency}';
    final rows = <(int, String, String)>[
      (
        0,
        'Details',
        [
          if (vm.name.trim().isEmpty) 'No name yet' else vm.name.trim(),
          vm.isLeague ? 'League' : 'Tournament',
        ].join(' · '),
      ),
      (
        1,
        'When & where',
        [
          end == null || DateUtils.isSameDay(end, vm.startsOn)
              ? f.format(vm.startsOn)
              : '${f.format(vm.startsOn)} – ${f.format(end)}',
          if (vm.location.trim().isNotEmpty) vm.location.trim(),
        ].join(' · '),
      ),
      (
        2,
        'Who can play',
        [
          vm.entryChoice.label,
          if (vm.teamEntry && !vm.isLeague) 'teams can reserve a spot',
          vm.visibility.label,
        ].join(' · '),
      ),
      (
        3,
        'Format & divisions',
        [
          vm.isLeague ? 'Weekly' : vm.settings.format.label,
          '${vm.settings.playersOnField}v${vm.settings.playersOnField}',
          '${vm.divisions.length} '
              '${vm.divisions.length == 1 ? 'division' : 'divisions'}',
        ].join(' · '),
      ),
      (
        4,
        'Fees & deadline',
        [
          if (!vm.hasFee) 'No fee' else '${vm.feeName}: ${money(vm.feeCents)}',
          if (vm.hasFee && vm.teamEntry) 'team spot: ${money(vm.teamFeeCents)}',
          vm.entryDeadline == null
              ? 'due the day before'
              : 'due ${DateFormat.MMMd().format(vm.entryDeadline!)}',
        ].join(' · '),
      ),
      (
        HostedTournamentFormViewModel.directorStep,
        'Director',
        vm.director == null
            ? 'None'
            : [
                vm.director!.name,
                if (vm.director!.isMember) 'Stall 10 member',
                if (vm.director!.email.isNotEmpty) vm.director!.email,
                if (vm.director!.phone.isNotEmpty) vm.director!.phone,
              ].join(' · '),
      ),
    ];
    return _formStep(
      c,
      number: HostedTournamentFormViewModel.steps.length,
      title: 'Review',
      children: [
        for (final (i, title, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: c.muted,
                        ),
                      ),
                      Text(
                        value,
                        style: TextStyle(fontSize: 14.5, color: c.ink),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: c.accent),
                  onPressed: () => vm.goTo(i),
                  child: Text('Edit', semanticsLabel: 'Edit $title'),
                ),
              ],
            ),
          ),
        if (why != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              why,
              key: const Key('form-problem'),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: c.highlightInk,
              ),
            ),
          ),
      ],
    );
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
      child: AppSegmentedButton<HostedKind>(
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
          children: [Chip(label: Text(vm.entryChoice.label))],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSegmentedButton<EntryChoice>(
          segments: [
            for (final c in vm.entryChoices)
              ButtonSegment(value: c, label: Text(c.label)),
          ],
          selected: {vm.entryChoice},
          onSelectionChanged: (s) => vm.setEntryChoice(s.first),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(switch ((vm.kind, vm.entryType)) {
            (HostedKind.league, _) when vm.entryChoice == EntryChoice.both =>
              'A weekly league: a captain can pay the team fee and bring '
                  'their own team, or players sign up on their own and are '
                  'drafted onto the other teams.',
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
          // A league picks this as its third choice above.
          if (!vm.isLeague)
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
          AppSegmentedButton<DraftMode>(
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
      listenable: Listenable.merge([vm, vm.save, vm.publish]),
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
        final busy = vm.save.running || vm.publish.running;
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
                    if (vm.onReview && vm.isDraft)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Save draft keeps it to your managers. Publish puts '
                          'it on the website and opens registration for '
                          '${vm.takesPlayers ? 'signups' : 'teams'}.',
                          textAlign: TextAlign.center,
                          style: small,
                        ),
                      ),
                    Row(
                      children: [
                        if (vm.step > 0) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: vm.back,
                              child: const Text('Back'),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          flex: 2,
                          child: !vm.onReview
                              ? FilledButton(
                                  key: const Key('form-next'),
                                  onPressed: vm.next,
                                  child: Text(
                                    'Next: '
                                    '${HostedTournamentFormViewModel.steps[vm.step + 1]}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              : vm.isDraft
                              ? FilledButton(
                                  key: const Key('form-publish'),
                                  onPressed:
                                      busy ||
                                          vm.problem != null ||
                                          vm.publishProblem != null
                                      ? null
                                      : vm.publish.execute,
                                  child: const Text('Publish'),
                                )
                              : FilledButton(
                                  onPressed: busy || vm.problem != null
                                      ? null
                                      : vm.save.execute,
                                  child: const Text('Save'),
                                ),
                        ),
                      ],
                    ),
                    // Saving never needs the last step.
                    if (vm.isDraft || !vm.onReview)
                      TextButton(
                        key: const Key('form-save'),
                        style: TextButton.styleFrom(foregroundColor: c.accent),
                        onPressed: busy || vm.problem != null
                            ? null
                            : vm.save.execute,
                        child: Text(vm.isDraft ? 'Save draft' : 'Save'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          body: ConstrainedContent(
            child: ListView(
              // Each step starts at its top.
              key: ValueKey('form-step-${vm.step}'),
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
                _StepHeader(viewModel: vm),
                ...switch (vm.step) {
                  0 => _formStep(
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
                  1 => _formStep(
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
                  2 => _formStep(
                    c,
                    number: 3,
                    title: 'Who can play',
                    children: [
                      _entryPicker(theme),
                      AppSegmentedButton<TournamentVisibility>(
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
                      if (vm.takesTeams) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int?>(
                          key: const Key('invite-reply-days'),
                          initialValue: vm.inviteReplyDays,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Invited teams answer by',
                          ),
                          items: [
                            for (final d in <int?>[
                              null,
                              ...HostedTournament.inviteReplyChoices,
                            ])
                              DropdownMenuItem(
                                value: d,
                                child: Text(
                                  HostedTournament.inviteReplyLabel(d),
                                ),
                              ),
                          ],
                          onChanged: vm.setInviteReplyDays,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'After this an invite expires and you can '
                            'invite another team. A late invite still gets '
                            'two days.',
                            style: small,
                          ),
                        ),
                      ],
                    ],
                  ),
                  3 => _formStep(
                    c,
                    number: 4,
                    title: 'Format & divisions',
                    children: EventFormatSection(viewModel: vm).parts(context),
                  ),
                  4 => _formStep(
                    c,
                    number: 5,
                    title: 'Fees & deadline',
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(vm.feeName),
                        subtitle: Text(
                          vm.teamEntry
                              ? 'What each player who signs up pays, and what '
                                    'a team pays to reserve a spot. You mark '
                                    'them paid, or Stall 10 does when they '
                                    'pay online.'
                              : vm.takesPlayers
                              ? 'What each player pays to sign up. You mark '
                                    'them paid, or Stall 10 does when they '
                                    'pay online.'
                              : 'What each team pays to hold its spot. You '
                                    'mark them paid, or Stall 10 does when '
                                    'they pay online.',
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
                                      _fee.text.isNotEmpty &&
                                          vm.feeCents == null
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
                        FeeBreakdownNote(
                          amountCents: vm.feeCents,
                          currency: vm.currency,
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
                          FeeBreakdownNote(
                            amountCents: vm.teamFeeCents,
                            currency: vm.currency,
                          ),
                        ],
                        const SizedBox(height: 12),
                        // With online payments on, these are the other ways
                        // (a school's check or PO).
                        PaymentsOnBuilder(
                          builder: (context, on) => TextField(
                            controller: _instructions,
                            maxLength: 500,
                            maxLines: 3,
                            minLines: 1,
                            decoration: InputDecoration(
                              labelText: on
                                  ? 'Other ways to pay'
                                  : 'How to pay',
                              hintText: on
                                  ? 'e.g. Checks payable to Fling Crew, '
                                        'mailed to 12 Main St'
                                  : 'e.g. Venmo @club-treasurer with your '
                                        'team name',
                            ),
                            onChanged: (v) => vm.feeInstructions = v,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      ListTile(
                        key: const Key('entry-deadline'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_available_outlined),
                        title: const Text('Entry deadline'),
                        subtitle: Text(
                          vm.entryDeadline == null
                              ? 'Rosters${vm.hasFee ? ' and fees' : ''} are '
                                    'due the day before it starts'
                              : 'Rosters${vm.hasFee ? ' and fees' : ''} are '
                                    'due ${DateFormat.yMMMd().format(vm.entryDeadline!)}',
                        ),
                        trailing: vm.entryDeadline == null
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.close),
                                onPressed: () => vm.setFeeDue(null),
                              ),
                        onTap: () async {
                          final last = vm.startsOn.subtract(
                            const Duration(days: 1),
                          );
                          final first = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            initialDate: () {
                              final want =
                                  vm.entryDeadline ??
                                  vm.startsOn.subtract(
                                    const Duration(days: 14),
                                  );
                              if (want.isBefore(first)) return first;
                              if (want.isAfter(last)) return last;
                              return want;
                            }(),
                            firstDate: first.isAfter(last) ? last : first,
                            lastDate: last,
                          );
                          if (d != null) {
                            vm.setFeeDue(
                              DateTime(d.year, d.month, d.day, 23, 59),
                            );
                          }
                        },
                      ),
                      // The host's payments, set up here without leaving.
                      if (vm.hasFee && vm.host != null) ...[
                        const SizedBox(height: 8),
                        PayoutsCard(
                          teamId: vm.host!.id,
                          amountCents: vm.feeCents,
                        ),
                      ],
                    ],
                  ),
                  5 => _formStep(
                    c,
                    number: 6,
                    title: 'Director',
                    children: [DirectorSection(viewModel: vm)],
                  ),
                  _ => _review(c),
                },
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

/// Where the form is: "Step 2 of 6 · When & where" over a bar of the
/// steps; a step's segment jumps to it.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.viewModel});

  final HostedTournamentFormViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    const steps = HostedTournamentFormViewModel.steps;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${vm.step + 1} of ${steps.length} · ${steps[vm.step]}',
            key: const Key('form-step'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.ink2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (i, title) in steps.indexed)
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Step ${i + 1}: $title',
                    selected: i == vm.step,
                    child: InkWell(
                      onTap: () => vm.goTo(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 6,
                        ),
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= vm.step ? c.accent : c.border,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
