import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/meeting/meeting_repository.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../domain/models/team_post.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../../follow/widgets/follow_button.dart';
import '../../groups/widgets/group_map.dart';
import '../../schedule/widgets/event_style.dart';
import '../../schedule/widgets/team_events_tab.dart';
import '../view_models/team_detail_viewmodel.dart';
import '../view_models/team_home_viewmodel.dart';
import 'invite_members_dialog.dart';
import 'join_team_dialog.dart';
import 'team_form.dart';
import 'team_post_widgets.dart';
import 'team_community_sheet.dart';
import 'team_section_screen.dart';

enum _MenuAction { edit, community, leave, delete }

/// Goes to [location], another tab of the team page. On a team pushed over
/// a tournament ([Routes.teamOver]) it swaps the tab in place, keeping the
/// tournament underneath, rather than jumping into the Teams tab.
void goWithinTeam(BuildContext context, String location) {
  final over = GoRouterState.of(
    context,
  ).uri.path.startsWith('${Routes.teamsOverPath}/');
  if (over) {
    context.replace(Routes.asTeamOver(location));
  } else {
    context.go(location);
  }
}

/// A team's home page. Members see a summary, tabs for each section, what's
/// coming up and the team's posts; anyone else sees the public page. The
/// tabs show their section in place, under a compact header.
class TeamHomeScreen extends StatefulWidget {
  const TeamHomeScreen({
    super.key,
    required this.viewModel,
    this.section,
    this.more = false,
  });

  final TeamHomeViewModel viewModel;

  /// The open section; null for the feed (the overview) or More.
  final TeamSection? section;

  /// Whether the More tab's list of sections is open.
  final bool more;

  @override
  State<TeamHomeScreen> createState() => _TeamHomeScreenState();
}

class _TeamHomeScreenState extends State<TeamHomeScreen> {
  TeamHomeViewModel get vm => widget.viewModel;

  late final List<Command<void>> _commands = [
    vm.updateTeam,
    vm.leaveTeam,
    vm.deleteTeam,
    vm.savePost,
    vm.deletePost,
    vm.joinGroup,
    vm.cancelJoinRequest,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
    vm.joinTeam.addListener(_onJoin);
  }

  @override
  void dispose() {
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
    vm.joinTeam.removeListener(_onJoin);
    super.dispose();
  }

  /// The "Deleting…" dialog, while it's up.
  NavigatorState? _deleting;

  void _closeDeleting() {
    _deleting?.pop();
    _deleting = null;
  }

