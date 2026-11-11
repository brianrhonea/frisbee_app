import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../utils/command.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
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
          return Scaffold(appBar: AppBar(), body: const LoadingView());
        }
        final d = vm.division;
        if (d == null) {
          return Scaffold(
            appBar: AppBar(),
            body: vm.error != null
                ? ErrorView(error: vm.error)
                : const EmptyView(
                    icon: Icons.groups_outlined,
                    title: 'Division not found',
                    message: 'It may have been removed.',
                  ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text('Draft teams · ${d.label}')),
          body: _body(context),
          bottomNavigationBar: vm.created
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton(
                      onPressed: vm.save.running || vm.teams.isEmpty
                          ? null
                          : () => vm.save.execute(),
                      child: Text(vm.dirty ? 'Save teams' : 'Teams saved'),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
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
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (vm.created)
            const Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.groups_outlined),
                title: Text("The league's teams are made"),
                subtitle: Text(
                  'Each captain owns their team and the players are its '
                  'members. Manage rosters on the teams themselves.',
                ),
              ),
            )
          else if (vm.locked)
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('The schedule is published'),
                subtitle: const Text(
                  'You can move players, rename teams and change captains, '
                  'but not add or remove teams.',
                ),
              ),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Teams', style: theme.textTheme.titleSmall),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Fewer teams',
                          onPressed: vm.teamCount <= 2
                              ? null
                              : () => vm.setTeamCount(vm.teamCount - 1),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          '${vm.teamCount}',
                          style: theme.textTheme.titleMedium,
                        ),
                        IconButton(
                          tooltip: 'More teams',
                          onPressed: vm.teamCount >= vm.maxTeams
                              ? null
                              : () => vm.setTeamCount(vm.teamCount + 1),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: vm.draft.running
                              ? null
                              : () => vm.draft.execute(),
                          icon: const Icon(Icons.auto_fix_high),
                          label: Text(
                            vm.teams.isEmpty ? 'Deal teams' : 'Deal again',
                          ),
                        ),
                        if (vm.teams.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: vm.reshuffle.running
                                ? null
                                : () => vm.reshuffle.execute(),
                            icon: const Icon(Icons.shuffle),
                            label: const Text('Shuffle'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Players are dealt strongest first, each to the team with '
                      'the fewest players and the lowest total skill. '
                      'Dealing again replaces the rosters below.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          if (stale.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text(
                  '${stale.length} '
                  '${stale.length == 1 ? 'player is' : 'players are'} on a team '
                  "but no longer accepted.",
                ),
                trailing: TextButton(
                  onPressed: vm.removeStale,
                  child: const Text('Remove'),
                ),
              ),
            ),
          ],
          if (vm.teams.isNotEmpty && unassigned.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Not on a team', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final p in unassigned) _playerTile(context, p, team: null),
          ],
          for (final team in vm.teams) ...[
            const SizedBox(height: 16),
            _teamCard(context, team),
          ],
        ],
      ),
    );
  }

  Widget _teamCard(BuildContext context, TournamentTeam team) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(team.name, style: theme.textTheme.titleMedium),
              subtitle: Text(
                '${team.playerIds.length} '
                '${team.playerIds.length == 1 ? 'player' : 'players'} · '
                'skill ${vm.skillOf(team)}',
              ),
              trailing: IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(team),
              ),
            ),
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('No players yet.'),
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
    final captain = team != null && team.captainId == p.uid;
    return ListTile(
      dense: true,
      leading: Icon(captain ? Icons.star : Icons.person_outline),
      title: Text(p.name),
      subtitle: Text(
        [
          'Skill ${p.skill}',
          if (p.gender != null) p.gender!.label,
          if (captain) 'Captain',
        ].join(' · '),
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
