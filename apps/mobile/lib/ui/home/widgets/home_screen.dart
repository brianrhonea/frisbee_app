import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/feed_item.dart';
import '../../../domain/models/schedule_entry.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_post.dart';
import '../../../domain/models/user_post.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/undo_snack_bar.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/event_card.dart';
import '../../core/ui/list_row.dart';
import '../../core/ui/summary_tiles.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';
import '../../posts/widgets/post_widgets.dart';
import '../../schedule/widgets/event_editor_screen.dart';
import '../../schedule/widgets/event_style.dart';
import '../../shell/widgets/app_shell.dart';
import '../../teams/widgets/join_team_dialog.dart';
import '../../teams/widgets/team_post_widgets.dart';
import '../../tournaments/widgets/tournament_day_card.dart';
import '../view_models/home_viewmodel.dart';
import 'home_cards.dart';
import '../../posts/widgets/inline_composer.dart';
import '../../posts/widgets/post_composer.dart';
import '../../core/ui/skeleton.dart';

/// The feed's tabs, in order; Your teams first and open by default.
enum _Tab {
  teams('Your teams'),
  following('Following'),
  everyone('Everyone');

  const _Tab(this.label);

  final String label;
}

/// The home feed, in three tabs: Your teams (the default: every post of
/// the user's teams and communities, with a strip of their teams), Following
/// (the user's posts, their teams' and those of who and what they follow)
/// and Everyone (every public profile's posts, with the API). The composer
/// tops Your teams and Following; on an empty feed, a "Get started"
/// checklist. What's up next sits beside the feed (above the tabs on narrow
/// screens: a tournament-day card or one Coming up card).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.viewModel, this.prompt});

  final HomeViewModel viewModel;

  /// A card above the feed (the personal details prompt).
  final Widget? prompt;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeViewModel get vm => widget.viewModel;
  var _tab = _Tab.teams;
  final _composerKey = GlobalKey();

  late final List<Command<void>> _commands = [
    vm.savePost,
    vm.deletePost,
    vm.deleteUserPost,
  ];

  void _onHomeAgain() {
    if (_tab != _Tab.teams) setState(() => _tab = _Tab.teams);
    vm.refreshFeed();
  }

  @override
  void initState() {
    super.initState();
    // Your teams is the first tab open.
    vm.openTeams();
    HomeRefresh.requests.addListener(_onHomeAgain);
    vm.joinTeam.addListener(_onJoin);
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
  }

  @override
  void dispose() {
    HomeRefresh.requests.removeListener(_onHomeAgain);
    vm.joinTeam.removeListener(_onJoin);
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
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

  void _onCommand() {
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
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

  Future<void> _edit(TeamPostItem p) async {
    final draft = await showDialog<PostDraft>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (_) => PostEditorDialog(
        initial: p.post,
        pickImages: vm.pickImages,
        canUseCamera: vm.canUseCamera,
        loadImage: vm.imageData,
        allowPublic: !(vm.teamOf(p)?.isPrivateGroup ?? false),
      ),
    );
    if (draft != null) vm.savePost.execute((teamId: p.teamId, draft: draft));
  }

  /// Deletes at once, with "Undo" in a toast rather than a dialog first.
  void _remove(FeedItem item) {
    vm.removals.remove(item);
    showUndoSnackBar(
      context,
      message: 'Post deleted',
      onUndo: () => vm.removals.undo(item),
    );
  }

  /// The + button: a post, an event, or a team. (All three already exist;
  /// this only gathers them in one place.)
  Future<void> _add() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: AppMotion.sheetStyle(context),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, icon, label) in [
              ('post', Icons.edit_outlined, 'New post'),
              ('event', Icons.event_outlined, 'Add event'),
              ('team', Icons.group_add_outlined, 'Create or join a team'),
            ])
              ListRow(
                key: Key('add-$value'),
                leading: Icon(icon, color: AppColors.of(context).muted),
                title: label,
                onTap: () => Navigator.pop(context, value),
              ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'post':
        await showPostComposer(context);
      case 'event':
        await _newEvent();
      case 'team':
        await _newOrJoin();
    }
  }

  /// A team event for a team the user runs, or a personal one.
  Future<void> _newEvent() async {
    final teams = vm.postableTeams;
    if (teams.isEmpty) {
      await showEventEditor(context);
      return;
    }
    // `team` is null for My schedule; the whole choice is null when the
    // dialog is dismissed, which adds nothing.
    final choice = await showDialog<({Team? team})>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add an event to'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, (team: null)),
            child: const Row(
              children: [
                Icon(Icons.person_outline),
                SizedBox(width: 12),
                Text('My schedule'),
              ],
            ),
          ),
          for (final t in teams)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (team: t)),
              child: Row(
                children: [
                  TeamBadge(size: 26, community: t.isCommunity),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t.name)),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    await showEventEditor(context, teamId: choice.team?.id);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ScreenSize.of(context).isMobile;
    return Scaffold(
      // Home has its own search bar on phones, so no search button.
      appBar: mobile ? const MobileTopBar(search: false) : null,
      // The one primary action: add something (a post, an event, a team).
      floatingActionButton: Semantics(
        label: 'Add',
        button: true,
        child: FloatingActionButton(
          tooltip: 'Add',
          onPressed: _add,
          child: const Icon(Icons.add),
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.savePost, vm.joinTeam]),
        builder: (context, _) {
          // No page header: the composer below is where posts start.
          return PageScroll(
            onRefresh: vm.refreshFeed,
            // The + button's height plus 16, so it never covers the last row.
            bottomInset: 56 + 16,
            children: [
              // On bigger screens the top bar has the same box.
              if (mobile) ...[const SearchField(), const SizedBox(height: 12)],
              _Greeting(name: vm.firstName, now: vm.now),
              const SizedBox(height: AppSpace.lg),
              SummaryTiles(
                loading: !vm.teamsLoaded,
                tiles: [
                  SummaryTile(
                    value:
                        '${(vm.nextTeamEvent == null ? 0 : 1) + vm.upcomingEvents.length}',
                    label: 'Coming up',
                    onTap: () => context.go(Routes.schedule),
                  ),
                  SummaryTile(
                    value: '${vm.teams.length}',
                    label: 'Your teams',
                    onTap: () => context.go(Routes.teams),
                  ),
                  if (vm.needsYou.isNotEmpty)
                    SummaryTile(
                      value: '${vm.needsYou.length}',
                      label: 'Needs you',
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.xl),
              // Narrow screens: what's today or next above the tabs, kept
              // light: a tournament-day card, or one Coming up card with
              // the next event first.
              LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth >= sideColumnBreakpoint
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: spaced([
                            // On a tournament day its card takes the next
                            // event's place.
                            for (final d in vm.tournamentDays)
                              TournamentDayCard(day: d),
                            // What's the user's to do comes before what's
                            // coming up.
                            if (vm.needsYou.isNotEmpty) _needsYou(),
                            _ComingUp(
                              uid: vm.user?.uid ?? '',
                              events: [
                                if (vm.tournamentDays.isEmpty)
                                  ?vm.nextTeamEvent,
                                ...vm.upcomingEvents.take(2),
                              ],
                              onAdd: _newEvent,
                            ),
                          ]),
                        ),
                      ),
              ),
              _TabRow(
                tabs: [
                  _Tab.teams,
                  _Tab.following,
                  if (vm.hasCommunity) _Tab.everyone,
                ],
                selected: _tab,
                onSelect: (t) {
                  setState(() => _tab = t);
                  if (t == _Tab.everyone) vm.openCommunity();
                  if (t == _Tab.teams) vm.openTeams();
                },
              ),
              const SizedBox(height: 14),
              if (vm.savePost.running)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(),
                ),
              SideColumnLayout(main: _main(), side: _side(), narrow: _main()),
            ],
          );
        },
      ),
    );
  }

  /// The personal details prompt and the composer, atop Your teams and
  /// Following.
  List<Widget> _composer() => [
    ?widget.prompt,
    // Kept across rebuilds (cards appearing above it on phones) and tabs;
    // the draft itself is in the view model.
    InlineComposer(
      key: _composerKey,
      viewModel: vm.composer,
      name: vm.user?.label ?? '',
      photoUrl: vm.user?.photoUrl,
    ),
  ];

  List<Widget> _main() => switch (_tab) {
    _Tab.teams => [..._composer(), ..._teamPosts()],
    _Tab.following => [
      ..._composer(),
      if (!vm.postsLoaded)
        const Skeleton(
          child: Column(
            children: [SkeletonPost(), SizedBox(height: 14), SkeletonPost()],
          ),
        ),
      for (final item in vm.posts)
        switch (item) {
          UserPostItem(:final post) => _userPostCard(post),
          final TeamPostItem p => _teamPostCard(p),
        },
      if (vm.postsError)
        _FeedNote(
          text: "Couldn't load posts.",
          action: ('Try again', vm.refreshFeed),
        )
      else if (vm.hasMorePosts)
        Center(
          child: vm.loadingMorePosts
              ? const Padding(
                  padding: EdgeInsets.all(AppSpace.md),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: vm.loadMorePosts,
                  child: const Text('Show older posts'),
                ),
        )
      else if (vm.showOnboarding)
        GetStartedCard(steps: vm.onboarding, onStep: _onboardingStep)
      else if (vm.postsLoaded)
        _CaughtUp(empty: vm.posts.isEmpty, followsAnything: vm.followsAnything),
    ],
    _Tab.everyone => _community(),
  };

  Widget _teamPostCard(TeamPostItem p) => TeamPostCard(
    key: ValueKey(p.id),
    post: p.post,
    teamName: p.teamName,
    teamId: p.teamId,
    now: vm.now,
    loadImage: vm.imageData,
    showVisibility: vm.teamOf(p) != null,
    onOpenTeam: () => context.go(Routes.team(p.teamId)),
    onEdit: vm.canEditPost(p) ? () => _edit(p) : null,
    onDelete: vm.canEditPost(p) ? () => _remove(p) : null,
  );

  /// A strip of the user's teams, then every post of their teams and
  /// groups, newest first. No team yet: the "Get started" checklist while
  /// it has steps left (it covers joining), else the join card.
  List<Widget> _teamPosts() {
    final feed = vm.teamFeed;
    final posts = vm.teamPosts;
    if (vm.teamsLoaded && vm.teams.isEmpty) {
      // Teams that failed to load aren't "no teams": no join card then.
      if (vm.postsError) {
        return [
          _FeedNote(
            text: "Couldn't load your teams.",
            action: ('Try again', vm.refreshFeed),
          ),
        ];
      }
      return [
        if (vm.showOnboarding)
          GetStartedCard(steps: vm.onboarding, onStep: _onboardingStep)
        else
          _JoinCard(
            joining: vm.joinTeam.running,
            onJoin: _join,
            onCreate: () => context.go(Routes.createTeam),
            onFind: () =>
                context.go(Routes.explore(only: ExploreFilter.groups)),
          ),
      ];
    }
    return [
      if (vm.teamsLoaded)
        TeamStrip(
          teams: vm.stripTeams,
          onOpen: (t) => context.go(Routes.team(t.id)),
          onNewOrJoin: _newOrJoin,
        ),
      if (!vm.teamPostsLoaded)
        const Skeleton(
          child: Column(
            children: [SkeletonPost(), SizedBox(height: 14), SkeletonPost()],
          ),
        ),
      for (final item in posts)
        if (item case final TeamPostItem p) _teamPostCard(p),
      if (vm.teamPostsLoaded && feed != null)
        if (feed.loadingMore)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpace.md),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (feed.error)
          _FeedNote(
            text: "Couldn't load posts.",
            action: ('Try again', vm.refreshFeed),
          )
        else if (feed.hasMore)
          Center(
            child: TextButton(
              onPressed: feed.loadMore,
              child: const Text('Show older posts'),
            ),
          )
        else
          _FeedNote(
            text: posts.isEmpty
                ? 'No team posts yet. News your teams and communities post shows '
                      'up here.'
                : "You're all caught up.",
          ),
    ];
  }

  /// Create a team, or join one with a code (the strip's New / Join).
  Future<void> _newOrJoin() async {
    final choice = await showDialog<String>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => SimpleDialog(
        title: const Text('Create or join'),
        children: [
          for (final (value, icon, label) in [
            ('join', Icons.group_add_outlined, 'Join with a code'),
            ('create', Icons.add, 'Create a team or community'),
            ('find', Icons.search, 'Find a community'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label)),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'join':
        await _join();
      case 'create':
        context.go(Routes.createTeam);
      case 'find':
        context.go(Routes.explore(only: ExploreFilter.groups));
    }
  }

  void _onboardingStep(OnboardingStep step) => switch (step) {
    OnboardingStep.username => context.go(Routes.chooseUsername),
    OnboardingStep.join => _newOrJoin(),
    OnboardingStep.find => context.go(
      Routes.explore(only: ExploreFilter.teams),
    ),
    OnboardingStep.follow => context.go(
      Routes.explore(only: ExploreFilter.players),
    ),
  };

  Widget _needsYou() => NeedsYouCard(
    items: vm.needsYou,
    onOpen: (t) => context.go(Routes.teamMembers(t.id)),
  );

  Widget _userPostCard(UserPost post) {
    final mine = post.authorId == vm.user?.uid;
    final item = UserPostItem(post);
    return UserPostCard(
      key: ValueKey(item.id),
      post: post,
      loadImage: vm.imageData,
      onOpen: () => context.push(Routes.post(post.id)),
      onEdit: mine ? () => showPostComposer(context, postId: post.id) : null,
      onDelete: mine ? () => _remove(item) : null,
      actions: vm.actions,
      onRepost: () => repostOrUndo(context, vm.actions, post),
    );
  }

  /// Every public profile's posts, newest first, a page at a time.
  List<Widget> _community() {
    final feed = vm.community;
    final posts = vm.communityPosts;
    return [
      if (!feed.loaded)
        const Skeleton(
          child: Column(
            children: [SkeletonPost(), SizedBox(height: 14), SkeletonPost()],
          ),
        ),
      for (final post in posts) _userPostCard(post),
      if (feed.loaded)
        if (feed.loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpace.md),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (feed.error)
          _FeedNote(
            text: "Couldn't load posts.",
            action: ('Try again', feed.loadMore),
          )
        else if (feed.hasMore)
          Center(
            child: TextButton(
              onPressed: feed.loadMore,
              child: const Text('Show older posts'),
            ),
          )
        else
          _FeedNote(
            text: posts.isEmpty ? 'No posts yet.' : "You're all caught up.",
          ),
    ];
  }

  List<Widget> _side() => [
    if (vm.needsYou.isNotEmpty) _needsYou(),
    if (vm.tournamentDays.isNotEmpty)
      for (final d in vm.tournamentDays) TournamentDayCard(day: d)
    else if (vm.nextTeamEvent case final next?)
      _UpNextCard(entry: next),
    _ComingUp(
      uid: vm.user?.uid ?? '',
      events: vm.upcomingEvents,
      onAdd: _newEvent,
    ),
    const _Footer(),
  ];
}

// Tabs -----------------------------------------------------------------------

class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<_Tab> tabs;
  final _Tab selected;
  final ValueChanged<_Tab> onSelect;

  @override
  Widget build(BuildContext context) => UnderlineTabs(
    labels: [for (final t in tabs) t.label],
    selected: tabs.indexOf(selected),
    onSelect: (i) => onSelect(tabs[i]),
  );
}

