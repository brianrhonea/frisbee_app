import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/schedule_entry.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_post.dart';
import '../../../domain/models/tournament.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../schedule/widgets/event_style.dart';
import '../../shell/widgets/app_shell.dart';
import '../../teams/widgets/join_team_dialog.dart';
import '../../teams/widgets/team_post_widgets.dart';
import '../view_models/home_viewmodel.dart';

enum _Tab { forYou, teams }

/// The community feed: posts from the user's teams, with what's up next
/// beside them (below the header on narrow screens), and a tab of the
/// user's teams.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.viewModel});

  final HomeViewModel viewModel;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeViewModel get vm => widget.viewModel;
  var _tab = _Tab.forYou;

  late final List<Command<void>> _commands = [vm.savePost, vm.deletePost];

  @override
  void initState() {
    super.initState();
    vm.joinTeam.addListener(_onJoin);
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
  }

  @override
  void dispose() {
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
        loadImage: vm.imageData,
        allowPublic: !team.isPrivateGroup,
      ),
    );
    if (draft != null) vm.savePost.execute((teamId: team.id, draft: draft));
  }

  Future<void> _edit(FeedPost p) async {
    final draft = await showDialog<PostDraft>(
      context: context,
      builder: (_) => PostEditorDialog(
        initial: p.post,
        pickImages: vm.pickImages,
        loadImage: vm.imageData,
        allowPublic: !p.team.isPrivateGroup,
      ),
    );
    if (draft != null) vm.savePost.execute((teamId: p.team.id, draft: draft));
  }

  Future<void> _delete(FeedPost p) async {
    if (await confirmDialog(
      context,
      title: 'Delete post?',
      message: 'It will be removed from ${p.team.name} and the feed.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      vm.deletePost.execute(p);
    }
  }

  void _newPersonalEvent() => context.push(Routes.newMyEvent());

  /// A team event for a team the user runs, or a personal one.
  Future<void> _newEvent() async {
    final teams = vm.postableTeams;
    if (teams.isEmpty) {
      context.push(Routes.newMyEvent());
      return;
    }
    final choice = await showDialog<Team?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add an event to'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
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
              onPressed: () => Navigator.pop(context, t),
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
    if (!mounted) return;
    context.push(
      choice == null ? Routes.newMyEvent() : Routes.newEvent(choice.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ScreenSize.of(context).isMobile;
    return Scaffold(
      appBar: mobile ? const MobileTopBar() : null,
      body: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.savePost, vm.joinTeam]),
        builder: (context, _) {
          final city = vm.homeCity;
          return PageScroll(
            children: [
              PageHeader(
                eyebrow:
                    '${city == null ? '' : '$city / '}Your ultimate community',
                title: 'Good things fly together.',
                subtitle: 'Your people. Your teams. Your next point.',
                action: mobile || vm.postableTeams.isEmpty
                    ? null
                    : FilledButton.icon(
                        onPressed: vm.savePost.running ? null : _compose,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Create post'),
                      ),
              ),
              _TabRow(
                selected: _tab,
                onSelect: (t) => setState(() => _tab = t),
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
                    if (vm.nextTeamEvent case final next?)
                      _NextEventStrip(entry: next),
                    _ComingUpCard(
                      events: vm.upcomingEvents.take(2).toList(),
                      onAdd: _newPersonalEvent,
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
      _Composer(
        name: vm.user?.label ?? '',
        photoUrl: vm.user?.photoUrl,
        canPost: vm.postableTeams.isNotEmpty,
        onPost: vm.savePost.running ? null : _compose,
        onEvent: _newEvent,
      ),
      if (vm.teamsLoaded && vm.teams.isEmpty)
        _JoinCard(
          joining: vm.joinTeam.running,
          onJoin: _join,
          onCreate: () => context.go(Routes.createTeam),
          onFind: () => context.go(Routes.explore()),
        ),
      if (!vm.postsLoaded)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      for (final p in vm.posts)
        TeamPostCard(
          post: p.post,
          teamName: p.team.name,
          now: vm.now,
          loadImage: vm.imageData,
          showVisibility: true,
          onOpenTeam: () => context.go(Routes.team(p.team.id)),
          onEdit: vm.canEdit(p.team) ? () => _edit(p) : null,
          onDelete: vm.canEdit(p.team) ? () => _delete(p) : null,
        ),
      if (vm.postsLoaded && vm.teams.isNotEmpty)
        _CaughtUp(empty: vm.posts.isEmpty),
    ],
    _Tab.teams => [
      for (final t in vm.teams)
        _TeamRow(
          team: t,
          next: vm.nextEventFor(t),
          onTap: () => context.go(Routes.team(t.id)),
        ),
      _JoinCard(
        joining: vm.joinTeam.running,
        onJoin: _join,
        onCreate: () => context.go(Routes.createTeam),
        onFind: () => context.go(Routes.explore()),
        hasTeams: vm.teams.isNotEmpty,
      ),
    ],
  };

  List<Widget> _side() => [
    if (vm.nextTeamEvent case final next?) _UpNextCard(entry: next),
    _ComingUpCard(events: vm.upcomingEvents, onAdd: _newPersonalEvent),
    if (vm.nextTournament case final t?) _AroundTheLeague(tournament: t),
    const _Footer(),
  ];
}

// Tabs -----------------------------------------------------------------------

class _TabRow extends StatelessWidget {
  const _TabRow({required this.selected, required this.onSelect});

  final _Tab selected;
  final ValueChanged<_Tab> onSelect;

  @override
  Widget build(BuildContext context) => UnderlineTabs(
    labels: const ['For you', 'Your teams'],
    selected: selected.index,
    onSelect: (i) => onSelect(_Tab.values[i]),
  );
}

// Feed -----------------------------------------------------------------------

class _Composer extends StatelessWidget {
  const _Composer({
    required this.name,
    required this.photoUrl,
    required this.canPost,
    required this.onPost,
    required this.onEvent,
  });

  final String name;
  final String? photoUrl;
  final bool canPost;
  final VoidCallback? onPost;
  final VoidCallback onEvent;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final post = canPost ? onPost : null;
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
                        canPost
                            ? "What's happening on your sideline?"
                            : 'Coaches and captains post here. Add an '
                                  'event to your schedule.',
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
            child: Row(
              children: [
                if (canPost)
                  TextButton.icon(
                    style: compact,
                    onPressed: post,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('Photo'),
                  ),
                TextButton.icon(
                  style: compact,
                  onPressed: onEvent,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: const Text('Event'),
                ),
                const Spacer(),
                if (canPost)
                  TextButton(
                    onPressed: post,
                    style: compact.copyWith(
                      foregroundColor: WidgetStatePropertyAll(c.muted),
                    ),
                    child: const Text('Post →'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CaughtUp extends StatelessWidget {
  const _CaughtUp({required this.empty});

  final bool empty;

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
            child: Text(
              empty
                  ? 'No posts yet. Team news shows up here.'
                  : "You're all caught up with your teams.",
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
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
    this.hasTeams = false,
  });

  final bool joining;
  final VoidCallback onJoin;
  final VoidCallback onCreate;
  final VoidCallback onFind;
  final bool hasTeams;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return FeatureCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(
            hasTeams ? 'Another team?' : 'No team yet',
            color: c.onFeatureMuted,
          ),
          const SizedBox(height: 8),
          Text(
            hasTeams ? 'Join or start one.' : 'Join your team.',
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

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team, required this.next, required this.onTap});

  final Team team;
  final ScheduleEntry? next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final count = team.members.length;
    final e = next?.event;
    return SectionCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          TeamBadge(size: 46, community: team.isCommunity),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: c.ink,
                  ),
                ),
                Text(
                  '${TeamListing.of(team).subtitle} · $count '
                  '${count == 1 ? 'member' : 'members'}',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
                if (e != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Next: ${e.title} · '
                    '${DateFormat.MMMEd().format(e.startsAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: c.muted),
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
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
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

class _AroundTheLeague extends StatelessWidget {
  const _AroundTheLeague({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = tournament;
    final start = t.startDate;
    final place = [t.city, t.state].where((s) => s.isNotEmpty).join(', ');
    return SectionCard(
      onTap: () => context.go(Routes.tournament(t.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Tag('AROUND THE LEAGUE'),
          const SizedBox(height: 10),
          Text(
            t.name,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15.5,
              letterSpacing: -0.3,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (start != null) DateFormat.MMMd().format(start),
              if (place.isNotEmpty) place,
              if (t.divisions.isNotEmpty) t.divisions.join(', '),
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
          const SizedBox(height: 10),
          CardLink(
            label: 'Explore events',
            onTap: () => context.go(Routes.tournaments),
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
