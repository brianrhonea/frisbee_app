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
import '../../groups/widgets/group_map.dart';
import '../../schedule/widgets/event_style.dart';
import '../../schedule/widgets/team_events_tab.dart';
import '../view_models/team_detail_viewmodel.dart';
import '../view_models/team_home_viewmodel.dart';
import 'invite_members_dialog.dart';
import 'join_team_dialog.dart';
import 'team_form.dart';
import 'team_post_widgets.dart';
import 'team_section_screen.dart';

enum _MenuAction { edit, leave, delete }

/// A team's home page. Members see a summary, tabs for each section, what's
/// coming up and the team's posts; anyone else sees the public page. The
/// tabs show their section in place, under a compact header.
class TeamHomeScreen extends StatefulWidget {
  const TeamHomeScreen({super.key, required this.viewModel, this.section});

  final TeamHomeViewModel viewModel;

  /// The open tab; null for the overview.
  final TeamSection? section;

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
      case _MenuAction.edit:
        final updated = await showDialog<NewTeam>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(team.isCommunity ? 'Edit group' : 'Edit team'),
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
            (true, false) => 'You can rejoin from the group page any time.',
          },
          confirmLabel: 'Leave',
          destructive: true,
        )) {
          vm.leaveTeam.execute();
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
        if (team != null &&
            section != null &&
            TeamSection.forKind(team.kind).contains(section)) {
          return Scaffold(
            appBar: mobile
                ? AppBar(
                    leading: leading,
                    title: Text(summary.name),
                    actions: [?menu],
                  )
                : null,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  viewModel: vm,
                  summary: summary,
                  section: section,
                  menu: mobile ? null : menu,
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
          appBar: mobile
              ? AppBar(
                  leading: leading,
                  title: Text(summary.name),
                  actions: [?menu],
                )
              : null,
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
                side: [..._events(context), _details(summary)],
                narrow: [
                  _about(summary),
                  if (!vm.isMember) _joinCard(summary),
                  ..._events(context),
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

  Widget _menu(Team team) {
    final noun = team.isCommunity ? 'group' : 'team';
    return PopupMenuButton<_MenuAction>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz),
      onSelected: (a) => _onMenu(a, team),
      itemBuilder: (_) => [
        if (vm.canEdit)
          PopupMenuItem(value: _MenuAction.edit, child: Text('Edit $noun')),
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
                            '${summary.isCommunity ? 'group' : 'team'} is '
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
      title: summary.isCommunity ? 'Group details' : 'Club details',
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
                      ? 'Organizers approve new members.'
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
                onTap: () => context.go(TeamSection.events.route(vm.teamId)),
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
      if (summary.isCommunity)
        'pickup group'
      else
        '${summary.division.label} ${summary.level.label}',
    ].join(' ').toUpperCase();
    final count = vm.memberCount;
    final actions = <Widget>[
      if (vm.isMember)
        OutlinedButton.icon(
          onPressed: () => context.go(TeamSection.chat.route(teamId)),
          icon: const Icon(Icons.chat_bubble_outline, size: 17),
          label: const Text('Message'),
        ),
      if (vm.team case final team? when vm.canEdit)
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
                // Phones put the buttons below the name, side by side.
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
                  _TeamTabs(teamId: teamId, kind: summary.kind, selected: null)
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

/// Overview plus a tab per section. Switching tabs stays on the team page.
class _TeamTabs extends StatelessWidget {
  const _TeamTabs({
    required this.teamId,
    required this.kind,
    required this.selected,
  });

  final String teamId;
  final TeamKind kind;

  /// Null for the overview.
  final TeamSection? selected;

  @override
  Widget build(BuildContext context) {
    final sections = TeamSection.forKind(kind);
    final current = selected;
    return UnderlineTabs(
      labels: ['Overview', for (final s in sections) s.labelFor(kind)],
      selected: current == null ? 0 : sections.indexOf(current) + 1,
      onSelect: (i) => context.go(
        i == 0 ? Routes.team(teamId) : sections[i - 1].route(teamId),
      ),
    );
  }
}

/// The top of a section tab: the team's badge and name, then the tabs.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.viewModel,
    required this.summary,
    required this.section,
    required this.menu,
  });

  final TeamHomeViewModel viewModel;
  final TeamListing summary;
  final TeamSection section;
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
              selected: section,
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
        onTap: () => context.go(TeamSection.members.route(team.id)),
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
            (true, _) => 'Request sent. An organizer will let you in soon.',
            (false, true) =>
              'Organizers approve new members. Ask to join to see '
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
