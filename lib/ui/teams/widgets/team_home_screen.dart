import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../domain/models/team_post.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../groups/widgets/group_map.dart';
import '../../schedule/widgets/event_style.dart';
import '../../schedule/widgets/team_events_tab.dart';
import '../view_models/team_home_viewmodel.dart';
import 'join_team_dialog.dart';
import 'team_form.dart';
import 'team_post_widgets.dart';
import 'team_section_screen.dart';
import '../../follow/widgets/follow_button.dart';

enum _MenuAction { edit, leave, delete }

/// Builds the content of a team section tab.
typedef TeamSectionBuilder =
    Widget Function(BuildContext context, TeamSection section);

/// A team's page. Members get a tab bar: Home (a summary, what's coming up
/// and the team's posts) and one tab per section. Switching tabs swaps only
/// the content below the bar. Anyone else sees the public page.
class TeamHomeScreen extends StatefulWidget {
  const TeamHomeScreen({
    super.key,
    required this.viewModel,
    this.section,
    this.sectionBuilder,
  });

  final TeamHomeViewModel viewModel;

  /// The selected tab; null for Home.
  final TeamSection? section;

  /// Builds a section tab's content. Only called for members.
  final TeamSectionBuilder? sectionBuilder;

  @override
  State<TeamHomeScreen> createState() => _TeamHomeScreenState();
}

