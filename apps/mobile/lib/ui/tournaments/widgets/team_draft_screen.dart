import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../utils/command.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/scoreboard.dart' show ScoreText;
import '../../core/ui/status_views.dart';
import '../../group_tournaments/widgets/hat_parts.dart';
import '../view_models/team_draft_viewmodel.dart';

/// The host turns a division's accepted players into teams: deal balanced
/// teams, then move players, rename teams and pick captains.
class TeamDraftScreen extends StatefulWidget {
  const TeamDraftScreen({super.key, required this.viewModel});

  final TeamDraftViewModel viewModel;

  @override
  State<TeamDraftScreen> createState() => _TeamDraftScreenState();
}

class _TeamDraftScreenState extends State<TeamDraftScreen> {
  TeamDraftViewModel get vm => widget.viewModel;
  late final List<Command<void>> _commands = vm.commands;

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
    if (vm.save.completed) {
      vm.save.clearResult();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Teams saved.')));
      context.pop();
      return;
    }
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  Future<void> _rename(TournamentTeam team) async {
    final controller = TextEditingController(text: team.name);
    final name = await showDialog<String>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('Team name'),
        content: TextField(
          controller: controller,
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
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) vm.rename(team.id, name.trim());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        if (!vm.loaded) {
          return Scaffold(appBar: AppBar(), body: const LoadingState());
        }
        final d = vm.division;
        if (d == null) {
          return Scaffold(
            appBar: AppBar(),
            body: vm.error != null
                ? ErrorState(error: vm.error)
                : const EmptyState(
                    icon: Icons.groups_outlined,
                    title: 'Division not found',
                    message: 'It may have been removed.',
                  ),
          );
        }
        final c = AppColors.of(context);
        return Scaffold(
          appBar: AppBar(title: Text('Draft teams · ${d.label}')),
          body: _body(context),
          bottomNavigationBar: vm.created
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.card,
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: vm.save.running || vm.teams.isEmpty
                            ? null
                            : () => vm.save.execute(),
                        child: Text(vm.dirty ? 'Save teams' : 'Teams saved'),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  /// MMP and WMP on [team], from the players' signups.
  (int, int) _split(TournamentTeam team) {
    var mmp = 0, wmp = 0;
    for (final id in team.playerIds) {
      switch (vm.signupOf(id)?.gender) {
        case GenderMatch.mmp:
          mmp++;
        case GenderMatch.wmp:
          wmp++;
        case null:
          break;
      }
    }
    return (mmp, wmp);
  }

  Widget _body(BuildContext context) {
    final c = AppColors.of(context);
    final unassigned = vm.unassigned;
    final stale = vm.staleIds;
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '${vm.players.length} accepted '
            '${vm.players.length == 1 ? 'player' : 'players'}'
            '${vm.teams.isEmpty ? '' : ' · ${unassigned.length} not on a team'}'
            '${vm.mixed ? ' · evened by gender match' : ''}.',
            style: TextStyle(fontSize: 13.5, color: c.ink2),
          ),
          const SizedBox(height: 12),
          if (vm.created)
            const NotePanel(
              icon: Icons.groups_outlined,
              title: "The league's teams are made",
              message:
                  'Each captain owns their team and the players are its '
                  'members. Manage rosters on the teams themselves.',
            )
          else if (vm.locked)
            const NotePanel(
              icon: Icons.lock_outline,
              title: 'The schedule is published',
              message:
                  'You can move players, rename teams and change captains, '
                  'but not add or remove teams.',
            )
          else if (vm.fromCaptains)
            const NotePanel(
              icon: Icons.how_to_reg_outlined,
              title: "Drafted by the captains",
              message:
                  'Move players, rename teams or change a captain below, '
                  'then save.',
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Teams',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Fewer teams',
                          color: c.accent,
                          onPressed: vm.teamCount <= 2
                              ? null
                              : () => vm.setTeamCount(vm.teamCount - 1),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        SizedBox(
                          width: 32,
                          child: Center(
                            child: ScoreText('${vm.teamCount}', size: 24),
                          ),
                        ),
                        IconButton(
                          tooltip: 'More teams',
                          color: c.accent,
                          onPressed: vm.teamCount >= vm.maxTeams
                              ? null
                              : () => vm.setTeamCount(vm.teamCount + 1),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Row(
                        children: [
                          if (vm.teams.isNotEmpty) ...[
                            OutlinedButton.icon(
                              onPressed: vm.reshuffle.running
                                  ? null
                                  : () => vm.reshuffle.execute(),
                              icon: const Icon(Icons.shuffle),
                              label: const Text('Shuffle'),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: vm.draft.running
                                  ? null
                                  : () => vm.draft.execute(),
                              icon: const Icon(Icons.auto_fix_high),
                              label: Text(
                                vm.teams.isEmpty ? 'Deal teams' : 'Deal again',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'Players are dealt strongest first, each to the team '
                        'with the fewest players and the lowest total skill. '
                        'Dealing again replaces the rosters below.',
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (stale.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Fixing the rosters is the host's to do.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: c.highlightSoft,
                borderRadius: BorderRadius.circular(controlRadius),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_outlined, color: c.highlightInk),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${stale.length} '
                      '${stale.length == 1 ? 'player is' : 'players are'} on a team '
                      "but no longer accepted.",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.highlightInk,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: c.highlightInk,
                    ),
                    onPressed: vm.removeStale,
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
          ],
          if (vm.teams.isNotEmpty) ...[
            const SizedBox(height: 12),
            _balance(context),
          ],
          if (vm.teams.isNotEmpty && unassigned.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Not on a team',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final p in unassigned)
                    _playerTile(context, p, team: null),
                ],
              ),
            ),
          ],
          for (final team in vm.teams) ...[
            const SizedBox(height: 12),
            _teamCard(context, team),
          ],
        ],
      ),
    );
  }

