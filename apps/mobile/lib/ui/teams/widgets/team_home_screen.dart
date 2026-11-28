import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../tournaments/widgets/tournament_day_card.dart';
import '../../../data/repositories/meeting/meeting_repository.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../domain/models/team_page.dart';
import '../../../domain/models/team_post.dart';
import '../../../routing/routes.dart';
import '../../../routing/push_team_route.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/avatar.dart' show AvatarStack;
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/cover_header.dart';
import '../../core/ui/event_card.dart';
import '../../core/ui/scoreboard.dart' show SectionHeader;
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../../follow/widgets/follow_button.dart';
import '../../groups/widgets/group_map.dart';
import '../../schedule/widgets/event_editor_screen.dart';
import '../../schedule/widgets/event_style.dart';
import '../../schedule/widgets/team_events_tab.dart';
import '../view_models/team_detail_viewmodel.dart';
import '../view_models/team_home_viewmodel.dart';
import 'community_sections.dart';
import 'invite_members_dialog.dart';
import 'join_team_dialog.dart';
import 'team_form.dart';
import 'team_share_card.dart';
import 'team_initials.dart';
import 'team_message_sheet.dart';
import 'team_post_comments_sheet.dart';
import 'team_post_widgets.dart';
import 'team_community_sheet.dart';
import 'team_section_screen.dart';
import 'team_settings_screen.dart';
import '../../core/ui/app_segmented_button.dart';
import '../../../routing/team_chat_links.dart';

enum _MenuAction { edit, settings, community, leave, delete }

/// The sections [vm]'s page shows: the team's own for members (some may
/// be turned off), else every one its kind has.
List<TeamSection> _sectionsOf(TeamHomeViewModel vm, TeamKind kind) =>
    switch (vm.team) {
      final t? => TeamSection.forTeam(t),
      null => TeamSection.forKind(kind),
    };

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
/// tabs show their section in place, under a compact header. On phones the
/// header collapses (the banner and name shrink into a bar, the tabs stay
/// pinned under it) when a tab other than the feed opens, or the feed
/// scrolls; it's one page throughout, so back leaves the team.
class TeamHomeScreen extends StatefulWidget {
  const TeamHomeScreen({
    super.key,
    required this.viewModel,
    this.section,
    this.more = false,
    this.inTeamsTab = false,
  });

  final TeamHomeViewModel viewModel;

  /// Opened in the Teams tab (`/teams/{id}`), where back is "All teams":
  /// the list of the user's teams. Elsewhere (over a tournament) back
  /// returns to the page below.
  final bool inTeamsTab;

  /// The open section; null for the feed (the overview) or More.
  final TeamSection? section;

  /// Whether the More tab's list of sections is open.
  final bool more;

  @override
  State<TeamHomeScreen> createState() => _TeamHomeScreenState();
}

class _TeamHomeScreenState extends State<TeamHomeScreen> {
  TeamHomeViewModel get vm => widget.viewModel;

  /// The phone page's outer scroll: how far its header has collapsed.
  final _scroll = ScrollController();

  /// Whether the phone page last showed the feed; null before it showed.
  bool? _wasFeed;

  late final List<Command<void>> _commands = [
    vm.updateTeam,
    vm.leaveTeam,
    vm.deleteTeam,
    vm.savePost,
    vm.deletePost,
    vm.pinPost,
    vm.unpinPost,
    vm.joinGroup,
    vm.cancelJoinRequest,
    vm.setNextRsvp,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
    vm.joinTeam.addListener(_onJoin);
    vm.messageOrganizer.addListener(_onMessage);
  }

  @override
  void dispose() {
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
    vm.joinTeam.removeListener(_onJoin);
    vm.messageOrganizer.removeListener(_onMessage);
    _scroll.dispose();
    super.dispose();
  }

