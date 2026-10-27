import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/teams_viewmodel.dart';
import 'join_team_dialog.dart';

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key, required this.viewModel});

  final TeamsViewModel viewModel;

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  TeamsViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.joinTeam.addListener(_onJoin);
  }

  @override
  void dispose() {
    vm.joinTeam.removeListener(_onJoin);
    super.dispose();
  }

  void _onJoin() {
    final cmd = vm.joinTeam;
    switch (cmd.result) {
      case Ok<String>(:final value):
        cmd.clearResult();
        context.go(Routes.team(value));
      case Error<String>():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  Future<void> _join() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const JoinTeamDialog(),
    );
    if (code != null) vm.joinTeam.execute(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teams'),
        actions: [
          ListenableBuilder(
            listenable: vm.joinTeam,
            builder: (context, _) => TextButton.icon(
              onPressed: vm.joinTeam.running ? null : _join,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Join'),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(Routes.createTeam),
        icon: const Icon(Icons.add),
        label: const Text('New team'),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (vm.loading) return const LoadingView();
          if (vm.error != null) {
            return ErrorView(error: vm.error, onRetry: vm.retry);
          }
          if (vm.teams.isEmpty) {
            return EmptyView(
              icon: Icons.groups_outlined,
              title: 'No teams yet',
              message: 'Create a team or join one with an invite code.',
              action: OutlinedButton(
                onPressed: _join,
                child: const Text('Join with code'),
              ),
            );
          }
          return ConstrainedContent(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: vm.teams.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) =>
                  _TeamCard(team: vm.teams[i], role: vm.roleIn(vm.teams[i])),
            ),
          );
        },
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team, required this.role});

  final Team team;
  final TeamRole? role;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      team.division.label,
      team.level.label,
      if (team.city.isNotEmpty) team.city,
    ].join(' · ');
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(team.name.isEmpty ? '?' : team.name[0].toUpperCase()),
        ),
        title: Text(team.name),
        subtitle: Text(subtitle),
        trailing: role == null ? null : Chip(label: Text(role!.label)),
        onTap: () => context.go(Routes.team(team.id)),
      ),
    );
  }
}
