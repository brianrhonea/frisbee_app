import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/team.dart';
import '../../../domain/tournament_engine/generator.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../view_models/hosted_tournament_viewmodel.dart';
import '../view_models/player_signups_viewmodel.dart';

/// Formats a division can use; a hosted division always has more than a
/// handful of teams, so all of them.
const _formats = TournamentFormat.values;

/// Adds or edits a division: which one, how many teams, the format and
/// game rules. Returns the division to save.
Future<TournamentDivision?> showDivisionDialog(
  BuildContext context, {
  required TournamentDivision initial,
  bool league = false,
  bool players = false,
}) => showDialog<TournamentDivision>(
  context: context,
  builder: (_) =>
      _DivisionDialog(initial: initial, league: league, players: players),
);

class _DivisionDialog extends StatefulWidget {
  const _DivisionDialog({
    required this.initial,
    this.league = false,
    this.players = false,
  });

  final TournamentDivision initial;

  /// A weekly league: the format follows the season, and the first night
  /// is picked by date.
  final bool league;

  /// Players sign up one by one, so there's no team roster minimum.
  final bool players;

  @override
  State<_DivisionDialog> createState() => _DivisionDialogState();
}

class _DivisionDialogState extends State<_DivisionDialog> {
  late TournamentDivision d = widget.initial;

  TournamentSettings get s => d.settings;

  void _settings(TournamentSettings next) =>
      setState(() => d = d.copyWith(settings: next));

  /// Applies the usual format for the team cap: a round robin for small
  /// fields, otherwise pools of 4–5 and a placement bracket.
  void _suggest() => _settings(
    s.copyWith(
      format: suggestedFormat(d.maxTeams),
      poolCount: suggestedPools(d.maxTeams),
    ),
  );

  /// A new field size also resets the roster minimum when it was still the
  /// usual one for the old size (or unset), so a 4v4 league asks for 4.
  void _fieldSize(int n) => setState(() {
    final wasUsual = d.minRoster == null || d.minRoster == s.playersOnField;
    d = d.copyWith(
      settings: s.copyWith(playersOnField: n),
      minRoster: wasUsual ? () => n : null,
    );
  });

