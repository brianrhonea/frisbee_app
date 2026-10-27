import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../playbook/widgets/playbook_tab.dart';
import '../view_models/team_detail_viewmodel.dart';
import 'members_tab.dart';
import 'roster_tab.dart';
import 'team_form.dart';

enum _MenuAction { edit, leave, delete }

class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({super.key, required this.viewModel});

  final TeamDetailViewModel viewModel;

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  TeamDetailViewModel get vm => widget.viewModel;

  late final List<Command<void>> _commands = [
    vm.updateTeam,
    vm.savePlayer,
    vm.deletePlayer,
    vm.regenerateInviteCode,
    vm.setMemberRole,
    vm.removeMember,
    vm.leaveTeam,
    vm.deleteTeam,
    vm.deletePlay,
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
    if (vm.leaveTeam.completed || vm.deleteTeam.completed) {
      vm.leaveTeam.clearResult();
      vm.deleteTeam.clearResult();
      context.go(Routes.teams);
      return;
    }
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  Future<void> _onMenu(_MenuAction action, Team team) async {
    switch (action) {
      case _MenuAction.edit:
        final updated = await showDialog<NewTeam>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Edit team'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: TeamForm(
                  submitLabel: 'Save',
                  initial: NewTeam(
                    name: team.name,
                    division: team.division,
                    level: team.level,
                    city: team.city,
                  ),
                  onSubmit: (t) => Navigator.pop(context, t),
                ),
              ),
            ),
          ),
        );
        if (updated != null) {
          vm.updateTeam.execute(
            team.copyWith(
              name: updated.name,
              division: updated.division,
              level: updated.level,
              city: updated.city,
            ),
          );
        }
      case _MenuAction.leave:
        if (await confirmDialog(
          context,
          title: 'Leave ${team.name}?',
          message: 'You will need a new invite code to rejoin.',
          confirmLabel: 'Leave',
          destructive: true,
        )) {
          vm.leaveTeam.execute();
        }
      case _MenuAction.delete:
        if (await confirmDialog(
          context,
          title: 'Delete ${team.name}?',
          message:
              'This permanently deletes the team, its roster and playbook.',
          confirmLabel: 'Delete',
          destructive: true,
        )) {
          vm.deleteTeam.execute();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final team = vm.team;
        if (!vm.loaded) {
          return Scaffold(appBar: AppBar(), body: const LoadingView());
        }
        if (team == null) {
          return Scaffold(
            appBar: AppBar(),
            body: vm.error != null
                ? ErrorView(error: vm.error)
                : const EmptyView(
                    icon: Icons.group_off_outlined,
                    title: 'Team not available',
                    message: 'It may have been deleted or you were removed.',
                  ),
          );
        }
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(team.name),
              actions: [
                PopupMenuButton<_MenuAction>(
                  onSelected: (a) => _onMenu(a, team),
                  itemBuilder: (_) => [
                    if (vm.canEdit)
                      const PopupMenuItem(
                        value: _MenuAction.edit,
                        child: Text('Edit team'),
                      ),
                    if (!vm.isOwner)
                      const PopupMenuItem(
                        value: _MenuAction.leave,
                        child: Text('Leave team'),
                      ),
                    if (vm.isOwner)
                      const PopupMenuItem(
                        value: _MenuAction.delete,
                        child: Text('Delete team'),
                      ),
                  ],
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Roster'),
                  Tab(text: 'Playbook'),
                  Tab(text: 'Members'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                RosterTab(viewModel: vm),
                PlaybookTab(viewModel: vm),
                MembersTab(viewModel: vm),
              ],
            ),
          ),
        );
      },
    );
  }
}