class _TeamHomeScreenState extends State<TeamHomeScreen>
    with TickerProviderStateMixin {
  TeamHomeViewModel get vm => widget.viewModel;

  TabController? _tabController;

  /// The sections shown as tabs after Home; null when there's no tab bar
  /// (still loading, or not a member).
  List<TeamSection>? get _sections {
    final summary = vm.summary;
    if (summary == null || !vm.isMember) return null;
    return TeamSection.forKind(summary.kind);
  }

  /// The tab for [widget.section]: Home for null or a section this kind of
  /// team doesn't have.
  int _tabIndex(List<TeamSection> sections) {
    final i = widget.section == null ? -1 : sections.indexOf(widget.section!);
    return i + 1;
  }

  /// The controller for the current tabs, replaced when their number
  /// changes (e.g. on joining).
  TabController _tabsFor(List<TeamSection> sections) {
    final length = sections.length + 1;
    final current = _tabController;
    if (current != null && current.length == length) return current;
    if (current != null) {
      // The old TabBar lets go of it during this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return _tabController = TabController(
      length: length,
      initialIndex: _tabIndex(sections),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(TeamHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sections = _sections;
    final controller = _tabController;
    if (sections != null &&
        controller != null &&
        controller.length == sections.length + 1) {
      controller.index = _tabIndex(sections);
    }
  }

  void _selectTab(List<TeamSection> sections, int index) {
    final route = index == 0
        ? Routes.team(vm.teamId)
        : sections[index - 1].route(vm.teamId);
    // `go`, not `push`: tabs replace each other, so back leaves the team.
    context.go(route);
  }

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
    _tabController?.dispose();
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
      context.push(Routes.teamEvent(vm.teamId, e));
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
        final leading = backOr(context, Routes.teams);
        final summary = vm.summary;
        if (!vm.loaded) {
          return Scaffold(
            appBar: AppBar(leading: leading),
            body: const LoadingView(),
          );
        }
        if (summary == null) {
          return Scaffold(
            appBar: AppBar(leading: leading),
            body: const EmptyView(
              icon: Icons.group_off_outlined,
              title: 'Team not available',
              message: 'It may have been deleted or you were removed.',
            ),
          );
        }
        final team = vm.team;
        final noun = summary.isCommunity ? 'group' : 'team';
        final sections = _sections;
        final tabs = sections == null ? null : _tabsFor(sections);
        final section = sections == null || _tabIndex(sections) == 0
            ? null
            : widget.section;
        final sectionBuilder = widget.sectionBuilder;
        return Scaffold(
          appBar: AppBar(
            leading: leading,
            title: Text(summary.name),
            bottom: sections == null
                ? null
                : TabBar(
                    controller: tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    onTap: (i) => _selectTab(sections, i),
                    tabs: [
                      const Tab(text: 'Home'),
                      for (final s in sections)
                        Tab(text: s.labelFor(summary.kind)),
                    ],
                  ),
            actions: [
              if (team != null)
                PopupMenuButton<_MenuAction>(
                  onSelected: (a) => _onMenu(a, team),
                  itemBuilder: (_) => [
                    if (vm.canEdit)
                      PopupMenuItem(
                        value: _MenuAction.edit,
                        child: Text('Edit $noun'),
                      ),
                    if (!vm.isOwner)
                      PopupMenuItem(
                        value: _MenuAction.leave,
                        child: Text('Leave $noun'),
                      ),
                    if (vm.isOwner)
                      PopupMenuItem(
                        value: _MenuAction.delete,
                        child: Text('Delete $noun'),
                      ),
                  ],
                ),
            ],
          ),
          floatingActionButton: section == null && vm.canPost
              ? FloatingActionButton.extended(
                  onPressed: vm.savePost.running ? null : _editPost,
                  icon: const Icon(Icons.post_add),
                  label: const Text('New post'),
                )
              : null,
          body: section != null && sectionBuilder != null
              ? sectionBuilder(context, section)
              : _home(context, summary),
        );
      },
    );
  }

  /// The Home tab, and the whole page for non-members.
  Widget _home(BuildContext context, TeamListing summary) {
    final location = summary.location;
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (vm.savePost.running)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(),
            ),
          _Header(viewModel: vm, summary: summary),
          if (vm.follow case final follow?) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FollowControl(viewModel: follow, showCount: true),
            ),
          ],
          if (summary.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(summary.description),
          ],
          if (!vm.isMember) ...[
            const SizedBox(height: 16),
            if (summary.isCommunity)
              _GroupJoinCard(
                requiresApproval: summary.requiresApproval,
                pending: vm.requestPending,
                busy: vm.joinGroup.running || vm.cancelJoinRequest.running,
                onJoin: vm.joinGroup.execute,
                onCancel: vm.cancelJoinRequest.execute,
              )
            else
              _JoinCard(joining: vm.joinTeam.running, onJoin: _join),
          ],
          if (location != null) ...[
            const SizedBox(height: 16),
            GroupMapCard(location: location),
          ],
          if (vm.contentError != null) ...[
            const SizedBox(height: 16),
            Text(
              errorMessage(vm.contentError),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          ..._events(context),
          ..._tournaments(context),
          ..._posts(context),
        ],
      ),
    );
  }

  /// A group's tournaments, which anyone can open and follow. Members
  /// have the full list in the Tournaments section.
  List<Widget> _tournaments(BuildContext context) {
    final listings = vm.tournamentListings;
    if (listings.isEmpty || vm.isMember) return const [];
    final day = DateFormat.MMMd();
    return [
      const _ListHeader(title: 'Tournaments'),
      for (final t in listings.take(5))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.emoji_events_outlined),
          title: Text(t.name),
          subtitle: Text('${day.format(t.startsAt)} · ${t.format.label}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              context.push(Routes.groupTournament(t.groupId, t.tournamentId)),
        ),
    ];
  }

  List<Widget> _events(BuildContext context) {
    final events = vm.upcomingEvents;
    // Nothing public to show isn't worth a heading on the public page.
    if (events.isEmpty && !vm.isMember) return const [];
    return [
      _ListHeader(
        title: vm.isMember ? 'Up next' : 'Upcoming events',
        action: vm.isMember
            ? TextButton(
                onPressed: () =>
                    context.go(TeamSection.events.route(vm.teamId)),
                child: const Text('See all'),
              )
            : null,
      ),
      if (events.isEmpty)
        const _Note('Nothing scheduled yet.')
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final e in events.take(TeamHomeViewModel.upcomingLimit))
                TeamEventTile(
                  event: e,
                  uid: vm.uid,
                  showResponses: vm.isMember,
                  onTap: () => _openEvent(e),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _posts(BuildContext context) {
    final posts = vm.posts;
    if (posts.isEmpty && !vm.isMember) {
      return vm.upcomingEvents.isEmpty
          ? [
              const SizedBox(height: 24),
              _Note(
                "This ${vm.isGroup ? 'group' : 'team'} hasn't shared "
                'anything publicly yet.',
              ),
            ]
          : const [];
    }
    return [
      _ListHeader(title: 'Posts'),
      if (posts.isEmpty)
        _Note(
          vm.canPost
              ? 'Post news for the team: tryouts, fees, field changes. '
                    'Make a post public to show it to anyone who finds '
                    'the team.'
              : 'No posts yet.',
        ),
      for (final p in posts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TeamPostCard(
            post: p,
            loadImage: vm.imageData,
            showVisibility: vm.isMember,
            onEdit: vm.canPost ? () => _editPost(p) : null,
            onDelete: vm.canPost ? () => _deletePost(p) : null,
          ),
        ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.viewModel, required this.summary});

  final TeamHomeViewModel viewModel;
  final TeamListing summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = viewModel.myRole;
    final count = viewModel.memberCount;
    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          child: summary.isCommunity
              ? const Icon(Icons.diversity_3_outlined, size: 32)
              : Text(
                  summary.name.isEmpty ? '?' : summary.name[0].toUpperCase(),
                  style: theme.textTheme.headlineSmall,
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(summary.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                summary.subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (role != null) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    'You: ${role.labelFor(summary.kind)}',
                    '$count ${count == 1 ? 'member' : 'members'}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _JoinCard extends StatelessWidget {
  const _JoinCard({required this.joining, required this.onJoin});

  final bool joining;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
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
          FilledButton.tonal(
            onPressed: joining ? null : onJoin,
            child: const Text('Join'),
          ),
        ],
      ),
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
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
    ),
  );
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?action,
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
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