  /// Deleting takes a while: a dialog nobody can dismiss shows each step,
  /// so it's clear the app is working rather than stuck.
  void _showDeleting(String name) {
    final navigator = Navigator.of(context, rootNavigator: true);
    _deleting = navigator;
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: _DeletingDialog(viewModel: vm, name: name),
        ),
      ),
    );
  }

  void _onCommand() {
    if (!vm.deleteTeam.running && _deleting != null) _closeDeleting();
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

  void _onJoin() {
    final cmd = vm.joinTeam;
    switch (cmd.result) {
      case Ok<String>(:final value):
        cmd.clearResult();
        // The code may have been for another team.
        if (value != vm.teamId) context.go(Routes.team(value));
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

  Future<void> _onMenu(_MenuAction action, Team team) async {
    switch (action) {
      case _MenuAction.community:
        await showTeamCommunity(context, team);
      case _MenuAction.edit:
        final updated = await showDialog<NewTeam>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Edit ${team.kind.noun}'),
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
                    kind: team.kind,
                    description: team.description,
                    requiresApproval: team.requiresApproval,
                    location: team.location,
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
              description: updated.description,
              requiresApproval: updated.requiresApproval,
              location: () => updated.location,
            ),
          );
        }
      case _MenuAction.leave:
        if (await confirmDialog(
          context,
          title: 'Leave ${team.name}?',
          message: switch ((team.isCommunity, team.requiresApproval)) {
            (false, _) => 'You will need a new invite code to rejoin.',
            (true, true) => 'To rejoin, you will need to ask again.',
            (true, false) =>
              'You can rejoin from the ${team.kind.noun} page any time.',
          },
          confirmLabel: 'Leave',
          destructive: true,
        )) {
          vm.leaveTeam.execute();
        }
      case _MenuAction.delete when team.members.length > 1:
        // Deleting would take everyone else's team away; hand it on or
        // empty it first.
        final noun = team.kind.noun;
        final others = team.members.length - 1;
        final goToMembers = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text("Can't delete ${team.name} yet"),
            content: Text(
              'It still has $others other '
              '${others == 1 ? 'member' : 'members'}. To delete the $noun, '
              'remove everyone else first. Or, to keep it going without '
              'you, transfer ownership to someone else and then leave.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Go to Members'),
              ),
            ],
          ),
        );
        if (goToMembers == true && mounted) {
          goWithinTeam(
            context,
            Routes.teamSection(team.id, TeamSection.members.path),
          );
        }
      case _MenuAction.delete:
        if (await confirmDialog(
          context,
          title: 'Delete ${team.name}?',
          message: team.isCommunity
              ? 'This permanently deletes the group, its events, '
                    'tournaments, chat and posts.'
              : 'This permanently deletes the team, its roster, events, '
                    'posts and playbook.',
          confirmLabel: 'Delete',
          destructive: true,
        )) {
          if (!mounted) return;
          _showDeleting(team.name);
          vm.deleteTeam.execute();
        }
    }
  }

  Future<void> _editPost([TeamPost? post]) async {
    final draft = await showDialog<PostDraft>(
      context: context,
      builder: (_) => PostEditorDialog(
        initial: post,
        pickImages: vm.pickImages,
        canUseCamera: vm.canUseCamera,
        loadImage: vm.imageData,
        allowPublic: !(vm.team?.isPrivateGroup ?? false),
      ),
    );
    if (draft != null) vm.savePost.execute(draft);
  }

  Future<void> _deletePost(TeamPost post) async {
    if (await confirmDialog(
      context,
      title: 'Delete post?',
      message: 'It will be removed from the team page.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      vm.deletePost.execute(post.id);
    }
  }

  void _openEvent(TeamEvent e) {
    if (vm.isMember) {
      openTeamEvent(context, vm.teamId, e);
    } else {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _PublicEventSheet(event: e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        vm,
        vm.joinTeam,
        vm.joinGroup,
        vm.cancelJoinRequest,
        vm.savePost,
      ]),
      builder: (context, _) {
        final mobile = ScreenSize.of(context).isMobile;
        final leading = backOr(context, Routes.teams);
        final summary = vm.summary;
        if (!vm.loaded || summary == null) {
          return Scaffold(
            appBar: AppBar(leading: leading),
            body: !vm.loaded
                ? const LoadingView()
                : const EmptyView(
                    icon: Icons.group_off_outlined,
                    title: 'Team not available',
                    message: 'It may have been deleted or you were removed.',
                  ),
          );
        }
        final team = vm.team;
        final menu = team == null ? null : _menu(team);
        final section = widget.section;
        final sections = team == null
            ? const <TeamSection>[]
            : TeamSection.forTeam(team);
        final appBar = mobile
            ? AppBar(
                leading: leading,
                title: Text(summary.name),
                actions: [?menu],
              )
            : null;
        final more = TeamTab.moreSections(sections);
        if (widget.more && more.isNotEmpty) {
          return Scaffold(
            appBar: appBar,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  viewModel: vm,
                  summary: summary,
                  tab: TeamTab.more,
                  menu: mobile ? null : menu,
                ),
                Expanded(
                  child: _MoreList(teamId: vm.teamId, sections: more),
                ),
              ],
            ),
          );
        }
        if (team != null && section != null && sections.contains(section)) {
          // A team's players sit beside its members under Roster.
          final players =
              TeamTab.of(section) == TeamTab.roster &&
              sections.contains(TeamSection.roster);
          return Scaffold(
            appBar: appBar,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  viewModel: vm,
                  summary: summary,
                  tab: TeamTab.of(section),
                  menu: mobile ? null : menu,
                ),
                if (players)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Center(
                      child: SegmentedButton<TeamSection>(
                        segments: const [
                          ButtonSegment(
                            value: TeamSection.members,
                            label: Text('Members'),
                          ),
                          ButtonSegment(
                            value: TeamSection.roster,
                            label: Text('Players'),
                          ),
                        ],
                        selected: {section},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            goWithinTeam(context, s.single.route(vm.teamId)),
                      ),
                    ),
                  ),
                Expanded(
                  child: ViewModelHost(
                    key: ValueKey('team-sections-${vm.teamId}'),
                    create: (c) => TeamDetailViewModel(
                      teamId: vm.teamId,
                      teamRepository: c.read(),
                      playRepository: c.read(),
                      eventRepository: c.read(),
                      meetingRepository: c.read<MeetingRepository>(),
                      authRepository: c.read(),
                    ),
                    builder: (_, detail) => ListenableBuilder(
                      listenable: detail,
                      builder: (context, _) => !detail.loaded
                          ? const LoadingView()
                          : detail.team == null
                          ? ErrorView(error: detail.error)
                          : TeamSectionBody(
                              key: ValueKey(section),
                              viewModel: detail,
                              section: section,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: appBar,
          floatingActionButton: mobile && vm.canPost
              ? FloatingActionButton.extended(
                  onPressed: vm.savePost.running ? null : _editPost,
                  icon: const Icon(Icons.post_add),
                  label: const Text('New post'),
                )
              : null,
          body: PageScroll(
            children: [
              if (vm.savePost.running)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(),
                ),
              _Hero(
                viewModel: vm,
                summary: summary,
                menu: mobile ? null : menu,
                onJoin: _join,
              ),
              const SizedBox(height: 16),
              if (team != null && team.isLeagueTeam)
                // A league team is its chat and members; the league page
                // has its games.
                SideColumnLayout(
                  main: [
                    _about(summary),
                    _leagueCard(team),
                    _MembersCard(team: team),
                  ],
                  side: [_details(summary)],
                  narrow: [
                    _about(summary),
                    _leagueCard(team),
                    _MembersCard(team: team),
                    _details(summary),
                  ],
                )
              else
                SideColumnLayout(
                  main: [
                    _about(summary),
                    if (!vm.isMember) _joinCard(summary),
                    if (vm.contentError != null)
                      Text(
                        errorMessage(vm.contentError),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (team != null) _MembersCard(team: team),
                    ..._posts(context),
                  ],
                  side: [
                    ..._events(context),
                    ..._tournaments(context),
                    _details(summary),
                  ],
                  narrow: [
                    _about(summary),
                    if (!vm.isMember) _joinCard(summary),
                    ..._events(context),
                    ..._tournaments(context),
                    if (team != null) _MembersCard(team: team),
                    ..._posts(context),
                    _details(summary),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  /// Where a league team's games are: the league's page, plus its chat.
  Widget _leagueCard(Team team) => SectionCard(
    title: 'League team',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your games, standings and schedule are on the league page. '
          'Talk to your team in chat.',
          style: TextStyle(color: AppColors.of(context).muted, fontSize: 13.5),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => context.push(Routes.tournament(team.leagueId!)),
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('League page'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  goWithinTeam(context, TeamSection.chat.route(team.id)),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Chat'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _menu(Team team) {
    final noun = team.kind.noun;
    return PopupMenuButton<_MenuAction>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz),
      onSelected: (a) => _onMenu(a, team),
      itemBuilder: (_) => [
        if (vm.canEdit)
          PopupMenuItem(value: _MenuAction.edit, child: Text('Edit $noun')),
        if (vm.canEdit && !team.isCommunity)
          const PopupMenuItem(
            value: _MenuAction.community,
            child: Text('School or club'),
          ),
        if (!vm.isOwner)
          PopupMenuItem(value: _MenuAction.leave, child: Text('Leave $noun')),
        if (vm.isOwner)
          PopupMenuItem(value: _MenuAction.delete, child: Text('Delete $noun')),
      ],
    );
  }

  Widget _about(TeamListing summary) {
    final c = AppColors.of(context);
    final upcoming = vm.upcomingEvents.length;
    return SectionCard(
      title: summary.isCommunity ? 'About the group' : 'About the team',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.description.isEmpty
                ? (vm.canEdit
                      ? 'Add a description so people know what the '
                            '${summary.kind.noun} is '
                            'about.'
                      : 'No description yet.')
                : summary.description,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: summary.description.isEmpty ? c.muted : c.ink,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (summary.isCommunity) ...[
                Tag(summary.kind.label),
                Tag(
                  summary.requiresApproval
                      ? 'Approval to join'
                      : 'Open to join',
                ),
              ] else ...[
                Tag(summary.division.label),
                Tag(summary.level.label),
              ],
              if (summary.city.isNotEmpty) Tag(summary.city),
            ],
          ),
          if (vm.isMember) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: StatBlock(
                    value: '${vm.memberCount}',
                    label: summary.isCommunity ? 'Members' : 'Rostered',
                  ),
                ),
                Expanded(
                  child: StatBlock(value: '$upcoming', label: 'Upcoming'),
                ),
                Expanded(
                  child: StatBlock(value: '${vm.posts.length}', label: 'Posts'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _joinCard(TeamListing summary) => summary.isCommunity
      ? _GroupJoinCard(
          requiresApproval: summary.requiresApproval,
          pending: vm.requestPending,
          busy: vm.joinGroup.running || vm.cancelJoinRequest.running,
          onJoin: vm.joinGroup.execute,
          onCancel: vm.cancelJoinRequest.execute,
        )
      : _JoinCard(joining: vm.joinTeam.running, onJoin: _join);

  Widget _details(TeamListing summary) {
    final c = AppColors.of(context);
    final location = summary.location;
    final role = vm.myRole;
    return SectionCard(
      title: summary.isOrganization
          ? 'Community details'
          : summary.isCommunity
          ? 'Group details'
          : 'Club details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (location != null) ...[
            GroupMapCard(location: location),
            const SizedBox(height: 10),
          ],
          for (final (icon, text) in [
            if (summary.city.isNotEmpty) (Icons.place_outlined, summary.city),
            (Icons.groups_outlined, summary.subtitle),
            if (role != null)
              (Icons.badge_outlined, 'You: ${role.labelFor(summary.kind)}'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(fontSize: 12.5, color: c.ink),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            summary.isCommunity
                ? (summary.requiresApproval
                      ? "The group's admins approve new members."
                      : 'Open to new players. Join any time.')
                : 'Joining takes an invite code from a coach or captain.',
            style: TextStyle(fontSize: 11.5, color: c.muted),
          ),
        ],
      ),
    );
  }

  List<Widget> _events(BuildContext context) {
    final events = vm.upcomingEvents;
    // Nothing public to show isn't worth a card on the public page.
    if (events.isEmpty && !vm.isMember) return const [];
    final next = events.firstOrNull;
    final rest = events.skip(1).take(TeamHomeViewModel.upcomingLimit).toList();
    return [
      if (next != null)
        _UpNextCard(
          event: next,
          teamName: vm.summary?.name ?? '',
          onOpen: () => _openEvent(next),
        ),
      SectionCard(
        title: next == null ? 'Up next' : 'Coming up',
        action: vm.isMember
            ? CardLink(
                label: 'All events',
                onTap: () =>
                    goWithinTeam(context, TeamSection.events.route(vm.teamId)),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rest.isEmpty)
              _Note(
                next == null
                    ? 'Nothing scheduled yet.'
                    : 'Nothing else '
                          'scheduled yet.',
              ),
            for (final e in rest)
              _EventRow(event: e, onTap: () => _openEvent(e)),
          ],
        ),
      ),
    ];
  }

  /// A group's tournaments, which anyone can open and follow. Members
  /// have the full list in the Tournaments tab.
  List<Widget> _tournaments(BuildContext context) {
    final listings = vm.tournamentListings;
    if (listings.isEmpty || vm.isMember) return const [];
    final c = AppColors.of(context);
    final day = DateFormat.MMMd();
    return [
      SectionCard(
        title: 'Tournaments',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final t in listings.take(5))
              InkWell(
                borderRadius: BorderRadius.circular(controlRadius),
                onTap: () => context.push(
                  Routes.groupTournament(t.groupId, t.tournamentId),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.emoji_events_outlined,
                        size: 18,
                        color: c.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: c.ink,
                              ),
                            ),
                            Text(
                              '${day.format(t.startsAt)} · ${t.format.label}',
                              style: TextStyle(fontSize: 12, color: c.muted),
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
      ),
    ];
  }

  List<Widget> _posts(BuildContext context) {
    final posts = vm.posts;
    if (vm.isPrivateToMe) {
      return const [
        _Note(
          'This is a private group. Its location, events and posts are '
          'only visible to members.',
        ),
      ];
    }
    if (posts.isEmpty && !vm.isMember) {
      return vm.upcomingEvents.isEmpty
          ? [
              _Note(
                "This ${vm.isGroup ? 'group' : 'team'} hasn't shared "
                'anything publicly yet.',
              ),
            ]
          : const [];
    }
    final c = AppColors.of(context);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                vm.isGroup ? 'From the group' : 'From the team',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: c.ink,
                ),
              ),
            ),
            if (vm.canPost && !ScreenSize.of(context).isMobile)
              TextButton.icon(
                onPressed: vm.savePost.running ? null : _editPost,
                icon: const Icon(Icons.post_add, size: 18),
                label: const Text('New post'),
              ),
          ],
        ),
      ),
      if (posts.isEmpty)
        _Note(
          vm.canPost
              ? 'Post news for the team: tryouts, fees, field changes. '
                    'Make a post public to show it to anyone who finds '
                    'the team.'
              : 'No posts yet.',
        ),
      for (final p in posts)
        TeamPostCard(
          post: p,
          loadImage: vm.imageData,
          showVisibility: vm.isMember,
          onEdit: vm.canPost ? () => _editPost(p) : null,
          onDelete: vm.canPost ? () => _deletePost(p) : null,
        ),
    ];
  }
}

