import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/player_profile.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../view_models/player_profile_viewmodel.dart';
import '../view_models/profile_viewmodel.dart';
import 'delete_account_dialog.dart';

enum _Tab { overview, stats, teams }

/// A player's profile: who they are, their numbers, recent games and
/// teams. On the user's own profile, [settings] adds their app settings,
/// and they can edit the profile and link their roster spots.
class PlayerProfileScreen extends StatefulWidget {
  const PlayerProfileScreen({
    super.key,
    required this.viewModel,
    this.settings,
  });

  final PlayerProfileViewModel viewModel;
  final ProfileViewModel? settings;

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  PlayerProfileViewModel get vm => widget.viewModel;
  var _tab = _Tab.overview;

  late final List<Command<void>> _commands = [
    vm.saveDetails,
    vm.claim,
    vm.unclaim,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
    vm.message.addListener(_onMessage);
  }

  @override
  void dispose() {
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
    vm.message.removeListener(_onMessage);
    super.dispose();
  }

  void _onCommand() {
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
    if (vm.saveDetails.completed) {
      vm.saveDetails.clearResult();
      showSnackBar(context, 'Profile saved');
    }
  }

  void _onMessage() {
    switch (vm.message.result) {
      case Ok<String>(:final value):
        vm.message.clearResult();
        context.push(Routes.conversation(value));
      case Error<String>():
        showErrorSnackBar(context, vm.message.result);
        vm.message.clearResult();
      case null:
        break;
    }
  }

  Future<void> _edit() async {
    final details = await showDialog<ProfileDetails>(
      context: context,
      builder: (_) => EditProfileDialog(initial: vm.details),
    );
    if (details != null) vm.saveDetails.execute(details);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ScreenSize.of(context).isMobile;
    return Scaffold(
      appBar: mobile || !vm.isMe
          ? AppBar(title: Text(vm.isMe ? 'My profile' : 'Player profile'))
          : null,
      body: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.saveDetails, vm.message]),
        builder: (context, _) {
          if (!vm.loaded) return const LoadingView();
          if (!vm.isMe && vm.profile == null) {
            return vm.error != null
                ? ErrorView(error: vm.error)
                : const EmptyView(
                    icon: Icons.person_off_outlined,
                    title: 'Profile not available',
                  );
          }
          return PageScroll(
            children: [
              _Hero(
                viewModel: vm,
                onEdit: _edit,
                tab: _tab,
                onTab: (t) => setState(() => _tab = t),
              ),
              const SizedBox(height: 16),
              ..._body(),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _body() {
    final settings = widget.settings;
    final side = [
      if (vm.isMe)
        for (final c in vm.claimable) _ClaimCard(viewModel: vm, claim: c),
      _OffTheSheet(details: vm.details, primary: vm.primaryTeam),
      if (vm.showsTeams) _TeamsCard(viewModel: vm),
      ?settings == null ? null : SettingsCard(viewModel: settings),
    ];
    return switch (_tab) {
      _Tab.overview => [
        SideColumnLayout(
          main: [
            _NumbersCard(viewModel: vm),
            if (vm.showsGames) ..._games(),
          ],
          side: side,
        ),
      ],
      _Tab.stats => [
        _NumbersCard(viewModel: vm),
        const SizedBox(height: 14),
        _SeasonsCard(viewModel: vm),
      ],
      _Tab.teams => [
        SideColumnLayout(
          main: [_TeamsCard(viewModel: vm, wide: true)],
          side: [
            if (vm.isMe)
              for (final c in vm.claimable)
                _ClaimCard(viewModel: vm, claim: c),
          ],
        ),
      ],
    };
  }

  List<Widget> _games() {
    final c = AppColors.of(context);
    final games = vm.summary.games;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                vm.isMe ? 'From my sideline' : 'Recent games',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: c.ink,
                ),
              ),
            ),
            if (vm.isMe && !vm.visibility.games)
              const _HiddenTag(),
          ],
        ),
      ),
      if (games.isEmpty)
        Text(
          'Games show up here once a stat keeper tracks one you play in.',
          style: TextStyle(fontSize: 12.5, color: c.muted),
        ),
      for (final g in games) _GameCard(game: g),
    ];
  }
}

