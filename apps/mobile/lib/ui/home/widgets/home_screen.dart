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
import '../../core/ui/layout.dart';
import '../../posts/widgets/post_widgets.dart';
import '../../schedule/widgets/event_editor_screen.dart';
import '../../schedule/widgets/event_style.dart';
import '../../shell/widgets/app_shell.dart';
import '../../teams/widgets/join_team_dialog.dart';
import '../../teams/widgets/team_post_widgets.dart';
import '../view_models/home_viewmodel.dart';
import 'home_cards.dart';
import '../../posts/widgets/post_composer.dart';
import '../../workouts/widgets/record_button.dart';
import '../../core/ui/skeleton.dart';

enum _Tab {
  forYou('For you'),
  community('Community'),
  teams('Your teams');

  const _Tab(this.label);

  final String label;
}

/// The home feed: the user's posts, their teams' and those of what they
/// follow, with what's up next beside them (below the header on narrow
/// screens); a Community tab of every public profile's posts (as on the
/// website); and a Your teams tab of their teams' posts. Under the
/// composer, a strip of their teams; on an empty feed, a "Get started"
/// checklist (both as on the website).
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
  var _tab = _Tab.forYou;

  late final List<Command<void>> _commands = [
    vm.savePost,
    vm.deletePost,
    vm.deleteUserPost,
  ];

  void _onHomeAgain() {
    if (_tab != _Tab.forYou) setState(() => _tab = _Tab.forYou);
    vm.refreshFeed();
  }

  @override
  void initState() {
    super.initState();
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
      builder: (_) => const JoinTeamDialog(),
    );
    if (code != null) vm.joinTeam.execute(code);
  }

  /// Asks which of [teams] to use when there's more than one.
  Future<Team?> _pickTeam(List<Team> teams, String title) async {
    if (teams.length == 1) return teams.single;
    return showDialog<Team>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final t in teams)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, t),
              child: Row(
                children: [
                  TeamBadge(size: 30, community: t.isCommunity),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t.name)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _compose() async {
    final team = await _pickTeam(vm.postableTeams, 'Post to');
    if (team == null || !mounted) return;
    final draft = await showDialog<PostDraft>(
      context: context,
      builder: (_) => PostEditorDialog(
        pickImages: vm.pickImages,
        canUseCamera: vm.canUseCamera,
        loadImage: vm.imageData,
        allowPublic: !team.isPrivateGroup,
      ),
    );
    if (draft != null) vm.savePost.execute((teamId: team.id, draft: draft));
  }

  Future<void> _edit(TeamPostItem p) async {
    final draft = await showDialog<PostDraft>(
      context: context,
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

  void _newPost() => showPostComposer(context);

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
      body: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.savePost, vm.joinTeam]),
        builder: (context, _) {
          // No page header: the composer below is where posts start.
          return PageScroll(
            onRefresh: vm.refreshFeed,
            children: [
              // On bigger screens the top bar has the same box.
              if (mobile) ...[const SearchField(), const SizedBox(height: 12)],
              _TabRow(
                tabs: [
                  _Tab.forYou,
                  if (vm.hasCommunity) _Tab.community,
                  _Tab.teams,
                ],
                selected: _tab,
                onSelect: (t) {
                  setState(() => _tab = t);
                  if (t == _Tab.community) vm.openCommunity();
                  if (t == _Tab.teams) vm.openTeams();
                },
              ),
              const SizedBox(height: 14),
              if (vm.savePost.running)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(),
                ),
              SideColumnLayout(
                main: _main(),
                side: _side(),
                narrow: [
                  if (_tab == _Tab.forYou) ...[
                    if (vm.needsYou.isNotEmpty) _needsYou(),
                    if (vm.nextTeamEvent case final next?)
                      _NextEventStrip(entry: next),
                    _ComingUpCard(
                      events: vm.upcomingEvents.take(2).toList(),
                      onAdd: _newEvent,
                    ),
                  ],
                  ..._main(),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _main() => switch (_tab) {
    _Tab.forYou => [
      ?widget.prompt,
      _Composer(
        name: vm.user?.label ?? '',
        photoUrl: vm.user?.photoUrl,
        onPost: _newPost,
        onWorkout: () => showPostComposer(context, workout: true),
        onTeamPost: vm.postableTeams.isEmpty || vm.savePost.running
            ? null
            : _compose,
      ),
      if (vm.teamsLoaded)
        TeamStrip(
          teams: vm.stripTeams,
          onOpen: (t) => context.go(Routes.team(t.id)),
          onNewOrJoin: _newOrJoin,
        ),
      // An empty feed has the checklist, which covers joining.
      if (vm.teamsLoaded && vm.teams.isEmpty && !vm.showOnboarding)
        _JoinCard(
          joining: vm.joinTeam.running,
          onJoin: _join,
          onCreate: () => context.go(Routes.createTeam),
          onFind: () => context.go(Routes.explore(only: ExploreFilter.groups)),
        ),
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
      if (vm.hasMorePosts)
        Center(
          child: vm.loadingMorePosts
              ? const Padding(
                  padding: EdgeInsets.all(12),
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
    _Tab.community => _community(),
    _Tab.teams => _teamPosts(),
  };

  Widget _teamPostCard(TeamPostItem p) => TeamPostCard(
    key: ValueKey(p.id),
    post: p.post,
    teamName: p.teamName,
    now: vm.now,
    loadImage: vm.imageData,
    showVisibility: vm.teamOf(p) != null,
    onOpenTeam: () => context.go(Routes.team(p.teamId)),
    onEdit: vm.canEditPost(p) ? () => _edit(p) : null,
    onDelete: vm.canEditPost(p) ? () => _remove(p) : null,
  );

  /// Every post of the user's teams and groups, newest first; no team yet,
  /// the join card.
  List<Widget> _teamPosts() {
    final feed = vm.teamFeed;
    final posts = vm.teamPosts;
    if (vm.teamsLoaded && vm.teams.isEmpty) {
      return [
        _JoinCard(
          joining: vm.joinTeam.running,
          onJoin: _join,
          onCreate: () => context.go(Routes.createTeam),
          onFind: () => context.go(Routes.explore(only: ExploreFilter.groups)),
        ),
      ];
    }
    return [
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
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
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
                ? 'No team posts yet. News your teams and groups post shows '
                      'up here.'
                : "You're all caught up.",
          ),
    ];
  }

  /// Create a team, or join one with a code (the strip's New / Join).
  Future<void> _newOrJoin() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Create or join'),
        children: [
          for (final (value, icon, label) in [
            ('join', Icons.group_add_outlined, 'Join with a code'),
            ('create', Icons.add, 'Create a team or group'),
            ('find', Icons.search, 'Find a group'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Row(
                children: [Icon(icon), const SizedBox(width: 12), Text(label)],
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
    OnboardingStep.join => _join(),
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
              padding: EdgeInsets.all(12),
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
    if (vm.nextTeamEvent case final next?) _UpNextCard(entry: next),
    _ComingUpCard(events: vm.upcomingEvents, onAdd: _newEvent),
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.name,
    required this.photoUrl,
    required this.onPost,
    required this.onWorkout,
    required this.onTeamPost,
  });

  final String name;
  final String? photoUrl;
  final VoidCallback onPost;
  final VoidCallback onWorkout;

  /// Posts to one of the user's teams; null if they run none.
  final VoidCallback? onTeamPost;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final post = onPost;
    final compact = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(
        fontFamily: appFont,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                PersonAvatar(name: name, photoUrl: photoUrl, radius: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(controlRadius),
                    onTap: post,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        "What's happening on your sideline?",
                        style: TextStyle(color: c.muted, fontSize: 13.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            // Wraps on phones, where the buttons don't fit on one line. The
            // card's full width, so every row starts at its left edge (a
            // centred wrap left the second row out of line).
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                children: [
                  TextButton.icon(
                    style: compact,
                    onPressed: post,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('Photo'),
                  ),
                  TextButton.icon(
                    style: compact,
                    onPressed: onWorkout,
                    icon: const Icon(Icons.directions_run, size: 18),
                    label: const Text('Workout'),
                  ),
                  RecordWorkoutButton(style: compact),
                  if (onTeamPost case final teamPost?)
                    TextButton.icon(
                      style: compact,
                      onPressed: teamPost,
                      icon: const Icon(Icons.campaign_outlined, size: 18),
                      label: const Text('Team post'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    return FeatureCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('No team yet', color: c.onFeatureMuted),
          const SizedBox(height: 8),
          Text(
            'Join your team.',
            style: TextStyle(
              color: c.onFeature,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Get the schedule, playbook and stats your team shares. Ask a '
            'coach for the invite code, find a pickup group, or start your '
            'own.',
            style: TextStyle(color: c.onFeatureMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: c.highlight,
                  foregroundColor: c.onHighlight,
                ),
                onPressed: joining ? null : onJoin,
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: const Text('Join with code'),
              ),
              for (final (label, icon, onTap) in [
                ('Find a group', Icons.search, onFind),
                ('Create team', Icons.add, onCreate),
              ])
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.onFeature,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: c.onFeatureMuted),
                  ),
                  onPressed: onTap,
                  icon: Icon(icon, size: 18),
                  label: Text(label),
                ),
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
              Icon(Icons.north_east, size: 15, color: c.highlight),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(e.type.icon, color: c.highlight, size: 22),
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
          const SizedBox(height: 14),
          HighlightButton(label: 'View details', onPressed: open),
        ],
      ),
    );
  }
}

/// The next event on the feed for narrow screens, in place of the side
/// column.
class _NextEventStrip extends StatelessWidget {
  const _NextEventStrip({required this.entry});

  final ScheduleEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final e = entry.event;
    return Material(
      color: c.accentSoft,
      borderRadius: BorderRadius.circular(cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(cardRadius),
        onTap: () => context.push(Routes.scheduleEvent(entry)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              DateBadge(date: e.startsAt, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      [
                        eventTimeRange(e),
                        if (e.location.isNotEmpty) e.location,
                        ?entry.team?.name,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 34),
                ),
                onPressed: () => context.push(Routes.scheduleEvent(entry)),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComingUpCard extends StatelessWidget {
  const _ComingUpCard({required this.events, required this.onAdd});

  final List<ScheduleEntry> events;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SectionCard(
      title: 'Coming up',
      action: CardLink(
        label: 'Schedule',
        onTap: () => context.go(Routes.schedule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (events.isEmpty)
            Text(
              'Nothing else on the calendar.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          for (final entry in events)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => context.push(Routes.scheduleEvent(entry)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    DateBadge(date: entry.event.startsAt, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            '${eventTimeRange(entry.event)} · '
                            '${entry.team?.name ?? 'Personal'}',
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
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              // Compact, so the card's padding below it matches the top
              // (a full 48 dp tap target left a gap under it).
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add event'),
            ),
          ),
        ],
      ),
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