/// The banner, name, actions and section tabs at the top of the page.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.viewModel,
    required this.summary,
    required this.menu,
    required this.onJoin,
  });

  final TeamHomeViewModel viewModel;
  final TeamListing summary;
  final Widget? menu;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final mobile = ScreenSize.of(context).isMobile;
    final teamId = vm.teamId;
    final founded = vm.team?.createdAt?.year;
    final banner = [
      if (summary.city.isNotEmpty) summary.city,
      if (summary.isOrganization)
        'school or club'
      else if (summary.isCommunity)
        'pickup group'
      else
        '${summary.division.label} ${summary.level.label}',
    ].join(' ').toUpperCase();
    final count = vm.memberCount;
    final follow = switch (vm.follow) {
      final f? => FollowControl(viewModel: f, showCount: true),
      null => null,
    };
    final actions = <Widget>[
      if (vm.team case final team? when team.inCommunity)
        ActionChip(
          avatar: const Icon(Icons.account_balance_outlined, size: 18),
          label: Text(team.orgName.isEmpty ? 'Community' : team.orgName),
          tooltip: 'Open the community',
          onPressed: () => context.push(Routes.team(team.orgId!)),
        ),
      if (!mobile) ?follow,
      if (vm.isMember)
        OutlinedButton.icon(
          onPressed: () =>
              goWithinTeam(context, TeamSection.chat.route(teamId)),
          icon: const Icon(Icons.chat_bubble_outline, size: 17),
          label: const Text('Message'),
        ),
      if (vm.team case final team? when vm.canManageMembers)
        FilledButton.icon(
          onPressed: () => showInviteMembers(context, team),
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: Text(
            summary.isCommunity ? 'Invite members' : 'Invite players',
          ),
        ),
      ?menu,
    ];
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: mobile ? 120 : 170,
            child: CustomPaint(
              painter: _BannerPainter(
                base: c.feature,
                accent: c.highlight,
                light: c.featureHighlight,
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Tag(banner, strong: true),
                    const Spacer(),
                    if (founded != null)
                      Text(
                        'EST. $founded',
                        style: TextStyle(
                          color: c.onFeature,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(mobile ? 14 : 20, 16, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TeamBadge(
                          size: mobile ? 48 : 58,
                          community: summary.isCommunity,
                        ),
                        const SizedBox(width: 14),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: mobile ? 240 : 420,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                summary.name,
                                style: TextStyle(
                                  fontSize: mobile ? 22 : 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.9,
                                  height: 1.1,
                                  color: c.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                summary.subtitle,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: c.muted,
                                ),
                              ),
                              if (summary.official) ...[
                                const SizedBox(height: 6),
                                const OfficialBadge(
                                  label: 'Official organizer',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (actions.isNotEmpty && !mobile)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < actions.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            actions[i],
                          ],
                        ],
                      ),
                  ],
                ),
                // Phones put the buttons below the name, side by side,
                // with Follow on its own line.
                if (follow != null && mobile) ...[
                  const SizedBox(height: 14),
                  Align(alignment: Alignment.centerLeft, child: follow),
                ],
                if (actions.isNotEmpty && mobile) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        vm.isMember
                            ? '$count ${count == 1 ? 'member' : 'members'}'
                                  ' · ${vm.upcomingEvents.length} upcoming'
                            : summary.isCommunity
                            ? 'Community group'
                            : 'Team',
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ),
                    if (vm.myRole case final role?)
                      Tag('You: ${role.labelFor(summary.kind)}'),
                  ],
                ),
                const SizedBox(height: 6),
                if (vm.isMember)
                  _TeamTabs(
                    teamId: teamId,
                    kind: summary.kind,
                    league: vm.team?.isLeagueTeam ?? false,
                    selected: TeamTab.feed,
                  )
                else
                  const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The page's [TeamTab]s. Switching tabs stays on the team page.