  /// Opens the header on the feed and collapses it on the other tabs:
  /// animated when switching tabs, at once when the page first shows.
  void _settleHeader(bool feed) {
    if (_wasFeed == feed) return;
    final animate = _wasFeed != null;
    _wasFeed = feed;
    void settle(Duration _) {
      if (!mounted || !_scroll.hasClients) return;
      // A page covered before it was laid out (a chat room opened over it
      // at once) has no extent yet: wait for the frame that shows it.
      if (!_scroll.position.hasContentDimensions) {
        WidgetsBinding.instance.addPostFrameCallback(settle);
        return;
      }
      final to = feed ? 0.0 : _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          to,
          duration: AppMotion.of(context, AppMotion.sheet),
          curve: AppMotion.easing,
        );
      } else {
        _scroll.jumpTo(to);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(settle);
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
        animationStyle: AppMotion.dialogStyle(context),
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

  /// An organizer's Message button: on to the conversation, as a
  /// profile's Message does.
  void _onMessage() {
    final cmd = vm.messageOrganizer;
    switch (cmd.result) {
      case Ok<String>(:final value):
        cmd.clearResult();
        context.push(Routes.conversation(value));
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
      animationStyle: AppMotion.dialogStyle(context),
      builder: (_) => const JoinTeamDialog(),
    );
    if (code != null) vm.joinTeam.execute(code);
  }

  Future<void> _onMenu(_MenuAction action, Team team) async {
    switch (action) {
      case _MenuAction.community:
        await showTeamCommunity(context, team);
      case _MenuAction.settings:
        await showTeamSettings(context, team.id);
      case _MenuAction.edit:
        final updated = await showDialog<NewTeam>(
          context: context,
          animationStyle: AppMotion.dialogStyle(context),
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
          animationStyle: AppMotion.dialogStyle(context),
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
        // As on the website: they type the name to confirm.
        final typed = await showDialog<String>(
          context: context,
          animationStyle: AppMotion.dialogStyle(context),
          builder: (_) => _DeleteTeamDialog(team: team),
        );
        if (typed != null && mounted) {
          _showDeleting(team.name);
          vm.deleteTeam.execute(typed);
        }
    }
  }

  Future<void> _editPost([TeamPost? post]) async {
    final draft = await showDialog<PostDraft>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
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

  /// Pins [post]; with [TeamPost.pinsMax] pinned, asks which to take down.
  Future<void> _pinPost(TeamPost post) async {
    final pinned = vm.pinnedPosts;
    String? unpin;
    if (pinned.length >= TeamPost.pinsMax) {
      unpin = await showDialog<String>(
        context: context,
        animationStyle: AppMotion.dialogStyle(context),
        builder: (_) => UnpinPostDialog(pinned: pinned),
      );
      if (unpin == null) return;
    }
    vm.pinPost.execute((postId: post.id, unpin: unpin));
  }

  Future<void> _openComments(TeamPost post) => showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: AppMotion.sheetStyle(context),
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => TeamPostCommentsSheet(
      create: () => vm.commentsFor(post),
      title: post.title.isNotEmpty ? post.title : 'Comments',
    ),
  );

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
        sheetAnimationStyle: AppMotion.sheetStyle(context),
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
        vm.setNextRsvp,
        vm.messageOrganizer,
      ]),
      builder: (context, _) {
        final mobile = ScreenSize.of(context).isMobile;
        final leading = widget.inTeamsTab
            ? const _AllTeamsButton()
            : backOr(context, Routes.teams);
        final summary = vm.summary;
        if (!vm.loaded || summary == null) {
          return Scaffold(
            appBar: AppBar(leading: leading),
            body: !vm.loaded
                ? const LoadingState()
                : const EmptyState(
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
        final promoted = vm.tournamentsTab;
        final more = TeamTab.moreSections(sections, tournamentsTab: promoted);
        if (mobile && team != null && vm.isMember) {
          return _phonePage(summary, team, sections, menu);
        }
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
                  child: _MoreList(
                    teamId: vm.teamId,
                    sections: more,
                    meetings:
                        team?.hasSection(OptionalSection.meetings) ?? false,
                    manageLabel: team == null ? null : _manageLabel(team),
                    onManage: team == null ? null : _manageAction(team),
                    leaveLabel: team == null ? null : 'Leave ${team.kind.noun}',
                    onLeave: team == null ? null : _leaveAction(team),
                    ownerNote: team == null ? null : _ownerNote(team),
                  ),
                ),
              ],
            ),
          );
        }
        if (team != null && section != null && sections.contains(section)) {
          // A team's players sit beside its members under Roster.
          final players =
              TeamTab.of(section, promoted: promoted) == TeamTab.roster &&
              sections.contains(TeamSection.roster);
          return Scaffold(
            appBar: appBar,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  viewModel: vm,
                  summary: summary,
                  tab: TeamTab.of(section, promoted: promoted),
                  menu: mobile ? null : menu,
                ),
                if (players)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Center(child: _rosterSwitch(section)),
                  ),
                Expanded(child: _sectionBody(section)),
              ],
            ),
          );
        }
        return Scaffold(
          // The hero below has the name.
          appBar: mobile ? AppBar(leading: leading, actions: [?menu]) : null,
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
              if (vm.isMember) ...[
                const SizedBox(height: 12),
                _StatTiles(viewModel: vm, onOpenEvent: _openEvent),
              ],
              const SizedBox(height: 16),
              _feed(summary, team),
            ],
          ),
        );
      },
    );
  }

  /// A section's content, e.g. the schedule, with its own view model. A
  /// team's Tournaments starts with its tournament-day card, if it has one.
  Widget _sectionBody(TeamSection section) {
    final body = _sectionHost(section);
    if (section != TeamSection.tournaments) return body;
    final day = vm.tournamentDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (day != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ConstrainedContent(
              maxWidth: 720,
              child: TournamentDayCard(day: day, showTeam: false),
            ),
          ),
        Expanded(child: body),
      ],
    );
  }

  Widget _sectionHost(TeamSection section) => ViewModelHost(
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
          ? const LoadingState()
          : detail.team == null
          ? ErrorState(error: detail.error)
          : TeamSectionBody(
              key: ValueKey(section),
              viewModel: detail,
              section: section,
            ),
    ),
  );

  /// Members and Players side by side under Roster.
  Widget _rosterSwitch(TeamSection section) => AppSegmentedButton<TeamSection>(
    segments: const [
      ButtonSegment(value: TeamSection.members, label: Text('Members')),
      ButtonSegment(value: TeamSection.roster, label: Text('Players')),
    ],
    selected: {section},
    showSelectedIcon: false,
    onSelectionChanged: (s) => goWithinTeam(context, s.single.route(vm.teamId)),
  );

  /// A member's team page on a phone: a header that collapses into a bar
  /// with the tabs pinned under it, and the open tab below.
  Widget _phonePage(
    TeamListing summary,
    Team team,
    List<TeamSection> sections,
    Widget? menu,
  ) {
    final promoted = vm.tournamentsTab;
    final more = TeamTab.moreSections(sections, tournamentsTab: promoted);
    final showMore = widget.more && more.isNotEmpty;
    final section = !showMore && sections.contains(widget.section)
        ? widget.section
        : null;
    final tab = showMore
        ? TeamTab.more
        : TeamTab.of(section, promoted: promoted);
    final feed = tab == TeamTab.feed;
    _settleHeader(feed);
    final players =
        section != null &&
        TeamTab.of(section, promoted: promoted) == TeamTab.roster &&
        sections.contains(TeamSection.roster);
    final Widget body;
    if (feed) {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (vm.savePost.running)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(),
            ),
          _HeroDetails(viewModel: vm, summary: summary),
          const SizedBox(height: 12),
          _StatTiles(viewModel: vm, onOpenEvent: _openEvent),
          const SizedBox(height: 16),
          _feed(summary, team),
        ],
      );
    } else if (section == null) {
      body = _MoreList(
        teamId: vm.teamId,
        sections: more,
        meetings: team.hasSection(OptionalSection.meetings),
        manageLabel: _manageLabel(team),
        onManage: _manageAction(team),
        leaveLabel: 'Leave ${team.kind.noun}',
        onLeave: _leaveAction(team),
        ownerNote: _ownerNote(team),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (players)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Center(child: _rosterSwitch(section)),
            ),
          Expanded(child: _sectionBody(section)),
        ],
      );
    }
    return Scaffold(
      body: NestedScrollView(
        controller: _scroll,
        // The absorber keeps the scroll to the header's collapse, and its
        // handle says how far the pinned header overlaps the tab below.
        headerSliverBuilder: (context, _) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverPersistentHeader(
              pinned: true,
              delegate: _TeamHeaderDelegate(
                topPadding: MediaQuery.paddingOf(context).top,
                textScale: MediaQuery.textScalerOf(
                  context,
                ).scale(1).clamp(1.0, 1.5),
                summary: summary,
                meta: _metaLine(vm, summary),
                colors: AppColors.of(context),
                leading: widget.inTeamsTab
                    ? const _AllTeamsButton()
                    : backOr(context, Routes.teams) ?? const BackButton(),
                menu: menu,
                actions: _headerActions(context, vm, summary),
                tabs: _TeamTabs(
                  teamId: vm.teamId,
                  sections: sections,
                  tournamentsTab: promoted,
                  selected: tab,
                ),
              ),
            ),
          ),
        ],
        // The injector moves the tab below the pinned header; the tab's own
        // list (the primary scroll view) fills the rest. This wrapper
        // doesn't scroll itself.
        body: Builder(
          builder: (context) => CustomScrollView(
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            slivers: [
              SliverOverlapInjector(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
              ),
              SliverFillRemaining(
                child: AnimatedSwitcher(
                  duration: AppMotion.of(context, AppMotion.base),
                  child: KeyedSubtree(
                    key: ValueKey(section ?? tab),
                    child: body,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The feed tab: about, what's coming up, members and posts.
  Widget _feed(TeamListing summary, Team? team) {
    return Builder(
      builder: (context) {
        final pickup = _pickupCard(summary);
        // The pickup card carries an outsider's Join when it shows.
        final showJoinCard = !vm.isMember && pickup == null;
        final community = _communitySections(summary, team);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (vm.showSectionsHint)
              _SectionsHint(
                onOpen: () => showTeamSettings(context, vm.teamId),
                onDismiss: vm.dismissSectionsHint,
              ),
            if (team != null && team.isLeagueTeam)
              // A league team is its chat and members; the league page
              // has its games.
              SideColumnLayout(
                main: [
                  _about(summary),
                  _leagueCard(team),
                  _MembersCard(team: team),
                  TeamShareCard(team: team),
                ],
                side: [_details(summary)],
                narrow: [
                  _about(summary),
                  _leagueCard(team),
                  _MembersCard(team: team),
                  TeamShareCard(team: team),
                  _details(summary),
                ],
              )
            else
              SideColumnLayout(
                main: [
                  ?pickup,
                  ..._invites(context),
                  _about(summary),
                  if (showJoinCard) _joinCard(summary),
                  if (vm.youthRosterPrivate) const YouthRosterNote(),
                  if (vm.contentError != null)
                    Text(
                      errorMessage(vm.contentError),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (team != null) _MembersCard(team: team),
                  if (team != null && !team.isCommunity)
                    TeamShareCard(team: team),
                  ..._posts(context),
                ],
                side: [
                  ..._events(context),
                  ...community,
                  ..._tournaments(context),
                  _details(summary),
                ],
                narrow: [
                  ?pickup,
                  ..._invites(context),
                  _about(summary),
                  if (showJoinCard) _joinCard(summary),
                  if (vm.youthRosterPrivate) const YouthRosterNote(),
                  ...community,
                  ..._events(context),
                  ..._tournaments(context),
                  if (team != null) _MembersCard(team: team),
                  if (team != null && !team.isCommunity)
                    TeamShareCard(team: team),
                  ..._posts(context),
                  _details(summary),
                ],
              ),
          ],
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

  /// More's "Manage team" row: the settings the header's menu opens, for
  /// the same people (admins of a team that isn't a league's).
  VoidCallback? _manageAction(Team team) =>
      vm.canEdit && team.kind == TeamKind.team && !team.isLeagueTeam
      ? () => _onMenu(_MenuAction.settings, team)
      : null;

  String _manageLabel(Team team) => manageRowLabel(group: team.isCommunity);

  /// More's Leave button: the header menu's leave flow and confirm. Not
  /// for the owner, who hands the team on first.
  VoidCallback? _leaveAction(Team team) =>
      vm.isOwner ? null : () => _onMenu(_MenuAction.leave, team);

  String? _ownerNote(Team team) => vm.isOwner
      ? "Owners can't leave. To leave, make someone else the owner first "
            '(Roster › Members).'
      : null;

  Widget _menu(Team team) {
    final noun = team.kind.noun;
    return PopupMenuButton<_MenuAction>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz),
      onSelected: (a) => _onMenu(a, team),
      itemBuilder: (_) => [
        if (vm.canEdit)
          PopupMenuItem(value: _MenuAction.edit, child: Text('Edit $noun')),
        // Settings: Sections (the owner switches Playbook, Videos, Stats
        // and Meetings) and Visibility (admins switch the public page).
        if (vm.canEdit && team.kind == TeamKind.team && !team.isLeagueTeam)
          const PopupMenuItem(
            value: _MenuAction.settings,
            child: Text('Settings'),
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          summary.isCommunity ? 'About the community' : 'About the team',
        ),
        const SizedBox(height: AppSpace.sm),
        Column(
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
              style: AppText.body.copyWith(
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
                    child: StatBlock(
                      value: '${vm.posts.length}',
                      label: 'Posts',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
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
      : summary.takesRequests
      ? _TeamRequestCard(
          pending: vm.requestPending,
          busy:
              vm.joinGroup.running ||
              vm.cancelJoinRequest.running ||
              vm.joinTeam.running,
          onRequest: vm.joinGroup.execute,
          onCancel: vm.cancelJoinRequest.execute,
          onCode: _join,
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
          ? 'Community details'
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
                      ? "The community's admins approve new members."
                      : 'Open to new players. Join any time.')
                : summary.takesRequests
                ? 'Ask to join, or use an invite code from a coach or captain.'
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
    final day = vm.tournamentDay;
    // A community's next event is its pickup card, at the top (F27).
    final pickupShown = _showsPickupCard(vm.summary);
    if (pickupShown && rest.isEmpty && day == null) return const [];
    return [
      // On a tournament day the card takes the next event's place.
      if (day != null)
        TournamentDayCard(day: day, showTeam: false)
      else if (next != null && !pickupShown)
        _UpNextCard(
          event: next,
          teamName: vm.summary?.name ?? '',
          onOpen: () => _openEvent(next),
        ),
      Column(
        key: const ValueKey('coming-up'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            next == null ? 'Up next' : 'Coming up',
            actionLabel: vm.isMember ? 'All events' : null,
            onAction: () =>
                goWithinTeam(context, TeamSection.events.route(vm.teamId)),
          ),
          const SizedBox(height: AppSpace.sm),
          ...[
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
        ],
      ),
    ];
  }

  /// Whether the page leads with the community's next-event card (F27): a
  /// community's page that isn't private to the viewer, for members, and
  /// for outsiders while there's a public event to show.
  bool _showsPickupCard(TeamListing? summary) =>
      summary != null &&
      summary.isCommunity &&
      !vm.isPrivateToMe &&
      (vm.isMember || vm.nextEvent != null);

  /// The community's next event with RSVP (F27), or null.
  Widget? _pickupCard(TeamListing summary) {
    if (!_showsPickupCard(summary)) return null;
    final next = vm.nextEvent;
    // Follows the command too, or the buttons stay off after a save.
    return ListenableBuilder(
      key: const ValueKey('next-pickup'),
      listenable: vm.setNextRsvp,
      builder: (context, _) => NextPickupCard(
        kind: summary.kind,
        event: next,
        member: vm.isMember,
        mine: vm.myNextRsvp,
        needsRsvp: vm.nextNeedsRsvp,
        busy: vm.setNextRsvp.running,
        onAnswer: vm.answerNext,
        onOpen: next == null ? null : () => _openEvent(next),
        onNewEvent: vm.canAddEvents
            ? () => showEventEditor(context, teamId: vm.teamId)
            : null,
        join: vm.isMember
            ? null
            : PickupJoinPrompt(
                requiresApproval: summary.requiresApproval,
                pending: vm.requestPending,
                busy: vm.joinGroup.running || vm.cancelJoinRequest.running,
                onJoin: vm.joinGroup.execute,
                onCancel: vm.cancelJoinRequest.execute,
              ),
      ),
    );
  }

  /// A community member's Chat and Organizers sections (F27).
  List<Widget> _communitySections(TeamListing summary, Team? team) {
    if (team == null || !summary.isCommunity) return const [];
    final chat = vm.chatSection;
    return [
      CommunityChatSection(
        rooms: chat.rooms,
        more: chat.more,
        onOpenRoom: (r) => context.push(
          inSameContext(context, Routes.chatRoom(team.id, r.id)),
        ),
        onOpenChat: () =>
            goWithinTeam(context, TeamSection.chat.route(team.id)),
      ),
      CommunityOrganizersSection(
        organizers: vm.organizers,
        me: vm.uid,
        busy: vm.messageOrganizer.running,
        onMessage: vm.canMessage ? vm.messageOrganizer.execute : null,
      ),
    ];
  }

  /// A group's tournaments, which anyone can open and follow. Members
  /// have the full list in the Tournaments tab.
  /// The team's tournament business, for its admins: invites waiting on
  /// it, each with Respond (the respond flow: accept or decline, then
  /// roster and payment), and entries still missing a roster or fee, each
  /// with Finish entry. Nothing when there's nothing to do.
  List<Widget> _invites(BuildContext context) {
    final invites = vm.tournamentInvites;
    final toFinish = vm.entriesToFinish;
    if (invites.isEmpty && toFinish.isEmpty) return const [];
    final c = AppColors.of(context);
    final day = DateFormat('EEE, MMM d');
    Future<void> open(String route) async {
      await context.push(route);
      vm.refreshInvites();
    }

    Widget title(String text) => Text(
      text,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
    );
    Widget meta(List<String> parts) => Text(
      parts.where((p) => p.isNotEmpty).join(' · '),
      style: TextStyle(fontSize: 12.5, color: c.muted),
    );
    return [
      if (invites.isNotEmpty)
        SectionCard(
          key: const ValueKey('tournament-invites'),
          title: invites.length == 1
              ? 'Tournament invite'
              : 'Tournament invites · ${invites.length}',
          icon: Icons.mark_email_unread_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final i in invites)
                Padding(
                  key: ValueKey('tournament-invite-${i.tournamentId}'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title(i.name),
                      meta([
                        day.format(i.startsOn.toLocal()),
                        if (i.hostName.isNotEmpty) 'from ${i.hostName}',
                        i.divisionLabel,
                      ]),
                      if (i.expired)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Expired. ${TournamentEntry.expiredMessage}',
                            style: TextStyle(fontSize: 12.5, color: c.ink2),
                          ),
                        )
                      else ...[
                        if (i.replyBy case final by?)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Reply by ${day.format(by.toLocal())}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: c.highlightInk,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        FilledButton(
                          key: ValueKey('respond-invite-${i.tournamentId}'),
                          onPressed: () => open(
                            Routes.tournamentRespond(
                              i.tournamentId,
                              teamId: vm.teamId,
                            ),
                          ),
                          child: const Text('Respond'),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      if (toFinish.isNotEmpty)
        SectionCard(
          key: const ValueKey('entries-to-finish'),
          title: toFinish.length == 1
              ? 'Entry to finish'
              : 'Entries to finish · ${toFinish.length}',
          icon: Icons.checklist,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in toFinish)
                Padding(
                  key: ValueKey('entry-to-finish-${e.tournamentId}'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title(e.name),
                      meta([
                        day.format(e.startsOn.toLocal()),
                        if (e.hostName.isNotEmpty) 'from ${e.hostName}',
                        e.divisionLabel,
                      ]),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            e.stillToDo,
                            if (e.deadline case final d?)
                              '${e.overdue ? 'was due' : 'due'} '
                                  '${day.format(d.toLocal())}',
                          ].join(' '),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: e.overdue ? c.highlightInk : c.ink2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        key: ValueKey('finish-entry-${e.tournamentId}'),
                        onPressed: () => open(
                          Routes.tournamentRespond(
                            e.tournamentId,
                            teamId: vm.teamId,
                            step: e.rosterSet ? 'pay' : 'roster',
                          ),
                        ),
                        child: const Text('Finish entry'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ];
  }

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
      return [
        _Note(
          vm.isGroup
              ? 'This is a private community. Its location, events and posts '
                    'are only visible to members.'
              : "This team's page is private. Its events, posts and roster "
                    'are only visible to members.',
        ),
      ];
    }
    if (posts.isEmpty && !vm.isMember) {
      return vm.upcomingEvents.isEmpty
          ? [
              _Note(
                "This ${vm.isGroup ? 'community' : 'team'} hasn't shared "
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
                vm.isGroup ? 'From the community' : 'From the team',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: c.ink,
                ),
              ),
            ),
          ],
        ),
      ),
      if (vm.canPost)
        PostToTeamBox(
          label: vm.isGroup ? 'Post to the community' : 'Post to the team',
          onTap: vm.savePost.running ? null : _editPost,
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
          teamId: vm.teamId,
          loadImage: vm.imageData,
          showVisibility: vm.isMember,
          pinned: p.isPinned,
          onEdit: vm.canPost ? () => _editPost(p) : null,
          onDelete: vm.canPost ? () => _deletePost(p) : null,
          onPin: vm.canPin && !p.isPinned ? () => _pinPost(p) : null,
          onUnpin: vm.canPin && p.isPinned
              ? () => vm.unpinPost.execute(p.id)
              : null,
          onComments: vm.isMember ? () => _openComments(p) : null,
        ),
    ];
  }
}

/// The badge, name, what it is, actions and section tabs at the top of the
/// page (an outsider's phone view, and wide screens).
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
    final vm = viewModel;
    final mobile = ScreenSize.of(context).isMobile;
    final follow = _followOf(vm);
    final actions = <Widget>[
      ..._teamActions(context, vm, summary, follow: mobile ? null : follow),
      ?menu,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CoverHeader(
          title: summary.name,
          subtitle: _metaLine(vm, summary),
          avatar: TeamInitials(
            name: summary.name,
            kind: summary.kind,
            size: 72,
          ),
          actions: mobile ? const [] : actions,
        ),
        if (summary.official) ...[
          const SizedBox(height: AppSpace.sm),
          const Align(
            alignment: Alignment.centerLeft,
            child: OfficialBadge(label: 'Official organizer'),
          ),
        ],
        // Phones put the buttons below the name, side by side, with Follow
        // on its own line.
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
        if (vm.isMember) ...[
          const SizedBox(height: 12),
          _CountLine(viewModel: vm, summary: summary),
          const SizedBox(height: 6),
          _TeamTabs(
            teamId: vm.teamId,
            sections: _sectionsOf(vm, summary.kind),
            tournamentsTab: vm.tournamentsTab,
            selected: TeamTab.feed,
          ),
        ] else
          const SizedBox(height: 16),
      ],
    );
  }
}

/// What the team is, where, how many are on it and when it started, e.g.
/// "Mixed · Club · Denver · 24 members · Est. 2019".
String _metaLine(TeamHomeViewModel vm, TeamListing summary) {
  final count = vm.memberCount;
  final founded = vm.team?.createdAt?.year;
  return [
    if (summary.subtitle.isNotEmpty) summary.subtitle,
    if (vm.team != null) '$count ${count == 1 ? 'member' : 'members'}',
    if (founded != null) 'Est. $founded',
  ].join(' · ');
}

FollowControl? _followOf(TeamHomeViewModel vm) => switch (vm.follow) {
  final f? => FollowControl(viewModel: f, showCount: true),
  null => null,
};

/// The team's community, as a chip that opens it.
Widget? _communityChip(BuildContext context, TeamHomeViewModel vm) =>
    switch (vm.team) {
      final team? when team.inCommunity => ActionChip(
        avatar: const Icon(Icons.account_balance_outlined, size: 18),
        label: Text(team.orgName.isEmpty ? 'Community' : team.orgName),
        tooltip: 'Open the community',
        onPressed: () => pushTeamRoute(context, Routes.team(team.orgId!)),
      ),
      _ => null,
    };

/// Invite (turf, with a badge counting join requests) and Message
/// (outlined): the phone header's row.
List<Widget> _headerActions(
  BuildContext context,
  TeamHomeViewModel vm,
  TeamListing summary,
) => [
  if (vm.team case final team? when vm.canManageMembers)
    FilledButton.icon(
      onPressed: () => showInviteMembers(context, team),
      // The badge counts people asking to join; they're in the dialog too.
      // On the icon, so the button keeps its size in the phone's row.
      icon: Badge(
        isLabelVisible: vm.joinRequestCount > 0,
        label: Text(
          vm.joinRequestCount > 99 ? '99+' : '${vm.joinRequestCount}',
          semanticsLabel: '${vm.joinRequestCount} asking to join',
        ),
        child: const Icon(Icons.person_add_alt, size: 18),
      ),
      label: Text(summary.isCommunity ? 'Invite members' : 'Invite players'),
    ),
  if (vm.showsMessage)
    OutlinedButton.icon(
      onPressed: () => _openMessage(context, vm),
      icon: const Icon(Icons.chat_bubble_outline, size: 17),
      label: const Text('Message'),
    ),
];

/// The Message sheet: the team chat (members) and the staff to message;
/// the choice opens the chat, or starts a direct conversation, whose
/// errors the page shows.
Future<void> _openMessage(BuildContext context, TeamHomeViewModel vm) async {
  final choice = await showTeamMessageSheet(context, vm);
  if (!context.mounted) return;
  switch (choice) {
    case TeamChatChoice():
      goWithinTeam(context, TeamSection.chat.route(vm.teamId));
    case StaffChoice(:final staff):
      vm.messageOrganizer.execute(staff);
    case null:
      break;
  }
}

/// The buttons under the team's name: its community, [follow], Invite and
/// Message.
List<Widget> _teamActions(
  BuildContext context,
  TeamHomeViewModel vm,
  TeamListing summary, {
  Widget? follow,
}) => [
  ?_communityChip(context, vm),
  ?follow,
  ..._headerActions(context, vm, summary),
];

/// How many upcoming events, and the user's role.
class _CountLine extends StatelessWidget {
  const _CountLine({required this.viewModel, required this.summary});

  final TeamHomeViewModel viewModel;
  final TeamListing summary;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final upcoming = vm.upcomingEvents.length;
    return Row(
      children: [
        Expanded(
          child: Text(
            '$upcoming upcoming',
            style: AppText.caption.copyWith(color: AppColors.of(context).muted),
          ),
        ),
        if (vm.myRole case final role?)
          Tag('You: ${role.labelFor(summary.kind)}'),
      ],
    );
  }
}

/// The top of a phone's feed under the header: the team's community,
/// Follow, and what's coming up.
class _HeroDetails extends StatelessWidget {
  const _HeroDetails({required this.viewModel, required this.summary});

  final TeamHomeViewModel viewModel;
  final TeamListing summary;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final follow = _followOf(vm);
    final chip = _communityChip(context, vm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chip != null || follow != null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [?chip, ?follow],
          ),
          const SizedBox(height: 12),
        ],
        _CountLine(viewModel: vm, summary: summary),
      ],
    );
  }
}

/// Back to the Teams tab's list of the user's teams (the tab itself
/// always opens that list).
class _AllTeamsButton extends StatelessWidget {
  const _AllTeamsButton();

  static const label = 'All teams';

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    icon: const BackButtonIcon(),
    onPressed: () => GoRouter.of(context).canPop()
        ? Navigator.maybePop(context)
        : context.go(Routes.teams),
  );
}