  /// Each team's size, gender split (mixed divisions) and total skill, to
  /// see at a glance whether the deal is even.
  Widget _balance(BuildContext context) {
    final c = AppColors.of(context);
    final head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: c.muted,
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(width: 96, child: Text('TEAM', style: head)),
                Expanded(
                  child: Text(vm.mixed ? 'MMP / WMP' : 'PLAYERS', style: head),
                ),
                SizedBox(
                  width: 52,
                  child: Text('SKILL', textAlign: TextAlign.end, style: head),
                ),
              ],
            ),
            for (final team in vm.teams) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final (mmp, wmp) = _split(team);
                        return vm.mixed
                            ? GenderSplitBar(
                                mmp: mmp,
                                wmp: wmp,
                                unknown: team.playerIds.length - mmp - wmp,
                              )
                            : GenderSplitBar(
                                mmp: 0,
                                wmp: 0,
                                unknown: team.playerIds.length,
                              );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ScoreText('${vm.skillOf(team)}', size: 18),
                    ),
                  ),
                ],
              ),
            ],
            if (vm.mixed) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                children: [
                  LegendDot(color: genderColor(c, mmp: true), label: 'MMP'),
                  LegendDot(color: genderColor(c, mmp: false), label: 'WMP'),
                  Text(
                    'Skill = total',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _teamCard(BuildContext context, TournamentTeam team) {
    final c = AppColors.of(context);
    final (mmp, wmp) = _split(team);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.only(left: 14, right: 4),
              title: Text(
                team.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
              subtitle: Text(
                '${team.playerIds.length} '
                '${team.playerIds.length == 1 ? 'player' : 'players'} · '
                '${vm.mixed ? '$mmp MMP · $wmp WMP · ' : ''}'
                'skill ${vm.skillOf(team)}',
                style: TextStyle(fontSize: 12.5, color: c.muted),
              ),
              trailing: IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(team),
              ),
            ),
            const Divider(height: 1),
            for (final id in team.playerIds)
              _playerTile(
                context,
                vm.signupOf(id) ??
                    PlayerSignup(
                      uid: id,
                      name: team.nameOf(id),
                      divisionId: vm.divisionId,
                    ),
                team: team,
              ),
            if (team.playerIds.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: Text(
                  'No players yet.',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _playerTile(
    BuildContext context,
    PlayerSignup p, {
    required TournamentTeam? team,
  }) {
    final c = AppColors.of(context);
    final captain = team != null && team.captainId == p.uid;
    final gender = p.gender;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 14, right: 4),
      leading: Icon(
        captain ? Icons.star : Icons.person_outline,
        color: captain ? c.accent : c.muted,
      ),
      title: Text(
        p.name,
        style: TextStyle(
          fontSize: 14,
          fontWeight: captain ? FontWeight.w700 : FontWeight.w600,
          color: c.ink,
        ),
      ),
      subtitle: Row(
        children: [
          if (vm.mixed && gender != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: genderColor(c, mmp: gender == GenderMatch.mmp),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              [
                'Skill ${p.skill}',
                if (p.gender != null) p.gender!.label,
                if (captain) 'Captain',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Move',
        onSelected: (v) {
          if (v == '_captain') {
            vm.setCaptain(team!.id, p.uid);
          } else if (v == '_none') {
            vm.movePlayer(p.uid, teamId: null);
          } else {
            vm.movePlayer(p.uid, teamId: v);
          }
        },
        itemBuilder: (_) => [
          if (team != null && !captain)
            const PopupMenuItem(value: '_captain', child: Text('Make captain')),
          for (final t in vm.teams)
            if (t.id != team?.id)
              PopupMenuItem(value: t.id, child: Text('Move to ${t.name}')),
          if (team != null)
            const PopupMenuItem(value: '_none', child: Text('Take off team')),
        ],
      ),
    );
  }
}