class _TeamTabs extends StatelessWidget {
  const _TeamTabs({
    required this.teamId,
    required this.kind,
    required this.selected,
    this.league = false,
  });

  /// A league team: just chat and members.
  final bool league;

  final String teamId;
  final TeamKind kind;
  final TeamTab selected;

  @override
  Widget build(BuildContext context) {
    final tabs = TeamTab.forSections(TeamSection.forKind(kind, league: league));
    return UnderlineTabs(
      labels: [for (final t in tabs) t.label],
      selected: tabs.indexOf(selected),
      onSelect: (i) => goWithinTeam(context, tabs[i].route(teamId)),
    );
  }
}

/// The More tab: the team's other sections, one row each.
class _MoreList extends StatelessWidget {
  const _MoreList({required this.teamId, required this.sections});

  final String teamId;
  final List<TeamSection> sections;

  @override
  Widget build(BuildContext context) => ConstrainedContent(
    maxWidth: 720,
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final s in sections)
          ListTile(
            leading: Icon(s.icon),
            title: Text(s.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => goWithinTeam(context, s.route(teamId)),
          ),
      ],
    ),
  );
}

/// The top of a tab: the team's badge and name, then the tabs.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.viewModel,
    required this.summary,
    required this.tab,
    required this.menu,
  });

  final TeamHomeViewModel viewModel;
  final TeamListing summary;
  final TeamTab tab;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final mobile = ScreenSize.of(context).isMobile;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(mobile ? 16 : 24, mobile ? 4 : 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!mobile)
              Row(
                children: [
                  TeamBadge(size: 40, community: summary.isCommunity),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.name,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: c.ink,
                          ),
                        ),
                        Text(
                          summary.subtitle,
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  ?menu,
                ],
              ),
            _TeamTabs(
              teamId: viewModel.teamId,
              kind: summary.kind,
              league: viewModel.team?.isLeagueTeam ?? false,
              selected: tab,
            ),
          ],
        ),
      ),
    );
  }
}