  Future<void> _pickFirstNight() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: s.startsAt,
      firstDate: DateTime(s.startsAt.year - 1),
      lastDate: DateTime(s.startsAt.year + 3),
      helpText: 'First night of the season',
    );
    if (picked == null) return;
    _settings(
      s.copyWith(
        startsAt: DateTime(
          picked.year,
          picked.month,
          picked.day,
          s.startsAt.hour,
          s.startsAt.minute,
        ),
      ),
    );
  }

  Widget _number(
    String label,
    int value,
    List<int> options,
    void Function(int) onChanged, {
    String Function(int)? text,
  }) => DropdownButtonFormField<int>(
    initialValue: options.contains(value) ? value : null,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final o in options)
        DropdownMenuItem(value: o, child: Text(text?.call(o) ?? '$o')),
    ],
    onChanged: (v) => v == null ? null : onChanged(v),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caps = {...TournamentDivision.teamCaps, d.maxTeams}.toList()..sort();
    return AlertDialog(
      title: Text(d.isNew ? 'Add a division' : 'Edit ${d.label}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<CompetitionLevel>(
                      initialValue: d.level,
                      decoration: const InputDecoration(labelText: 'Level'),
                      items: [
                        for (final l in CompetitionLevel.values)
                          DropdownMenuItem(value: l, child: Text(l.label)),
                      ],
                      onChanged: (v) =>
                          setState(() => d = d.copyWith(level: v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<Division>(
                      initialValue: d.division,
                      decoration: const InputDecoration(labelText: 'Division'),
                      items: [
                        for (final v in Division.values)
                          DropdownMenuItem(value: v, child: Text(v.label)),
                      ],
                      onChanged: (v) =>
                          setState(() => d = d.copyWith(division: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _number(
                'Team cap',
                d.maxTeams,
                caps,
                (v) => setState(() => d = d.copyWith(maxTeams: v)),
                text: (v) => '$v teams',
              ),
              const SizedBox(height: 8),
              Text('Players on the field', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (final n in TournamentSettings.fieldSizes)
                    ChoiceChip(
                      label: Text('${n}v$n'),
                      selected: s.playersOnField == n,
                      onSelected: (_) => _fieldSize(n),
                    ),
                ],
              ),
              if (!widget.players) ...[
                const SizedBox(height: 8),
                _number(
                  'Players a team needs to register',
                  d.effectiveMinRoster,
                  [
                    for (var n = 2; n <= 20; n++) n,
                    if (d.effectiveMinRoster > 20) d.effectiveMinRoster,
                  ],
                  (v) => setState(() => d = d.copyWith(minRoster: () => v)),
                  text: (v) => '$v players',
                ),
              ],
              if (widget.league) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickFirstNight,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'First night',
                      helperText: 'Games are weekly on this day',
                    ),
                    child: Text(DateFormat('EEEE, MMM d').format(s.startsAt)),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Format', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _suggest,
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: Text('Suggest for ${d.maxTeams}'),
                    ),
                  ],
                ),
                DropdownButtonFormField<TournamentFormat>(
                  initialValue: s.format,
                  isExpanded: true,
                  decoration: InputDecoration(helperText: s.format.summary),
                  items: [
                    for (final f in _formats)
                      DropdownMenuItem(value: f, child: Text(f.label)),
                  ],
                  onChanged: (v) =>
                      v == null ? null : _settings(s.copyWith(format: v)),
                ),
              ],
              if (!widget.league &&
                  (s.format == TournamentFormat.poolsSingleElim ||
                      s.format == TournamentFormat.poolsPlacement)) ...[
                const SizedBox(height: 8),
                _number(
                  'Pools',
                  s.poolCount,
                  [1, 2, 3, 4, 5, 6, 8],
                  (v) => _settings(s.copyWith(poolCount: v)),
                  text: (v) => v == 1 ? 'One pool' : '$v pools',
                ),
              ],
              const SizedBox(height: 16),
              Text('Games', style: theme.textTheme.titleSmall),
              Row(
                children: [
                  Expanded(
                    child: _number(
                      'Game to',
                      s.scoreCap,
                      [7, 9, 11, 13, 15, 17],
                      (v) => _settings(s.copyWith(scoreCap: v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _number(
                      'Timeouts per half',
                      s.timeoutsPerHalf,
                      [0, 1, 2, 3],
                      (v) => _settings(s.copyWith(timeoutsPerHalf: v)),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _number(
                      'Game length',
                      s.gameMinutes,
                      [30, 40, 45, 60, 75, 90, 100, 120],
                      (v) => _settings(s.copyWith(gameMinutes: v)),
                      text: (v) => '$v min',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _number(
                      'Break',
                      s.breakMinutes,
                      [0, 5, 10, 15, 20, 30],
                      (v) => _settings(s.copyWith(breakMinutes: v)),
                      text: (v) => '$v min',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _number('Fields', s.fields, [
                      for (var i = 1; i <= 16; i++) i,
                    ], (v) => _settings(s.copyWith(fields: v))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(s.startsAt),
                          helpText: widget.league
                              ? 'First game each night'
                              : 'First game each day',
                        );
                        if (t == null) return;
                        final start = DateTime(
                          s.startsAt.year,
                          s.startsAt.month,
                          s.startsAt.day,
                          t.hour,
                          t.minute,
                        );
                        _settings(
                          s.copyWith(
                            startsAt: start,
                            laterDays: [
                              for (final day in s.laterDays)
                                DateTime(
                                  day.year,
                                  day.month,
                                  day.day,
                                  t.hour,
                                  t.minute,
                                ),
                            ],
                          ),
                        );
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'First game',
                        ),
                        child: Text(DateFormat.jm().format(s.startsAt)),
                      ),
                    ),
                  ),
                ],
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
          onPressed: () => Navigator.pop(context, d),
          child: Text(d.isNew ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}

/// A team admin enters one of [teams] (or answers an invite for it):
/// picks the division and who reports scores.
Future<EntryApplication?> showApplyDialog(
  BuildContext context, {
  required List<Team> teams,
  required List<TournamentDivision> divisions,
  required String uid,
  TournamentEntry? invite,
  TournamentEntry? editing,
}) => showDialog<EntryApplication>(
  context: context,
  builder: (_) => _ApplyDialog(
    teams: teams,
    divisions: divisions,
    uid: uid,
    invite: invite,
    editing: editing,
  ),
);

class _ApplyDialog extends StatefulWidget {
  const _ApplyDialog({
    required this.teams,
    required this.divisions,
    required this.uid,
    this.invite,
    this.editing,
  });

  final List<Team> teams;
  final List<TournamentDivision> divisions;
  final String uid;
  final TournamentEntry? invite;
  final TournamentEntry? editing;

  @override
  State<_ApplyDialog> createState() => _ApplyDialogState();
}

class _ApplyDialogState extends State<_ApplyDialog> {
  late Team? team = widget.teams.firstOrNull;
  late String? divisionId =
      widget.editing?.divisionId ??
      widget.invite?.divisionId ??
      _matching(widget.teams.firstOrNull);
  late Set<String> captains = {
    ...?widget.editing?.captainIds,
    if (widget.editing == null) widget.uid,
  };

  /// The division matching the team's own, if there is one.
  String? _matching(Team? t) {
    final match = widget.divisions.where(
      (d) => t != null && d.division == t.division && d.level == t.level,
    );
    return (match.firstOrNull ?? widget.divisions.firstOrNull)?.id;
  }

  @override
  Widget build(BuildContext context) {
    final t = team;
    final fixed = widget.invite != null || widget.editing != null;
    final members = t == null
        ? const <String>[]
        : ([...t.members.keys]
            ..sort((a, b) => t.nameOf(a).compareTo(t.nameOf(b))));
    return AlertDialog(
      title: Text(
        widget.editing != null
            ? 'Captains'
            : widget.invite != null
            ? 'Accept the invite'
            : 'Apply to play',
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!fixed)
                DropdownButtonFormField<Team>(
                  initialValue: team,
                  decoration: const InputDecoration(labelText: 'Team'),
                  items: [
                    for (final x in widget.teams)
                      DropdownMenuItem(value: x, child: Text(x.name)),
                  ],
                  onChanged: (v) => setState(() {
                    team = v;
                    divisionId = _matching(v);
                    captains = {widget.uid};
                  }),
                ),
              if (widget.editing == null)
                DropdownButtonFormField<String>(
                  initialValue: divisionId,
                  decoration: const InputDecoration(labelText: 'Division'),
                  items: [
                    for (final d in widget.divisions)
                      DropdownMenuItem(
                        value: d.id,
                        child: Text(
                          d.isFull ? '${d.label} (full: waitlist)' : d.label,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => divisionId = v),
                ),
              const SizedBox(height: 16),
              Text(
                'Captains report and confirm scores '
                '(up to ${TournamentEntry.maxCaptains}).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (final uid in members)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: captains.contains(uid),
                  title: Text(
                    t!.nameOf(uid) + (uid == widget.uid ? ' (you)' : ''),
                  ),
                  onChanged:
                      !captains.contains(uid) &&
                          captains.length >= TournamentEntry.maxCaptains
                      ? null
                      : (v) => setState(
                          () => v == true
                              ? captains.add(uid)
                              : captains.remove(uid),
                        ),
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
          onPressed: t == null || divisionId == null || captains.isEmpty
              ? null
              : () => Navigator.pop(context, (
                  teamId: t.id,
                  divisionId: divisionId!,
                  captainIds: captains.toList(),
                )),
          child: Text(
            widget.editing != null
                ? 'Save'
                : widget.invite != null
                ? 'Accept'
                : 'Apply',
          ),
        ),
      ],
    );
  }
}

/// The host searches the team directory for a team to invite and picks
/// its division.
Future<({TeamListing team, String divisionId})?> showInviteDialog(
  BuildContext context, {
  required HostedTournamentViewModel viewModel,
  required List<TournamentDivision> divisions,
  String? divisionId,
}) => showDialog<({TeamListing team, String divisionId})>(
  context: context,
  builder: (_) => _InviteDialog(
    viewModel: viewModel,
    divisions: divisions,
    divisionId: divisionId,
  ),
);

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({
    required this.viewModel,
    required this.divisions,
    this.divisionId,
  });

  final HostedTournamentViewModel viewModel;
  final List<TournamentDivision> divisions;
  final String? divisionId;

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  late String? divisionId =
      widget.divisionId ?? widget.divisions.firstOrNull?.id;
  List<TeamListing> results = const [];
  bool searching = false;
  Object? error;
  int _search = 0;

  Future<void> _find(String q) async {
    final mine = ++_search;
    if (q.trim().length < 2) {
      setState(() => results = const []);
      return;
    }
    setState(() => searching = true);
    final r = await widget.viewModel.searchTeams(q.trim());
    if (!mounted || mine != _search) return;
    setState(() {
      searching = false;
      switch (r) {
        case Ok(:final value):
          results = value;
          error = null;
        case Error(:final error):
          this.error = error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return AlertDialog(
      title: const Text('Invite a team'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: divisionId,
              decoration: const InputDecoration(labelText: 'Division'),
              items: [
                for (final d in widget.divisions)
                  DropdownMenuItem(value: d.id, child: Text(d.label)),
              ],
              onChanged: (v) => setState(() => divisionId = v),
            ),
            const SizedBox(height: 8),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search teams by name',
              ),
              onChanged: _find,
            ),
            if (searching) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(errorMessage(error)),
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final t in results)
                    ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.shield_outlined),
                      ),
                      title: Text(t.name),
                      subtitle: Text(
                        [
                          '${t.level.label} ${t.division.label}',
                          if (t.city.isNotEmpty) t.city,
                          if (vm.entryOf(t.id) case final e?) e.status.label,
                        ].join(' · '),
                      ),
                      enabled:
                          divisionId != null &&
                          (vm.entryOf(t.id) == null ||
                              vm.entryOf(t.id)!.status ==
                                  EntryStatus.withdrawn),
                      onTap: () => Navigator.pop(context, (
                        team: t,
                        divisionId: divisionId!,
                      )),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// What each self-rated skill level means, shown under the slider.
const _skillHints = {
  1: 'New to ultimate',
  2: 'Some experience',
  3: 'Solid recreational player',
  4: 'Experienced, plays regularly',
  5: 'Competitive club or college level',
};

/// A player signs up (or edits their signup): which division, how they rate
/// their skill, and in mixed divisions their gender match. Skill and gender
/// are only used to balance teams, and only the host sees them.
Future<SignupAnswers?> showPlayerSignupDialog(
  BuildContext context, {
  required List<TournamentDivision> divisions,
  PlayerSignup? initial,
  EntryFee? fee,
}) => showDialog<SignupAnswers>(
  context: context,
  builder: (_) =>
      _SignupDialog(divisions: divisions, initial: initial, fee: fee),
);

class _SignupDialog extends StatefulWidget {
  const _SignupDialog({required this.divisions, this.initial, this.fee});

  final List<TournamentDivision> divisions;
  final PlayerSignup? initial;
  final EntryFee? fee;

  @override
  State<_SignupDialog> createState() => _SignupDialogState();
}

class _SignupDialogState extends State<_SignupDialog> {
  late String _divisionId =
      widget.divisions.any((d) => d.id == widget.initial?.divisionId)
      ? widget.initial!.divisionId
      : widget.divisions.first.id;
  late int _skill = widget.initial?.skill ?? 3;
  late GenderMatch? _gender = widget.initial?.gender;

  TournamentDivision get _division =>
      widget.divisions.firstWhere((d) => d.id == _divisionId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fee = widget.fee;
    return AlertDialog(
      title: Text(widget.initial == null ? 'Sign up' : 'Your signup'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fee != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    [
                      'Entry fee: ${fee.label}.',
                      if (fee.instructions.isNotEmpty) fee.instructions,
                      if (fee.dueAt != null)
                        'Due ${DateFormat.yMMMd().format(fee.dueAt!)}.',
                    ].join(' '),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              if (widget.divisions.length > 1)
                DropdownButtonFormField<String>(
                  initialValue: _divisionId,
                  decoration: const InputDecoration(labelText: 'Division'),
                  items: [
                    for (final d in widget.divisions)
                      DropdownMenuItem(value: d.id, child: Text(d.label)),
                  ],
                  onChanged: (v) => setState(() {
                    _divisionId = v ?? _divisionId;
                    if (_division.division != Division.mixed) _gender = null;
                  }),
                ),
              const SizedBox(height: 12),
              Text(
                'Your skill: $_skill of 5',
                style: theme.textTheme.titleSmall,
              ),
              Slider(
                value: _skill.toDouble(),
                min: PlayerSignup.minSkill.toDouble(),
                max: PlayerSignup.maxSkill.toDouble(),
                divisions: PlayerSignup.maxSkill - PlayerSignup.minSkill,
                label: '$_skill',
                onChanged: (v) => setState(() => _skill = v.round()),
              ),
              Text(_skillHints[_skill] ?? '', style: theme.textTheme.bodySmall),
              if (_division.division == Division.mixed) ...[
                const SizedBox(height: 16),
                Text('Gender match', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final g in GenderMatch.values)
                      ChoiceChip(
                        label: Text(g.label),
                        selected: _gender == g,
                        onSelected: (_) => setState(() => _gender = g),
                      ),
                    ChoiceChip(
                      label: const Text('Prefer not to say'),
                      selected: _gender == null,
                      onSelected: (_) => setState(() => _gender = null),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Used to even out lines on each team.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Only the host sees your skill and gender match.',
                style: theme.textTheme.bodySmall,
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
          onPressed: () => Navigator.pop(context, (
            divisionId: _divisionId,
            skill: _skill,
            gender: _division.division == Division.mixed ? _gender : null,
          )),
          child: Text(widget.initial == null ? 'Sign up' : 'Save'),
        ),
      ],
    );
  }
}