// Feed -----------------------------------------------------------------------

/// A line under a feed: where it ends, or that a page failed, with
/// [action] (a label and what it does) beside it.
class _FeedNote extends StatelessWidget {
  const _FeedNote({required this.text, this.action});

  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            action == null ? Icons.check_circle_outline : Icons.error_outline,
            size: 15,
            color: c.muted,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, style: TextStyle(fontSize: 12, color: c.muted)),
          ),
          if (action case (final label, final onTap)) ...[
            const SizedBox(width: 6),
            TextButton(onPressed: onTap, child: Text(label)),
          ],
        ],
      ),
    );
  }
}

class _CaughtUp extends StatelessWidget {
  const _CaughtUp({required this.empty, required this.followsAnything});

  final bool empty;
  final bool followsAnything;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 15, color: c.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(switch ((empty, followsAnything)) {
              (true, false) =>
                'No posts yet. Follow players, teams and tournaments to '
                    'see their news here.',
              (true, true) => 'No posts yet. News you follow shows up here.',
              _ => "You're all caught up.",
            }, style: TextStyle(fontSize: 12, color: c.muted)),
          ),
        ],
      ),
    );
  }
}

class _JoinCard extends StatelessWidget {
  const _JoinCard({
    required this.joining,
    required this.onJoin,
    required this.onCreate,
    required this.onFind,
  });

