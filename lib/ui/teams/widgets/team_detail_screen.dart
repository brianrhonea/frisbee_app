import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../chat/view_models/chat_list_viewmodel.dart';
import '../../chat/widgets/chat_tab.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../playbook/widgets/playbook_tab.dart';
import '../../schedule/widgets/schedule_tab.dart';
import '../../core/ui/view_model_host.dart';
import '../../stats/view_models/stats_viewmodel.dart';
import '../../stats/widgets/stats_tab.dart';
import '../view_models/team_detail_viewmodel.dart';
import 'members_tab.dart';
import 'roster_tab.dart';
import 'team_form.dart';

enum _MenuAction { edit, leave, delete }

/// Team detail tabs, in display order. Linkable via `Routes.team(tab:)`.
enum TeamTab {
  schedule('Schedule'),
  chat('Chat'),
  roster('Roster'),
  playbook('Playbook'),
  stats('Stats'),
  members('Members');

  const TeamTab(this.label);
  final String label;

  static TeamTab byName(String? name) =>
      values.where((t) => t.name == name).firstOrNull ?? schedule;
}

class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({
    super.key,
    required this.viewModel,
    this.initialTab = TeamTab.schedule,
  });

  final TeamDetailViewModel viewModel;
  final TeamTab initialTab;

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
    vm.transferOwnership,
    vm.setStatKeeper,
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
              'This permanently deletes the team, its roster, schedule and playbook.',
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
          length: TeamTab.values.length,
          initialIndex: widget.initialTab.index,
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
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final t in TeamTab.values) Tab(text: t.label)],
              ),
            ),
            body: TabBarView(
              children: [
                ScheduleTab(viewModel: vm),
                ViewModelHost(
                  create: (c) => ChatListViewModel(
                    teamId: vm.teamId,
                    teamRepository: c.read(),
                    chatRepository: c.read(),
                    authRepository: c.read(),
                  ),
                  builder: (_, chatVm) => ChatTab(viewModel: chatVm),
                ),
                RosterTab(viewModel: vm),
                PlaybookTab(viewModel: vm),
                ViewModelHost(
                  create: (c) => StatsViewModel(
                    teamId: vm.teamId,
                    statsRepository: c.read(),
                    eventRepository: c.read(),
                    teamRepository: c.read(),
                    authRepository: c.read(),
                  ),
                  builder: (_, statsVm) => StatsTab(viewModel: statsVm),
                ),
                MembersTab(viewModel: vm),
              ],
            ),
          ),
        );
      },
    );
  }
}