/// A placeholder team photo: dark green with arcs like a disc in flight.
class _BannerPainter extends CustomPainter {
  _BannerPainter({
    required this.base,
    required this.accent,
    required this.light,
  });

  final Color base;
  final Color accent;
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, light, 0.9)!],
        ).createShader(rect),
    );
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < 6; i++) {
      arc.color = accent.withValues(alpha: 0.05 + i * 0.025);
      final r = size.width * (0.18 + i * 0.09);
      canvas.drawCircle(Offset(size.width * 0.92, size.height * 1.35), r, arc);
    }
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.32),
      size.height * 0.11,
      Paint()..color = accent.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_BannerPainter old) =>
      old.base != base || old.accent != accent || old.light != light;
}

/// The team's next event on a dark card.
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({
    required this.event,
    required this.teamName,
    required this.onOpen,
  });

  final TeamEvent event;
  final String teamName;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final e = event;
    return FeatureCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Eyebrow(
                  'Up next · ${e.type.label}',
                  color: c.onFeatureMuted,
                ),
              ),
              Icon(Icons.north_east, size: 15, color: c.highlight),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            e.title,
            style: TextStyle(
              color: c.onFeature,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${DateFormat.MMMEd().format(e.startsAt)} · ${eventTimeRange(e)}',
            style: TextStyle(
              color: c.onFeature,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          if (e.location.isNotEmpty)
            Text(
              e.location,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.onFeatureMuted, fontSize: 12),
            ),
          const SizedBox(height: 14),
          HighlightButton(label: 'View details', onPressed: onOpen),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onTap});

  final TeamEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final e = event;
    final going = e.responders(RsvpStatus.going).length;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            DateBadge(date: e.startsAt, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    [
                      e.type.label,
                      eventTimeRange(e),
                      if (going > 0) '$going going',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A few members with their roles, linking to the full list.
class _MembersCard extends StatelessWidget {
  const _MembersCard({required this.team});

  final Team team;

  static const _shown = 6;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final members = team.members.entries.toList()
      ..sort((a, b) {
        final byRole = a.value.index.compareTo(b.value.index);
        if (byRole != 0) return byRole;
        return (team.memberNames[a.key] ?? '').compareTo(
          team.memberNames[b.key] ?? '',
        );
      });
    final count = members.length;
    return SectionCard(
      title: team.isCommunity ? 'Meet the group' : 'Meet the sideline',
      action: CardLink(
        label: 'All $count ${team.isCommunity ? 'members' : 'players'}',
        onTap: () => goWithinTeam(context, TeamSection.members.route(team.id)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 520 ? 3 : 2;
          const gap = 10.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final MapEntry(key: uid, value: role) in members.take(
                _shown,
              ))
                SizedBox(
                  width: width,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.field,
                      borderRadius: BorderRadius.circular(controlRadius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PersonAvatar(
                          name: team.memberNames[uid] ?? '?',
                          radius: 17,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          team.memberNames[uid] ?? 'Member',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Eyebrow(team.roleLabel(role)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _JoinCard extends StatelessWidget {
  const _JoinCard({required this.joining, required this.onJoin});

  final bool joining;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Row(
      children: [
        const Icon(Icons.lock_outline),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            "You're not on this team. Ask a coach or captain for the "
            'invite code to join.',
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: joining ? null : onJoin,
          child: const Text('Join'),
        ),
      ],
    ),
  );
}

/// Join (or ask to join) a community group.
class _GroupJoinCard extends StatelessWidget {
  const _GroupJoinCard({
    required this.requiresApproval,
    required this.pending,
    required this.busy,
    required this.onJoin,
    required this.onCancel,
  });

  final bool requiresApproval;
  final bool pending;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Row(
      children: [
        Icon(
          pending
              ? Icons.hourglass_top
              : (requiresApproval
                    ? Icons.how_to_reg_outlined
                    : Icons.group_add_outlined),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(switch ((pending, requiresApproval)) {
            (true, _) => 'Request sent. An admin will let you in soon.',
            (false, true) =>
              'Admins approve new members. Ask to join to see '
                  'members, events and tournaments.',
            (false, false) =>
              'Join to see members, chat, and sign up for pickup and '
                  'tournaments.',
          }),
        ),
        const SizedBox(width: 12),
        if (pending)
          OutlinedButton(
            onPressed: busy ? null : onCancel,
            child: const Text('Cancel request'),
          )
        else
          FilledButton(
            onPressed: busy ? null : onJoin,
            child: Text(requiresApproval ? 'Ask to join' : 'Join'),
          ),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 12.5, color: AppColors.of(context).muted),
    ),
  );
}

/// A public event's details, for people outside the team.
class _PublicEventSheet extends StatelessWidget {
  const _PublicEventSheet({required this.event});

  final TeamEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = event;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(e.type.icon, color: e.type.color(theme.colorScheme)),
                const SizedBox(width: 8),
                Text(e.type.label, style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(e.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(DateFormat.yMMMMEEEEd().format(e.startsAt)),
              subtitle: Text(eventTimeRange(e)),
            ),
            if (e.location.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: SelectableText(e.location),
              ),
            if (e.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(e.notes, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown while a team is deleted: a progress bar and the step it's on.
class _DeletingDialog extends StatelessWidget {
  const _DeletingDialog({required this.viewModel, required this.name});

  final TeamHomeViewModel viewModel;
  final String name;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final p = viewModel.deleteProgress;
      final value = p == null || p.total == 0 ? null : p.done / p.total;
      return AlertDialog(
        title: Text('Deleting $name'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: value, minHeight: 8),
              ),
              const SizedBox(height: 12),
              Text(
                [
                  p?.step ?? 'Getting ready',
                  if (value != null) '${(value * 100).round()}%',
                ].join(' · '),
              ),
              const SizedBox(height: 4),
              Text(
                'This can take a minute. Keep the app open until it '
                'finishes.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}