  final bool joining;
  final VoidCallback onJoin;
  final VoidCallback onCreate;
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // A plain card with one turf action: amber is only for what's the
    // user's to do, navy only for live or today.
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Eyebrow('No team yet'),
          const SizedBox(height: 8),
          Text(
            'Join your team.',
            style: TextStyle(
              color: c.ink,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Get the schedule, playbook and stats your team shares. Ask a '
            'coach for the invite code, find a pickup community, or start your '
            'own.',
            style: TextStyle(color: c.ink2, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: joining ? null : onJoin,
            icon: const Icon(Icons.group_add_outlined, size: 18),
            label: const Text('Join with code'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (i, (label, icon, onTap)) in [
                ('Find a community', Icons.search, onFind),
                ('Create team', Icons.add, onCreate),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: onTap,
                    icon: Icon(icon, size: 18),
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// Side column ----------------------------------------------------------------

/// The user's next team event on a dark card.
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({required this.entry});

  final ScheduleEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final e = entry.event;
    void open() => context.push(Routes.scheduleEvent(entry));
    return FeatureCard(
      onTap: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Eyebrow(
                  'Up next · ${entry.team?.name ?? 'You'}',
                  color: c.onFeatureMuted,
                ),
              ),
              Icon(Icons.north_east, size: 15, color: c.onFeatureMuted),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(e.type.icon, color: c.onFeature, size: 22),
              const SizedBox(width: 8),
              Text(
                e.type.label,
                style: TextStyle(
                  color: c.onFeatureMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
          // Amber is only for what's the user's to do; opening the event
          // is a plain link along the card's foot (as on the team page).
          const SizedBox(height: 12),
          Divider(height: 1, color: c.featureHighlight),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'View details',
                  style: TextStyle(
                    color: c.onFeature,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
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

/// "Good morning, Ana" over today's date.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.now});

  final String name;
  final DateTime now;

  static String hello(DateTime now) => now.hour < 12
      ? 'Good morning'
      : now.hour < 18
      ? 'Good afternoon'
      : 'Good evening';

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            '${hello(now)}, $name',
            style: AppText.heading3.copyWith(color: c.ink),
          ),
        ),
        Text(
          DateFormat.MMMMEEEEd().format(now),
          style: AppText.secondary.copyWith(color: c.muted),
        ),
      ],
    );
  }
}

/// What's coming up: event cards, with a link to the schedule and "Add
/// event" (no box around the block).
class _ComingUp extends StatelessWidget {
  const _ComingUp({
    required this.uid,
    required this.events,
    required this.onAdd,
  });

  final String uid;
  final List<ScheduleEntry> events;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Coming up',
          actionLabel: 'Schedule',
          onAction: () => context.go(Routes.schedule),
        ),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Text(
              'Nothing else on the calendar.',
              style: AppText.secondary.copyWith(color: c.muted),
            ),
          ),
        for (final entry in events) ...[
          EventCard(
            date: entry.event.startsAt,
            title: entry.event.title,
            meta:
                '${eventTimeRange(entry.event)} · '
                '${entry.team?.name ?? 'Personal'}',
            rsvp: eventRsvpFor(entry.event, uid, team: entry.team != null),
            recurring: entry.event.series != null,
            onTap: () => context.push(Routes.scheduleEvent(entry)),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add event'),
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      '$appName $appVersion · Leave it on the field.',
      style: TextStyle(fontSize: 11, color: AppColors.of(context).muted),
    ),
  );
}
