import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../chat/view_models/chat_list_viewmodel.dart';
import '../../chat/widgets/chat_tab.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../../group_tournaments/view_models/group_tournaments_viewmodel.dart';
import '../../group_tournaments/widgets/group_tournaments_tab.dart';
import '../../playbook/widgets/playbook_tab.dart';
import '../../schedule/widgets/team_events_tab.dart';
import '../../stats/view_models/stats_viewmodel.dart';
import '../../stats/widgets/stats_tab.dart';
import '../../videos/view_models/team_videos_viewmodel.dart';
import '../../videos/widgets/videos_tab.dart';
import '../view_models/team_detail_viewmodel.dart';
import 'members_tab.dart';
import 'roster_tab.dart';

/// The parts of a team members open from its home page, in display order.
enum TeamSection {
  events('Team Events', Icons.event_outlined, 'events'),
  chat('Chat', Icons.chat_bubble_outline, 'chat'),
  roster('Roster', Icons.badge_outlined, 'roster'),
  playbook('Playbook', Icons.draw_outlined, 'playbook'),
  videos('Videos', Icons.video_library_outlined, 'videos'),
  stats('Stats', Icons.insights_outlined, 'stats'),
  tournaments('Tournaments', Icons.emoji_events_outlined, 'tournaments'),
  members('Members', Icons.groups_outlined, 'members');

  const TeamSection(this.label, this.icon, this.path);
  final String label;
  final IconData icon;

  /// Last segment of the section's route, e.g. `/teams/{id}/events`.
  final String path;

  String route(String teamId) => switch (this) {
    events => Routes.teamEvents(teamId),
    chat => Routes.teamChat(teamId),
    roster => Routes.teamRoster(teamId),
    playbook => Routes.teamPlaybook(teamId),
    videos => Routes.teamVideos(teamId),
    stats => Routes.teamStats(teamId),
    tournaments => Routes.teamTournaments(teamId),
    members => Routes.teamMembers(teamId),
  };

  /// Sections a team or community group has, in display order. Groups
  /// don't keep a roster, plays, videos or stats; only they run
  /// tournaments.
  static List<TeamSection> forKind(TeamKind kind) => switch (kind) {
    TeamKind.team => values.where((s) => s != tournaments).toList(),
    TeamKind.community => const [events, chat, tournaments, members],
  };

  /// "Team Events" is just "Events" in a group.
  String labelFor(TeamKind kind) =>
      this == events && kind == TeamKind.community ? 'Events' : label;

  /// The section named [path] (e.g. `?section=events`), if any.
  static TeamSection? fromPath(String? path) =>
      values.where((s) => s.path == path).firstOrNull;

  /// The section an old `?tab=` link meant, when teams had tabs; the
  /// Schedule tab is now Team Events.
  static TeamSection? fromLegacyTab(String? tab) => tab == 'schedule'
      ? events
      : values.where((s) => s.name == tab).firstOrNull;
}

/// One section's content, e.g. the Team Events list or the roster: a tab
/// of the team page. Reports failed actions in a snack bar.
class TeamSectionBody extends StatefulWidget {
  const TeamSectionBody({
    super.key,
    required this.viewModel,
    required this.section,
  });

  final TeamDetailViewModel viewModel;
  final TeamSection section;

  @override
  State<TeamSectionBody> createState() => _TeamSectionBodyState();
}

class _TeamSectionBodyState extends State<TeamSectionBody> {
  TeamDetailViewModel get vm => widget.viewModel;

  late final List<Command<void>> _commands = [
    vm.savePlayer,
    vm.deletePlayer,
    vm.regenerateInviteCode,
    vm.setMemberRole,
    vm.transferOwnership,
    vm.setStatKeeper,
    vm.removeMember,
    vm.deletePlay,
    vm.approveJoinRequest,
    vm.declineJoinRequest,
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
  }

  Widget _body() => switch (widget.section) {
    TeamSection.events => TeamEventsTab(viewModel: vm),
    TeamSection.chat => ViewModelHost(
      create: (c) => ChatListViewModel(
        teamId: vm.teamId,
        teamRepository: c.read(),
        chatRepository: c.read(),
        authRepository: c.read(),
      ),
      builder: (_, chatVm) => ChatTab(viewModel: chatVm),
    ),
    TeamSection.roster => RosterTab(viewModel: vm),
    TeamSection.playbook => PlaybookTab(viewModel: vm),
    TeamSection.videos => ViewModelHost(
      create: (c) => TeamVideosViewModel(
        teamId: vm.teamId,
        videoRepository: c.read(),
        teamRepository: c.read(),
        authRepository: c.read(),
      ),
      builder: (_, videosVm) => VideosTab(viewModel: videosVm),
    ),
    TeamSection.stats => ViewModelHost(
      create: (c) => StatsViewModel(
        teamId: vm.teamId,
        statsRepository: c.read(),
        eventRepository: c.read(),
        teamRepository: c.read(),
        authRepository: c.read(),
      ),
      builder: (_, statsVm) => StatsTab(viewModel: statsVm),
    ),
    TeamSection.tournaments => ViewModelHost(
      create: (c) => GroupTournamentsViewModel(
        groupId: vm.teamId,
        teamRepository: c.read(),
        tournamentRepository: c.read(),
        authRepository: c.read(),
      ),
      builder: (_, tvm) => GroupTournamentsTab(viewModel: tvm),
    ),
    TeamSection.members => MembersTab(viewModel: vm),
  };

  @override
  Widget build(BuildContext context) => _body();
}

/// One section of a team on a page of its own.
class TeamSectionScreen extends StatelessWidget {
  const TeamSectionScreen({
    super.key,
    required this.viewModel,
    required this.section,
  });

  final TeamDetailViewModel viewModel;
  final TeamSection section;

  TeamDetailViewModel get vm => viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final team = vm.team;
        final leading = backOr(context, Routes.team(vm.teamId));
        if (!vm.loaded) {
          return Scaffold(
            appBar: AppBar(leading: leading),
            body: const LoadingView(),
          );
        }
        if (team == null) {
          return Scaffold(
            appBar: AppBar(leading: leading),
            body: vm.error != null
                ? ErrorView(error: vm.error)
                : const EmptyView(
                    icon: Icons.group_off_outlined,
                    title: 'Team not available',
                    message: 'It may have been deleted or you were removed.',
                  ),
          );
        }
        if (!TeamSection.forKind(team.kind).contains(section)) {
          return Scaffold(
            appBar: AppBar(leading: leading),
            body: EmptyView(
              icon: section.icon,
              title: 'Not in community groups',
              message:
                  'Groups have events, chat, tournaments and members. '
                  '${section.label} is for teams.',
            ),
          );
        }
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            leading: leading,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(section.labelFor(team.kind)),
                Text(
                  team.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          body: TeamSectionBody(viewModel: vm, section: section),
        );
      },
    );
  }
}