/// A phone's team header: back, the badge, name and what the team is, and
/// the menu; then Invite and Message; then the tabs. Scrolled (or on a tab
/// other than the feed) the buttons fold away under the name, and the name
/// and tabs stay pinned.
class _TeamHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TeamHeaderDelegate({
    required this.topPadding,
    required this.textScale,
    required this.summary,
    required this.meta,
    required this.colors,
    required this.leading,
    required this.menu,
    required this.actions,
    required this.tabs,
  });

  static const _identityBase = 68.0;
  static const _actions = 56.0; // 48 px buttons + 8 px bottom padding
  static const _tabs = 44.0;

  final double topPadding;

  /// The text scale (1 to 1.5): the name and meta rows grow with it.
  final double textScale;
  final TeamListing summary;

  /// E.g. "Mixed · Club · Denver · 24 members · Est. 2019".
  final String meta;
  final AppColors colors;
  final Widget leading;
  final Widget? menu;

  /// Invite and Message; nothing folds when there are none.
  final List<Widget> actions;
  final Widget tabs;

  double get _identity => _identityBase * textScale;

  double get _actionsHeight => actions.isEmpty ? 0 : _actions;

  @override
  double get minExtent => topPadding + _identity + _tabs;

  @override
  double get maxExtent => minExtent + _actionsHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final c = colors;
    final fold = _actionsHeight == 0
        ? 1.0
        : (shrinkOffset / _actionsHeight).clamp(0.0, 1.0);
    return Material(
      color: c.card,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Back, badge, name and menu: always there.
          Positioned(
            top: topPadding,
            left: 4,
            right: 4,
            height: _identity,
            child: Row(
              children: [
                leading,
                const SizedBox(width: 4),
                TeamInitials(name: summary.name, kind: summary.kind),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.heading3.copyWith(color: c.ink),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        meta,
                        maxLines: textScale > 1.3 ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
                if (menu != null) menu! else const SizedBox(width: 12),
              ],
            ),
          ),
          // Invite and Message, sliding up under the name as it folds.
          if (actions.isNotEmpty)
            Positioned(
              top: topPadding + _identity,
              left: 0,
              right: 0,
              height: _actions * (1 - fold),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.bottomCenter,
                  minHeight: _actions,
                  maxHeight: _actions,
                  child: IgnorePointer(
                    ignoring: fold > 0.5,
                    child: Opacity(
                      opacity: (1 - fold * 1.6).clamp(0.0, 1.0),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            for (var i = 0; i < actions.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(child: actions[i]),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            height: _tabs,
            child: Align(alignment: Alignment.bottomLeft, child: tabs),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_TeamHeaderDelegate old) => true;
}

/// The page's [TeamTab]s. Switching tabs stays on the team page.
class _TeamTabs extends StatelessWidget {
  const _TeamTabs({
    required this.teamId,
    required this.sections,
    required this.selected,
    this.tournamentsTab = false,
  });

  /// The page's sections ([TeamSection.forTeam]): a league team has just
  /// chat and members, and sections the owner turned off have no tab.
  final List<TeamSection> sections;

  /// Tournaments is a tab of its own ([TeamHomeViewModel.tournamentsTab]).
  final bool tournamentsTab;

  final String teamId;
  final TeamTab selected;

  @override
  Widget build(BuildContext context) {
    final tabs = TeamTab.forSections(sections, tournamentsTab: tournamentsTab);
    return UnderlineTabs(
      labels: [for (final t in tabs) t.label],
      selected: tabs.indexOf(selected),
      onSelect: (i) => goWithinTeam(context, tabs[i].route(teamId)),
    );
  }
}

/// For the owner of a brand-new team: where the sections it started
/// without are. Shown until dismissed (remembered on the device).
class _SectionsHint extends StatelessWidget {
  const _SectionsHint({required this.onOpen, required this.onDismiss});

  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                Icon(Icons.tune, size: 20, color: c.accentInk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Turn on ${OptionalSection.listed} in Settings › '
                    'Sections.',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: c.accentInk,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  icon: Icon(Icons.close, size: 18, color: c.accentInk),
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The More tab: the team's other sections, one row each with a line on
/// what's there, then its Meetings list when the team has Meetings on,
/// "Manage team" for admins (Settings), and Leave at the bottom.
class _MoreList extends StatelessWidget {
  const _MoreList({
    required this.teamId,
    required this.sections,
    this.meetings = false,
    this.manageLabel,
    this.onManage,
    this.leaveLabel,
    this.onLeave,
    this.ownerNote,
  });

  final String teamId;
  final List<TeamSection> sections;

  /// Whether to list Meetings (Settings › Sections), which open on a page
  /// of their own.
  final bool meetings;

  /// "Manage team" (or group) and what it opens: the settings, for those
  /// who see them in the header's menu; null for no row.
  final String? manageLabel;
  final VoidCallback? onManage;

  /// "Leave team" and the header menu's leave flow (its confirm); null for
  /// the owner, who can't leave without handing the team on.
  final String? leaveLabel;
  final VoidCallback? onLeave;

  /// In Leave's place for the owner: why they can't leave yet.
  final String? ownerNote;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget row({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 19, color: c.accentInk),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: c.ink,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, color: c.muted),
      ),
      trailing: Icon(Icons.chevron_right, color: c.muted),
      onTap: onTap,
    );
    final rows = [
      for (final s in sections)
        row(
          icon: s.icon,
          title: s.label,
          subtitle: teamMoreSubtitle(s.path),
          onTap: () => goWithinTeam(context, s.route(teamId)),
        ),
      if (meetings)
        row(
          icon: Icons.videocam_outlined,
          title: 'Meetings',
          subtitle: teamMoreSubtitle('meetings'),
          onTap: () => context.push(Routes.teamMeetings(teamId)),
        ),
      if (onManage case final manage?)
        row(
          icon: Icons.settings_outlined,
          title: manageLabel ?? 'Manage team',
          subtitle: teamMoreSubtitle('manage'),
          onTap: manage,
        ),
    ];
    return ConstrainedContent(
      maxWidth: 720,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          // One card of rows, each with its icon on a soft turf tile.
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, r) in rows.indexed) ...[
                  if (i > 0) Divider(height: 1, color: c.border),
                  r,
                ],
              ],
            ),
          ),
          if (onLeave case final leave?) ...[
            const SizedBox(height: 20),
            Center(
              child: OutlinedButton.icon(
                onPressed: leave,
                icon: const Icon(Icons.logout, size: 18),
                label: Text(leaveLabel ?? 'Leave team'),
              ),
            ),
          ] else if (ownerNote case final note?) ...[
            const SizedBox(height: 20),
            Text(
              note,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// A member's quick numbers under the team header: how many are going to
/// the next event, and how many rooms have messages they haven't read
/// (amber while there are any: theirs to read). No win–loss record: the
/// team's results aren't kept anywhere cheap to read.
class _StatTiles extends StatelessWidget {
  const _StatTiles({required this.viewModel, required this.onOpenEvent});

  final TeamHomeViewModel viewModel;
  final ValueChanged<TeamEvent> onOpenEvent;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final next = vm.nextEvent;
    final unread = vm.newInChat;
    return Row(
      children: [
        if (next != null) ...[
          Expanded(
            child: _StatTile(
              value: '${vm.nextGoing}',
              label: 'going',
              detail: next.title.isEmpty ? 'Next event' : next.title,
              semantics: '${vm.nextGoing} going to ${next.title}',
              onTap: () => onOpenEvent(next),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: _StatTile(
            value: '$unread',
            label: 'new in chat',
            detail: unread == 0
                ? 'All caught up'
                : unread == 1
                ? '1 room'
                : '$unread rooms',
            semantics: unread == 0
                ? 'No new messages'
                : '$unread ${unread == 1 ? 'room has' : 'rooms have'} '
                      'new messages',
            highlight: unread > 0,
            onTap: () =>
                goWithinTeam(context, TeamSection.chat.route(vm.teamId)),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.detail,
    required this.semantics,
    required this.onTap,
    this.highlight = false,
  });

  final String value;
  final String label;
  final String detail;
  final String semantics;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ink = highlight ? c.highlightInk : c.ink;
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: highlight ? c.highlightSoft : c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
            color: highlight ? c.highlight.withValues(alpha: 0.45) : c.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value, style: AppText.score.copyWith(color: ink)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label.copyWith(color: ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
                  TeamInitials(name: summary.name, kind: summary.kind),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.name,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: c.ink,
                          ),
                        ),
                        Text(
                          _metaLine(viewModel, summary),
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  ?menu,
                ],
              ),
            _TeamTabs(
              teamId: viewModel.teamId,
              sections: _sectionsOf(viewModel, summary.kind),
              tournamentsTab: viewModel.tournamentsTab,
              selected: tab,
            ),
          ],
        ),
      ),
    );
  }
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
          Eyebrow('Up next · ${e.type.label}', color: c.onFeatureMuted),
          const SizedBox(height: 12),
          Text(e.title, style: AppText.heading3.copyWith(color: c.onFeature)),
          const SizedBox(height: 6),
          Text(
            '${DateFormat.MMMEd().format(e.startsAt)} · ${eventTimeRange(e)}',
            style: AppText.label.copyWith(color: c.onFeature),
          ),
          if (e.location.isNotEmpty)
            Text(
              e.location,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: c.onFeatureMuted),
            ),
          // Amber is only for what's the user's to do; opening the event
          // is a plain link along the card's foot.
          const SizedBox(height: 12),
          Divider(height: 1, color: c.featureHighlight),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'View details',
                  style: AppText.label.copyWith(color: c.onFeature),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: c.onFeature),
            ],
          ),
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
    final e = event;
    final going = e.responders(RsvpStatus.going).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: EventCard(
        date: e.startsAt,
        title: e.title,
        meta: [
          e.type.label,
          eventTimeRange(e),
          if (going > 0) '$going going',
        ].join(' \u00b7 '),
        recurring: e.series != null,
        onTap: onTap,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          team.isCommunity ? 'Meet the community' : 'Meet the sideline',
          actionLabel: 'All $count ${team.isCommunity ? 'members' : 'players'}',
          onAction: () =>
              goWithinTeam(context, TeamSection.members.route(team.id)),
        ),
        const SizedBox(height: AppSpace.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: AvatarStack(
            max: 6,
            total: count,
            items: [
              for (final uid in members.map((m) => m.key).take(6))
                (name: team.memberNames[uid] ?? '?', imageUrl: null),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 520 ? 3 : 2;
            const gap = 10.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
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
                      padding: const EdgeInsets.all(AppSpace.md),
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
                            style: AppText.label.copyWith(color: c.ink),
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
      ],
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

/// A team that takes join requests (F26), for a signed-in outsider:
/// Request to join (the team's member managers approve it), or Cancel
/// request while it waits; an invite code still works.
class _TeamRequestCard extends StatelessWidget {
  const _TeamRequestCard({
    required this.pending,
    required this.busy,
    required this.onRequest,
    required this.onCancel,
    required this.onCode,
  });

  final bool pending;
  final bool busy;
  final VoidCallback onRequest;
  final VoidCallback onCancel;
  final VoidCallback onCode;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(pending ? Icons.hourglass_top : Icons.how_to_reg_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                pending
                    ? "Request sent. You'll hear when the team lets you in."
                    : "You're not on this team. Ask to join, or use an "
                          'invite code from a coach or captain.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: busy ? null : onCode,
              child: const Text('Use a code'),
            ),
            if (pending)
              OutlinedButton(
                onPressed: busy ? null : onCancel,
                child: const Text('Cancel request'),
              )
            else
              FilledButton(
                onPressed: busy ? null : onRequest,
                child: const Text('Request to join'),
              ),
          ],
        ),
      ],
    ),
  );
}