// Header -----------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({
    required this.viewModel,
    required this.onEdit,
    required this.tab,
    required this.onTab,
  });

  final PlayerProfileViewModel viewModel;
  final VoidCallback onEdit;
  final _Tab tab;
  final ValueChanged<_Tab> onTab;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final mobile = ScreenSize.of(context).isMobile;
    final d = vm.details;
    final primary = vm.primaryTeam;
    final number = primary?.number;
    final button = vm.isMe
        ? FilledButton.icon(
            onPressed: vm.saveDetails.running ? null : onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit profile'),
          )
        : FilledButton.icon(
            onPressed: vm.message.running ? null : vm.message.execute,
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Message'),
          );
    final meta = [
      if (d.hometown.isNotEmpty) d.hometown,
      if (d.school.isNotEmpty) d.school,
      if (d.playingSince case final y?) 'Playing since $y',
    ];
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: mobile ? 92 : 112,
            color: c.feature,
            padding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow('Chase the next point.', color: c.highlight),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ALWAYS IN PLAY.',
                          style: TextStyle(
                            color: c.onFeature,
                            fontSize: mobile ? 24 : 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (number != null)
                  Text(
                    '$number',
                    style: TextStyle(
                      color: c.onFeature.withValues(alpha: 0.22),
                      fontSize: mobile ? 64 : 88,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -3,
                      height: 1,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(mobile ? 14 : 20, 16, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PersonAvatar(
                      name: vm.name,
                      photoUrl: vm.photoUrl,
                      radius: mobile ? 26 : 30,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vm.name,
                            style: TextStyle(
                              fontSize: mobile ? 20 : 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                              color: c.ink,
                            ),
                          ),
                          if (d.pronouns.isNotEmpty)
                            Text(
                              d.pronouns,
                              style: TextStyle(fontSize: 12, color: c.muted),
                            ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (primary != null && primary.number != null)
                                Tag(
                                  [
                                    '#${primary.number}',
                                    ?primary.position,
                                  ].join(' · ').toUpperCase(),
                                ),
                              if (primary?.role case final role?)
                                Tag(role.toUpperCase()),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!mobile) button,
                  ],
                ),
                if (d.bio.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    d.bio,
                    style: TextStyle(fontSize: 13.5, height: 1.45, color: c.ink),
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    meta.join(' · '),
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
                if (mobile) ...[
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: button),
                ],
                const SizedBox(height: 8),
                UnderlineTabs(
                  labels: const ['Overview', 'Stats', 'Teams'],
                  selected: tab.index,
                  onSelect: (i) => onTab(_Tab.values[i]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HiddenTag extends StatelessWidget {
  const _HiddenTag();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Only you can see this. Change it in Edit profile.',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.visibility_off_outlined, size: 14, color: AppColors.of(context).muted),
        const SizedBox(width: 4),
        Text(
          'Hidden',
          style: TextStyle(fontSize: 11.5, color: AppColors.of(context).muted),
        ),
      ],
    ),
  );
}

// Stats ------------------------------------------------------------------

String _pct(double? v) => v == null ? '–' : '${(v * 100).round()}%';

String _avg(double? v) => v == null ? '' : '${v.toStringAsFixed(1)} per game';

class _NumbersCard extends StatelessWidget {
  const _NumbersCard({required this.viewModel});

  final PlayerProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    final t = vm.totals;
    final seasons = vm.seasons;
    final updated = vm.isMe ? null : vm.summary.updatedAt;
    final teams = vm.summary.teams
        .where((x) => x.number != null || x.kind.name == 'team')
        .map((x) => x.name)
        .toSet();
    return SectionCard(
      title: 'By the numbers',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (vm.isMe && !vm.visibility.stats) ...[
            const _HiddenTag(),
            const SizedBox(width: 8),
          ],
          if (seasons.isNotEmpty)
            DropdownButton<String?>(
              value: vm.season,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: TextStyle(fontSize: 12, color: c.muted),
              items: [
                const DropdownMenuItem(value: null, child: Text('All time')),
                for (final s in seasons)
                  DropdownMenuItem(value: s, child: Text('$s season')),
              ],
              onChanged: vm.selectSeason,
            ),
        ],
      ),
      child: !vm.showsStats
          ? Text(
              'Stats are private.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            )
          : t.isEmpty
          ? Text(
              vm.isMe
                  ? 'No tracked games yet. Link your roster spot, and your '
                        'numbers fill in as your team tracks games.'
                  : 'No tracked games yet.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 420 ? 3 : 2;
                    final width = constraints.maxWidth / columns;
                    final blocks = [
                      ('${t.assists}', 'Assists', _avg(t.perGame(t.assists))),
                      ('${t.goals}', 'Goals', _avg(t.perGame(t.goals))),
                      ('${t.blocks}', 'Blocks', _avg(t.perGame(t.blocks))),
                      (
                        _pct(t.completionPct),
                        'Completion',
                        '${t.throws} throws',
                      ),
                      ('${t.games}', 'Games played', ''),
                      ('${t.points}', 'Points played', _avg(t.perGame(t.points))),
                    ];
                    return Wrap(
                      runSpacing: 18,
                      children: [
                        for (final (value, label, note) in blocks)
                          SizedBox(
                            width: width,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                StatBlock(value: value, label: label),
                                if (note.isNotEmpty)
                                  Text(
                                    note,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: c.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  [
                    if (teams.isNotEmpty) teams.join(', '),
                    if (updated != null)
                      'Updated ${DateFormat.MMMd().format(updated)}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 11, color: c.muted),
                ),
              ],
            ),
    );
  }
}

class _SeasonsCard extends StatelessWidget {
  const _SeasonsCard({required this.viewModel});

  final PlayerProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    if (!vm.showsStats || vm.seasons.isEmpty) return const SizedBox.shrink();
    const columns = [
      'Season',
      'Games',
      'Points',
      'Goals',
      'Assists',
      'Blocks',
      'Comp %',
      'Catches',
      'Drops',
      'Turns',
    ];
    List<String> row(String label, StatTotals t) => [
      label,
      '${t.games}',
      '${t.points}',
      '${t.goals}',
      '${t.assists}',
      '${t.blocks}',
      _pct(t.completionPct),
      '${t.catches}',
      '${t.drops}',
      '${t.throwaways}',
    ];
    final rows = [
      for (final s in vm.seasons) row(s, vm.summary.seasons[s]!),
      row('Career', vm.summary.career),
    ];
    return SectionCard(
      title: 'Season by season',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 40,
          horizontalMargin: 0,
          columnSpacing: 22,
          headingTextStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: c.muted,
          ),
          columns: [for (final h in columns) DataColumn(label: Text(h))],
          rows: [
            for (final r in rows)
              DataRow(
                cells: [
                  for (final v in r)
                    DataCell(
                      Text(
                        v,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.ink,
                          fontWeight: r.first == 'Career'
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game});

  final ProfileGame game;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = game;
    final l = g.line;
    final result = g.tied ? 'T' : (g.won ? 'W' : 'L');
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, size: 15, color: c.ink),
              const SizedBox(width: 6),
              Expanded(
                child: Eyebrow(
                  'Match day · ${DateFormat.MMMd().format(g.date)}',
                  color: c.ink,
                ),
              ),
              Tag('$result ${g.ourScore}–${g.theirScore}', strong: g.won),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${g.teamName} vs. ${g.opponent}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final s in [
                '${l.assists} ${l.assists == 1 ? 'assist' : 'assists'}',
                '${l.goals} ${l.goals == 1 ? 'goal' : 'goals'}',
                '${l.blocks} ${l.blocks == 1 ? 'block' : 'blocks'}',
                _pct(l.completionPct),
              ])
                Expanded(
                  child: Text(s, style: TextStyle(fontSize: 12, color: c.ink)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// Side cards -------------------------------------------------------------

class _OffTheSheet extends StatelessWidget {
  const _OffTheSheet({required this.details, required this.primary});

  final ProfileDetails details;
  final ProfileTeam? primary;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final d = details;
    final now = DateTime.now().year;
    final rows = [
      if (d.hometown.isNotEmpty) (Icons.place_outlined, 'Based in', d.hometown),
      if (d.school.isNotEmpty) (Icons.school_outlined, 'School', d.school),
      if (d.throwingHand case final h?)
        (Icons.back_hand_outlined, 'Throwing hand', h.label),
      if (primary?.position case final p?)
        (Icons.sports_handball_outlined, 'Position', p),
      if (d.playingSince case final y?)
        (
          Icons.history,
          'Experience',
          '${now - y + 1} ${now - y + 1 == 1 ? 'season' : 'seasons'}',
        ),
    ];
    return SectionCard(
      title: 'Off the stat sheet',
      child: rows.isEmpty
          ? Text(
              'Nothing here yet.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            )
          : Column(
              children: [
                for (final (icon, label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(icon, size: 15, color: c.muted),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            value,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TeamsCard extends StatelessWidget {
  const _TeamsCard({required this.viewModel, this.wide = false});

  final PlayerProfileViewModel viewModel;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    final teams = vm.summary.teams;
    return SectionCard(
      title: vm.isMe ? 'My teams' : 'Teams',
      action: vm.isMe && !vm.visibility.teams ? const _HiddenTag() : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!vm.showsTeams)
            Text(
              'Teams are private.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            )
          else if (teams.isEmpty)
            Text(
              'Not on a team yet.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          if (vm.showsTeams)
            for (final t in teams)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.go(Routes.team(t.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      TeamBadge(size: 38, community: t.kind.name == 'community'),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: c.ink,
                              ),
                            ),
                            Text(
                              [
                                if (t.subtitle.isNotEmpty) t.subtitle,
                                ?t.role,
                                if (t.number != null) '#${t.number}',
                              ].join(' · '),
                              maxLines: wide ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: c.muted),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Asks the user which roster spot on a team is theirs, so their stats
/// count on their profile.
class _ClaimCard extends StatelessWidget {
  const _ClaimCard({required this.viewModel, required this.claim});

  final PlayerProfileViewModel viewModel;
  final ClaimableTeam claim;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final suggested = claim.players.first;
    return FeatureCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Link your stats · ${claim.team.name}', color: c.onFeatureMuted),
          const SizedBox(height: 8),
          Text(
            'Which player on the roster is you?',
            style: TextStyle(
              color: c.onFeature,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Games your team tracks count toward your profile once you '
            'pick your spot.',
            style: TextStyle(color: c.onFeatureMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          HighlightButton(
            label: "I'm ${suggested.name}",
            onPressed: viewModel.claim.running
                ? null
                : () => viewModel.claim.execute((claim.team.id, suggested.id)),
          ),
          if (claim.players.length > 1)
            Center(
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: c.onFeature),
                onPressed: viewModel.claim.running
                    ? null
                    : () async {
                        final picked = await showDialog<String>(
                          context: context,
                          builder: (context) => SimpleDialog(
                            title: Text('You on ${claim.team.name}'),
                            children: [
                              for (final p in claim.players)
                                SimpleDialogOption(
                                  onPressed: () => Navigator.pop(context, p.id),
                                  child: Text(
                                    [
                                      p.name,
                                      if (p.number != null) '#${p.number}',
                                    ].join(' · '),
                                  ),
                                ),
                            ],
                          ),
                        );
                        if (picked != null) {
                          viewModel.claim.execute((claim.team.id, picked));
                        }
                      },
                child: const Text('Someone else on the roster'),
              ),
            ),
        ],
      ),
    );
  }
}

// Editing ----------------------------------------------------------------

/// Edits the user's profile details and what others see; pops with the
/// new details or null.
class EditProfileDialog extends StatefulWidget {
  const EditProfileDialog({super.key, required this.initial});

  final ProfileDetails initial;

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  late final _bio = TextEditingController(text: widget.initial.bio);
  late final _pronouns = TextEditingController(text: widget.initial.pronouns);
  late final _hometown = TextEditingController(text: widget.initial.hometown);
  late final _school = TextEditingController(text: widget.initial.school);
  late final _since = TextEditingController(
    text: widget.initial.playingSince?.toString() ?? '',
  );
  late ThrowingHand? _hand = widget.initial.throwingHand;
  late ProfileVisibility _visibility = widget.initial.visibility;

  @override
  void dispose() {
    for (final c in [_bio, _pronouns, _hometown, _school, _since]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final year = int.tryParse(_since.text);
    final now = DateTime.now().year;
    Navigator.pop(
      context,
      ProfileDetails(
        bio: _bio.text,
        pronouns: _pronouns.text,
        hometown: _hometown.text,
        school: _school.text,
        throwingHand: _hand,
        playingSince: year != null && year >= 1960 && year <= now ? year : null,
        visibility: _visibility,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget field(
      TextEditingController controller,
      String label, {
      int maxLength = 60,
      int maxLines = 1,
      TextInputType? keyboard,
      List<TextInputFormatter>? formatters,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: keyboard,
        inputFormatters: formatters,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, counterText: ''),
      ),
    );
    return AlertDialog(
      title: const Text('Edit profile'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field(
                _bio,
                'Bio',
                maxLength: ProfileDetails.maxBio,
                maxLines: 4,
              ),
              field(_pronouns, 'Pronouns', maxLength: 30),
              field(_hometown, 'Based in (city)'),
              field(_school, 'School'),
              field(
                _since,
                'Playing since (year)',
                maxLength: 4,
                keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              Text(
                'Throwing hand',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
              const SizedBox(height: 6),
              SegmentedButton<ThrowingHand?>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: null, label: Text('–')),
                  for (final h in ThrowingHand.values)
                    ButtonSegment(value: h, label: Text(h.label)),
                ],
                selected: {_hand},
                onSelectionChanged: (s) => setState(() => _hand = s.first),
              ),
              const SizedBox(height: 16),
              Text(
                'Show on my profile',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              Text(
                'Anyone on UltiUP can find your profile. Hidden sections '
                "aren't shared.",
                style: TextStyle(fontSize: 11.5, color: c.muted),
              ),
              for (final (label, value, update) in [
                (
                  'Stats',
                  _visibility.stats,
                  (bool v) => _visibility.copyWith(stats: v),
                ),
                (
                  'Recent games',
                  _visibility.games,
                  (bool v) => _visibility.copyWith(games: v),
                ),
                (
                  'Teams',
                  _visibility.teams,
                  (bool v) => _visibility.copyWith(teams: v),
                ),
              ])
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(label),
                  value: value,
                  onChanged: (v) => setState(() => _visibility = update(v)),
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
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// Settings ---------------------------------------------------------------

/// The user's app settings: appearance, notifications, display name, sign
/// out and account deletion.
class SettingsCard extends StatefulWidget {
  const SettingsCard({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard> {
  ProfileViewModel get vm => widget.viewModel;

  late final List<Command<void>> _commands = [
    vm.updateDisplayName,
    vm.signOut,
    vm.setThemeMode,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
  }

  @override
  void dispose() {
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
    super.dispose();
  }

  void _onCommand() {
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
    if (vm.updateDisplayName.completed) {
      vm.updateDisplayName.clearResult();
      showSnackBar(context, 'Name updated');
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: vm.user?.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      vm.updateDisplayName.execute(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final error = Theme.of(context).colorScheme.error;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => SectionCard(
        title: 'Settings',
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (vm.user?.email case final email?)
              Text(email, style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 12),
            Text(
              'Appearance',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {vm.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => vm.setThemeMode.execute(s.first),
            ),
            const SizedBox(height: 8),
            for (final (icon, label, onTap, color) in [
              (
                Icons.notifications_outlined,
                'Notifications',
                () => context.push(Routes.notificationSettings),
                null,
              ),
              (Icons.edit_outlined, 'Change display name', _editName, null),
              (
                Icons.logout,
                'Sign out',
                () async {
                  if (await confirmDialog(
                    context,
                    title: 'Sign out?',
                    message: 'Are you sure you want to sign out?',
                    confirmLabel: 'Sign out',
                  )) {
                    vm.signOut.execute();
                  }
                },
                null,
              ),
              (
                Icons.delete_forever_outlined,
                'Delete account',
                () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => DeleteAccountDialog(viewModel: vm),
                ),
                error,
              ),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(icon, size: 20, color: color),
                title: Text(label, style: TextStyle(color: color)),
                onTap: onTap,
              ),
            Text(
              '$appName v$appVersion',
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