/// Join (or ask to join) a community group.
/// In place of a youth team's roster for anyone who isn't on it (the
/// website says the same).
class YouthRosterNote extends StatelessWidget {
  const YouthRosterNote({super.key});

  static const text =
      'Rosters of youth teams are private: only members see them.';

  @override
  Widget build(BuildContext context) => const SectionCard(
    child: Row(
      children: [
        Icon(Icons.shield_outlined),
        SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

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

/// Asks the owner to type [team]'s name before deleting it; pops with what
/// they typed once it matches.
class _DeleteTeamDialog extends StatefulWidget {
  const _DeleteTeamDialog({required this.team});

  final Team team;

  @override
  State<_DeleteTeamDialog> createState() => _DeleteTeamDialogState();
}

class _DeleteTeamDialogState extends State<_DeleteTeamDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _matches => deleteNameMatches(widget.team.name, _name.text);

  void _confirm() {
    if (_matches) Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      scrollable: true,
      title: Text('Delete ${team.name}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            team.isCommunity
                ? 'This permanently deletes the ${team.kind.noun}, its '
                      'events, tournaments, chat and posts, for everyone. '
                      "It can't be undone."
                : 'This permanently deletes the team, its roster, events, '
                      "posts and playbook, for everyone. It can't be undone.",
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Type ${team.name} to confirm',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _matches ? _confirm : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
