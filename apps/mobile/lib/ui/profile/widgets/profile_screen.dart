import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/profile/profile_repository.dart';
import '../../../domain/models/player_profile.dart';
import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';
import '../../core/ui/tone.dart';
import '../../core/ui/status_views.dart';
import '../../follow/widgets/follow_button.dart';
import '../../posts/widgets/post_widgets.dart';
import '../../workouts/widgets/record_button.dart';
import '../view_models/player_profile_viewmodel.dart';
import 'team_history_section.dart';
import '../../posts/widgets/post_composer.dart';
import '../../core/ui/skeleton.dart';
import '../../../domain/models/moderation.dart';
import '../../moderation/widgets/report_sheet.dart';
import '../../core/ui/app_segmented_button.dart';
import '../../core/ui/avatar.dart';
import '../../core/ui/cover_header.dart';
import '../../core/ui/segmented_tabs.dart';
import '../../core/ui/summary_tiles.dart';

enum _Tab { overview, posts, stats, teams }

enum _SafetyAction { report, block, unblock }

/// A player's profile: who they are, their numbers, recent games and
/// teams. On the user's own profile they can edit it, link their roster
/// spots, and open Settings from the gear at the top right.
class PlayerProfileScreen extends StatefulWidget {
  const PlayerProfileScreen({super.key, required this.viewModel});

  final PlayerProfileViewModel viewModel;

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  PlayerProfileViewModel get vm => widget.viewModel;
  var _tab = _Tab.overview;

  late final List<Command<void>> _commands = [
    vm.saveDetails,
    vm.unlink,
    vm.deletePost,
    vm.changeImage,
    vm.removeImage,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
    vm.message.addListener(_onMessage);
  }

  @override
  void dispose() {
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
    vm.message.removeListener(_onMessage);
    super.dispose();
  }

  void _onCommand() {
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
    if (vm.saveDetails.completed) {
      vm.saveDetails.clearResult();
      showSnackBar(context, 'Profile saved');
    }
  }

  void _onMessage() {
    switch (vm.message.result) {
      case Ok<String>(:final value):
        vm.message.clearResult();
        context.push(Routes.conversation(value));
      case Error<String>():
        showErrorSnackBar(context, vm.message.result);
        vm.message.clearResult();
      case null:
        break;
    }
  }

  Future<void> _deletePost(String id) async {
    if (await confirmDialog(
      context,
      title: 'Delete post?',
      message: 'It and its photos are removed for everyone.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      vm.deletePost.execute(id);
    }
  }

  Future<void> _edit() async {
    final details = await showDialog<ProfileDetails>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (_) => EditProfileDialog(
        initial: vm.details,
        images: vm.canEditImages ? vm : null,
      ),
    );
    if (details != null) vm.saveDetails.execute(details);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ScreenSize.of(context).isMobile;
    final blocks = watchBlocks(context);
    final safety = !vm.isMe && canReport(context, vm.uid);
    return Scaffold(
      appBar: mobile || !vm.isMe
          ? AppBar(
              title: Text(vm.isMe ? 'My profile' : 'Player profile'),
              actions: [
                if (vm.isMe) const SettingsButton(),
                if (safety)
                  PopupMenuButton<_SafetyAction>(
                    tooltip: 'More',
                    onSelected: (a) => switch (a) {
                      _SafetyAction.report => showReportSheet(
                        context,
                        target: PersonReport(vm.uid),
                        authorName: vm.name,
                        authorId: vm.uid,
                      ),
                      _SafetyAction.block => confirmBlock(
                        context,
                        uid: vm.uid,
                        name: vm.name,
                      ),
                      _SafetyAction.unblock => confirmUnblock(
                        context,
                        uid: vm.uid,
                        name: vm.name,
                      ),
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _SafetyAction.report,
                        child: Text('Report ${vm.name}'),
                      ),
                      if (blocks.blockedByMe(vm.uid))
                        PopupMenuItem(
                          value: _SafetyAction.unblock,
                          child: Text('Unblock ${vm.name}'),
                        )
                      else if (!blocks.hides(vm.uid))
                        PopupMenuItem(
                          value: _SafetyAction.block,
                          child: Text('Block ${vm.name}'),
                        ),
                    ],
                  ),
                const SizedBox(width: 4),
              ],
            )
          : null,
      body: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.saveDetails, vm.message]),
        builder: (context, _) {
          if (!vm.loaded) return const LoadingState();
          // Blocked either way: only their name, and Unblock for the blocker.
          if (!vm.isMe && blocks.hides(vm.uid)) {
            final mine = blocks.blockedByMe(vm.uid);
            return EmptyState(
              icon: Icons.block,
              title: mine ? 'You blocked ${vm.name}' : vm.name,
              message: mine
                  ? "You won't see each other's posts or messages."
                  : "This profile isn't available.",
              action: mine
                  ? OutlinedButton(
                      onPressed: () =>
                          confirmUnblock(context, uid: vm.uid, name: vm.name),
                      child: const Text('Unblock'),
                    )
                  : null,
            );
          }
          if (!vm.isMe && vm.profile == null) {
            return vm.error != null
                ? ErrorState(error: vm.error)
                : const EmptyState(
                    icon: Icons.person_off_outlined,
                    title: 'Profile not available',
                  );
          }
          return PageScroll(
            children: [
              _Hero(
                viewModel: vm,
                onEdit: _edit,
                tab: _tab,
                onTab: (t) => setState(() => _tab = t),
              ),
              const SizedBox(height: 16),
              if (vm.locked) _PrivateNotice(name: vm.name) else ..._body(),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _body() {
    final side = [
      if (vm.isMe && vm.linkedSpots.isNotEmpty) _RosterSpotsCard(viewModel: vm),
      _OffTheSheet(details: vm.details, primary: vm.primaryTeam),
      if (vm.showsTeams) _TeamsCard(viewModel: vm),
    ];
    return switch (_tab) {
      _Tab.overview => [
        SideColumnLayout(
          main: [
            _NumbersCard(viewModel: vm),
            if (vm.showsGames) ..._games(),
          ],
          side: side,
        ),
      ],
      _Tab.posts => _posts(),
      _Tab.stats => [
        _NumbersCard(viewModel: vm),
        const SizedBox(height: 14),
        _SeasonsCard(viewModel: vm),
      ],
      _Tab.teams => [
        SideColumnLayout(
          main: [
            _TeamsCard(viewModel: vm, wide: true),
            TeamHistorySection(uid: vm.uid, isMe: vm.isMe),
          ],
          side: [
            if (vm.isMe && vm.linkedSpots.isNotEmpty)
              _RosterSpotsCard(viewModel: vm),
          ],
        ),
      ],
    };
  }

  List<Widget> _posts() {
    final c = AppColors.of(context);
    return [
      if (vm.isMe)
        // Small chips, not big buttons, with room before the posts.
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('New post'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showPostComposer(context),
                ),
                ActionChip(
                  avatar: const Icon(Icons.directions_run, size: 16),
                  label: const Text('Log a workout'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showPostComposer(context, workout: true),
                ),
                const RecordWorkoutButton(chip: true),
              ],
            ),
          ),
        ),
      if (!vm.postsLoaded)
        const Skeleton(child: SkeletonPost())
      else if (vm.postsError != null)
        ErrorState(error: vm.postsError)
      else if (vm.posts.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            vm.isMe
                ? 'Share an update or a workout with the people who follow '
                      'you.'
                : 'No posts yet.',
            textAlign: TextAlign.center,
            style: AppText.secondary.copyWith(color: c.muted),
          ),
        )
      else
        for (final p in vm.posts)
          Padding(
            key: ValueKey(p.id),
            padding: const EdgeInsets.only(bottom: 12),
            child: UserPostCard(
              post: p,
              loadImage: vm.imageData,
              onOpen: () => context.push(Routes.post(p.id)),
              onEdit: vm.isMe
                  ? () => showPostComposer(context, postId: p.id)
                  : null,
              onDelete: vm.isMe ? () => _deletePost(p.id) : null,
              actions: vm.actions,
              onRepost: switch (vm.actions) {
                final a? => () => repostOrUndo(context, a, p),
                null => null,
              },
            ),
          ),
    ];
  }

  List<Widget> _games() {
    final c = AppColors.of(context);
    final games = vm.summary.games;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                vm.isMe ? 'From my sideline' : 'Recent games',
                style: AppText.bodyStrong.copyWith(color: c.ink),
              ),
            ),
            if (vm.isMe && !vm.visibility.games) const _HiddenTag(),
          ],
        ),
      ),
      if (games.isEmpty)
        Text(
          'Games show up here once a stat keeper tracks one you play in.',
          style: AppText.secondary.copyWith(color: c.muted),
        ),
      for (final g in games) _GameCard(game: g),
    ];
  }
}

// Header -----------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({
    required this.viewModel,
    required this.onEdit,
    required this.tab,
    required this.onTab,
  });

  final PlayerProfileViewModel viewModel;
  final VoidCallback onEdit;
  final _Tab tab;
  final ValueChanged<_Tab> onTab;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final mobile = ScreenSize.of(context).isMobile;
    final d = vm.details;
    final primary = vm.primaryTeam;
    // The buttons: beside the name on wide screens, under it on phones
    // (where Settings is in the top bar).
    final buttons = <Widget>[
      if (vm.isMe) ...[
        FilledButton.icon(
          onPressed: vm.saveDetails.running ? null : onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit profile'),
        ),
        if (!mobile) const SettingsButton(outlined: true),
      ] else ...[
        if (vm.follow case final follow?) FollowControl(viewModel: follow),
        FilledButton.icon(
          onPressed: vm.message.running ? null : vm.message.execute,
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: const Text('Message'),
        ),
      ],
    ];
    final tabs = [
      _Tab.overview,
      if (vm.social) _Tab.posts,
      _Tab.stats,
      _Tab.teams,
    ];
    final meta = [
      if (d.hometown.isNotEmpty) d.hometown,
      if (d.school.isNotEmpty) d.school,
      if (d.playingSince case final y?) 'Playing since $y',
    ];
    final handle = [
      if (vm.username case final u?) '@$u',
      if (d.pronouns.isNotEmpty) d.pronouns,
    ].join(' · ');
    void openFollowing() => context.push(Routes.following);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CoverHeader(
          title: vm.name,
          subtitle: handle.isEmpty ? null : handle,
          coverUrl: vm.headerUrl,
          avatar: Avatar(
            name: vm.name,
            imageUrl: vm.photoUrl,
            size: 72,
            decorative: true,
          ),
          actions: mobile ? const [] : buttons,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((primary != null && primary.number != null) ||
                  primary?.role != null ||
                  vm.isStaff ||
                  vm.isPrivate) ...[
                const SizedBox(height: AppSpace.md),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (primary != null && primary.number != null)
                      Tag(
                        [
                          '#${primary.number}',
                          ?primary.position,
                        ].join(' · ').toUpperCase(),
                      ),
                    if (primary?.role case final role?) Tag(role.toUpperCase()),
                    if (vm.isStaff) const StaffBadge(),
                    if (vm.isPrivate) const Tag('PRIVATE'),
                  ],
                ),
              ],
              if (d.bio.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                Text(d.bio, style: AppText.body.copyWith(color: c.ink)),
              ],
              if (meta.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                Text(
                  meta.join(' · '),
                  style: AppText.secondary.copyWith(color: c.muted),
                ),
              ],
              if (vm.social) ...[
                const SizedBox(height: AppSpace.md),
                SummaryTiles(
                  tiles: [
                    SummaryTile(
                      value: '${vm.followers}',
                      label: vm.followers == 1 ? 'Follower' : 'Followers',
                      onTap: vm.isMe ? openFollowing : null,
                    ),
                    SummaryTile(
                      value: '${vm.following}',
                      label: 'Following',
                      onTap: vm.isMe ? openFollowing : null,
                    ),
                  ],
                ),
              ],
              if (mobile) ...[
                const SizedBox(height: AppSpace.md),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: buttons,
                ),
              ],
              if (!vm.locked) ...[
                const SizedBox(height: AppSpace.md),
                SegmentedTabs(
                  labels: [for (final t in tabs) t.label],
                  selected: tabs.contains(tab) ? tabs.indexOf(tab) : 0,
                  onSelect: (i) => onTab(tabs[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The header photo, or [fallback] (the default banner) when there's none
/// or it can't load.
class _Banner extends StatelessWidget {
  const _Banner({required this.url, required this.fallback});

  final String? url;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => switch (url) {
    final url? => Image.network(
      url,
      fit: BoxFit.cover,
      semanticLabel: 'Header photo',
      errorBuilder: (_, _, _) => fallback,
    ),
    null => fallback,
  };
}

enum _ImageAction { choose, camera, remove }

/// Changes the profile picture or header photo on the user's own profile:
/// pick one, take one, or remove it.
class _ImageMenu extends StatelessWidget {
  const _ImageMenu({
    required this.viewModel,
    required this.kind,
    required this.icon,
  });

  final PlayerProfileViewModel viewModel;
  final ProfileImage kind;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final scheme = Theme.of(context).colorScheme;
    final hasImage = switch (kind) {
      ProfileImage.photo => vm.photoUrl != null,
      ProfileImage.header => vm.headerUrl != null,
    };
    const size = 20.0;
    return ListenableBuilder(
      listenable: Listenable.merge([vm.changeImage, vm.removeImage]),
      builder: (context, _) => Material(
        color: scheme.surface.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        elevation: 1,
        child: vm.changeImage.running || vm.removeImage.running
            ? Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox.square(
                  dimension: size,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : PopupMenuButton<_ImageAction>(
                tooltip: 'Change ${kind.label}',
                iconSize: size,
                padding: const EdgeInsets.all(AppSpace.sm),
                icon: Icon(icon),
                onSelected: (a) => switch (a) {
                  _ImageAction.choose => vm.changeImage.execute((
                    kind,
                    camera: false,
                  )),
                  _ImageAction.camera => vm.changeImage.execute((
                    kind,
                    camera: true,
                  )),
                  _ImageAction.remove => vm.removeImage.execute(kind),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _ImageAction.choose,
                    child: ListTile(
                      leading: Icon(Icons.photo_library_outlined),
                      title: Text('Choose photo'),
                    ),
                  ),
                  if (vm.canUseCamera)
                    const PopupMenuItem(
                      value: _ImageAction.camera,
                      child: ListTile(
                        leading: Icon(Icons.photo_camera_outlined),
                        title: Text('Take photo'),
                      ),
                    ),
                  if (hasImage)
                    PopupMenuItem(
                      value: _ImageAction.remove,
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text('Remove ${kind.label}'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _PrivateNotice extends StatelessWidget {
  const _PrivateNotice({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpace.xxl,
        horizontal: 24,
      ),
      child: Column(
        children: [
          Icon(Icons.lock_outline, size: 40, color: c.muted),
          const SizedBox(height: 12),
          Text(
            'This profile is private',
            style: AppText.bodyStrong.copyWith(color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            "Follow $name to see their posts, teams and stats. They'll "
            'get a request to accept.',
            textAlign: TextAlign.center,
            style: AppText.secondary.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}

extension on _Tab {
  String get label => switch (this) {
    _Tab.overview => 'Overview',
    _Tab.posts => 'Posts',
    _Tab.stats => 'Stats',
    _Tab.teams => 'Teams',
  };
}

class _HiddenTag extends StatelessWidget {
  const _HiddenTag();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Only you can see this. Change it in Settings → Privacy.',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.visibility_off_outlined,
          size: 14,
          color: AppColors.of(context).muted,
        ),
        const SizedBox(width: 4),
        Text(
          'Hidden',
          style: AppText.caption.copyWith(color: AppColors.of(context).muted),
        ),
      ],
    ),
  );
}

// Stats ------------------------------------------------------------------

String _pct(double? v) => v == null ? '–' : '${(v * 100).round()}%';

String _avg(double? v) => v == null ? '' : '${v.toStringAsFixed(1)} per game';

class _NumbersCard extends StatelessWidget {
  const _NumbersCard({required this.viewModel});

  final PlayerProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    final t = vm.totals;
    final seasons = vm.seasons;
    final updated = vm.isMe ? null : vm.summary.updatedAt;
    final choice = vm.statsChoice;
    final teams = switch (choice.team) {
      final picked? => {picked.name},
      null =>
        vm.summary.teams
            .where((x) => x.number != null || x.kind.name == 'team')
            .map((x) => x.name)
            .toSet(),
    };
    // The app font named: a dropdown's style replaces the theme's whole.
    final menuStyle = AppText.caption.copyWith(
      fontWeight: FontWeight.w600,
      color: c.accent,
    );
    return SectionCard(
      title: 'By the numbers',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (vm.isMe && !vm.visibility.stats) ...[
            const _HiddenTag(),
            const SizedBox(width: 8),
          ],
          if (choice.options.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: DropdownButton<String?>(
                value: choice.teamId,
                isDense: true,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                style: menuStyle,
                hint: const Text('All teams'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All teams', overflow: TextOverflow.ellipsis),
                  ),
                  for (final t in choice.options)
                    DropdownMenuItem(
                      value: t.id,
                      child: Text(t.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: vm.selectStatsTeam,
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (seasons.isNotEmpty)
            DropdownButton<String?>(
              value: vm.season,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: menuStyle,
              items: [
                const DropdownMenuItem(value: null, child: Text('All time')),
                for (final s in seasons)
                  DropdownMenuItem(value: s, child: Text('$s season')),
              ],
              onChanged: vm.selectSeason,
            ),
        ],
      ),
      child: !vm.showsStats
          ? Text(
              'Stats are private.',
              style: AppText.secondary.copyWith(color: c.muted),
            )
          : t.isEmpty
          ? Text(
              vm.isMe
                  ? 'No tracked games yet. Once a team admin links you to '
                        'your roster spot, your numbers fill in as your team '
                        'tracks games.'
                  : 'No tracked games yet.',
              style: AppText.secondary.copyWith(color: c.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Tiles of three (two on the narrowest cards), the
                    // number in the score face over its label.
                    const gap = 8.0;
                    final columns = constraints.maxWidth >= 240 ? 3 : 2;
                    final width =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;
                    final blocks = [
                      ('${t.assists}', 'Assists', _avg(t.perGame(t.assists))),
                      ('${t.goals}', 'Goals', _avg(t.perGame(t.goals))),
                      ('${t.blocks}', 'Blocks', _avg(t.perGame(t.blocks))),
                      (
                        _pct(t.completionPct),
                        'Completion',
                        '${t.throws} throws',
                      ),
                      ('${t.games}', 'Games played', ''),
                      (
                        '${t.points}',
                        'Points played',
                        _avg(t.perGame(t.points)),
                      ),
                    ];
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final (value, label, note) in blocks)
                          Container(
                            width: width,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(
                                AppRadius.control,
                              ),
                              border: Border.all(color: c.border),
                            ),
                            child: Column(
                              children: [
                                ScoreText(value, size: 28),
                                const SizedBox(height: 2),
                                Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.caption.copyWith(
                                    color: c.ink2,
                                  ),
                                ),
                                if (note.isNotEmpty)
                                  Text(
                                    note,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.caption.copyWith(
                                      color: c.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  [
                    if (teams.isNotEmpty) teams.join(', '),
                    if (updated != null)
                      'Updated ${DateFormat.MMMd().format(updated)}',
                  ].join(' · '),
                  style: AppText.caption.copyWith(color: c.muted),
                ),
              ],
            ),
    );
  }
}

class _SeasonsCard extends StatelessWidget {
  const _SeasonsCard({required this.viewModel});

  final PlayerProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    if (!vm.showsStats || vm.seasons.isEmpty) return const SizedBox.shrink();
    const columns = [
      'Season',
      'Games',
      'Points',
      'Goals',
      'Assists',
      'Blocks',
      'Comp %',
      'Catches',
      'Drops',
      'Turns',
    ];
    List<String> row(String label, StatTotals t) => [
      label,
      '${t.games}',
      '${t.points}',
      '${t.goals}',
      '${t.assists}',
      '${t.blocks}',
      _pct(t.completionPct),
      '${t.catches}',
      '${t.drops}',
      '${t.throwaways}',
    ];
    final rows = [
      for (final s in vm.seasons) row(s, vm.seasonTotals[s]!),
      row('Career', vm.career),
    ];
    return SectionCard(
      title: switch (vm.statsChoice.team) {
        final team? => 'Season by season · ${team.name}',
        null => 'Season by season',
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 40,
          horizontalMargin: 0,
          columnSpacing: 22,
          headingTextStyle: AppText.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: c.muted,
          ),
          columns: [for (final h in columns) DataColumn(label: Text(h))],
          rows: [
            for (final r in rows)
              DataRow(
                cells: [
                  for (final v in r)
                    DataCell(
                      Text(
                        v,
                        style: AppText.secondary.copyWith(
                          color: c.ink,
                          fontWeight: r.first == 'Career'
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game});

  final ProfileGame game;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = game;
    final l = g.line;
    final result = g.tied ? 'T' : (g.won ? 'W' : 'L');
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, size: 15, color: c.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Eyebrow(
                  'Match day · ${DateFormat.MMMd().format(g.date)}',
                ),
              ),
              // The result in the score face; a win in turf.
              ScoreText(
                '$result ${g.ourScore}–${g.theirScore}',
                size: 20,
                color: g.won ? c.positive : c.ink2,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${g.teamName} vs. ${g.opponent}',
            style: AppText.label.copyWith(color: c.ink),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final s in [
                '${l.assists} ${l.assists == 1 ? 'assist' : 'assists'}',
                '${l.goals} ${l.goals == 1 ? 'goal' : 'goals'}',
                '${l.blocks} ${l.blocks == 1 ? 'block' : 'blocks'}',
                _pct(l.completionPct),
              ])
                Expanded(
                  child: Text(s, style: AppText.caption.copyWith(color: c.ink)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// Side cards -------------------------------------------------------------

class _OffTheSheet extends StatelessWidget {
  const _OffTheSheet({required this.details, required this.primary});

  final ProfileDetails details;
  final ProfileTeam? primary;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final d = details;
    final now = DateTime.now().year;
    final rows = [
      if (d.hometown.isNotEmpty) (Icons.place_outlined, 'Based in', d.hometown),
      if (d.school.isNotEmpty) (Icons.school_outlined, 'School', d.school),
      if (d.throwingHand case final h?)
        (Icons.back_hand_outlined, 'Throwing hand', h.label),
      if (primary?.position case final p?)
        (Icons.sports_handball_outlined, 'Position', p),
      if (d.playingSince case final y?)
        (
          Icons.history,
          'Experience',
          '${now - y + 1} ${now - y + 1 == 1 ? 'season' : 'seasons'}',
        ),
    ];
    return SectionCard(
      title: 'Off the stat sheet',
      child: rows.isEmpty
          ? Text(
              'Nothing here yet.',
              style: AppText.secondary.copyWith(color: c.muted),
            )
          : Column(
              children: [
                for (final (icon, label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(icon, size: 15, color: c.muted),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: AppText.caption.copyWith(color: c.muted),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            value,
                            textAlign: TextAlign.end,
                            style: AppText.label.copyWith(color: c.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TeamsCard extends StatelessWidget {
  const _TeamsCard({required this.viewModel, this.wide = false});

  final PlayerProfileViewModel viewModel;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    final teams = vm.shownTeams;
    final kinds = vm.teamKindCounts;
    return SectionCard(
      title: vm.isMe ? 'My teams' : 'Teams',
      action: vm.isMe && !vm.visibility.teams ? const _HiddenTag() : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!vm.showsTeams)
            Text(
              'Teams are private.',
              style: AppText.secondary.copyWith(color: c.muted),
            )
          else if (teams.isEmpty)
            Text(
              'Not on a team yet.',
              style: AppText.secondary.copyWith(color: c.muted),
            ),
          if (vm.showsTeams && vm.filtersTeams)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ToneFilterBar<TeamKind>(
                filters: [
                  (
                    value: null,
                    label: 'All',
                    tone: null,
                    count: vm.summary.teams.length,
                  ),
                  for (final MapEntry(key: k, value: n) in kinds.entries)
                    (value: k, label: k.pluralLabel, tone: k.tone, count: n),
                ],
                selected: vm.teamKindFilter,
                onSelected: vm.setTeamKindFilter,
              ),
            ),
          if (vm.showsTeams)
            for (final t in teams)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.go(Routes.team(t.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      TeamBadge(size: 38, community: t.kind != TeamKind.team),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              style: AppText.label.copyWith(color: c.ink),
                            ),
                            Text(
                              [
                                if (t.subtitle.isNotEmpty) t.subtitle,
                                ?t.role,
                                if (t.number != null) '#${t.number}',
                              ].join(' · '),
                              maxLines: wide ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ToneTag(label: t.kind.shortLabel, tone: t.kind.tone),
                      Icon(Icons.chevron_right, size: 18, color: c.muted),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Each kind of team's tone and names on a profile's Teams card.
extension on TeamKind {
  /// Neutral for every kind: the label says which, not a hue.
  Tone get tone => Tone.grey;

  String get shortLabel => switch (this) {
    TeamKind.team => 'Team',
    TeamKind.community => 'Pickup',
    TeamKind.organization => 'School/club',
  };

  String get pluralLabel => switch (this) {
    TeamKind.team => 'Teams',
    TeamKind.community => 'Pickup communities',
    TeamKind.organization => 'Schools & clubs',
  };
}

/// The roster spots a team admin has linked to the user, whose stats count
/// on their profile. Linking is the admin's; the user can only unlink
/// themselves (their privacy).
class _RosterSpotsCard extends StatelessWidget {
  const _RosterSpotsCard({required this.viewModel});

  final PlayerProfileViewModel viewModel;

  Future<void> _unlink(BuildContext context, LinkedSpot spot) async {
    final ok = await confirmDialog(
      context,
      title: 'Unlink from ${spot.team.name}?',
      message:
          'Your stats from ${spot.team.name} stop counting on your profile. '
          'A team admin can link you again.',
      confirmLabel: 'Unlink',
      destructive: true,
    );
    if (ok) viewModel.unlink.execute((spot.team.id, spot.player.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SectionCard(
      title: 'Roster spots',
      child: ListenableBuilder(
        listenable: viewModel.unlink,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A team admin links you to your spot on the roster.',
              style: AppText.caption.copyWith(color: c.muted),
            ),
            for (final spot in viewModel.linkedSpots)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spot.team.name,
                            style: AppText.bodyStrong.copyWith(color: c.ink),
                          ),
                          Text(
                            [
                              spot.player.name,
                              if (spot.player.number != null)
                                '#${spot.player.number}',
                            ].join(' · '),
                            style: AppText.caption.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: viewModel.unlink.running
                          ? null
                          : () => _unlink(context, spot),
                      child: const Text('Unlink'),
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

// Editing ----------------------------------------------------------------

/// Edits the user's profile details and what others see; pops with the
/// new details or null. With [images], it also changes the profile
/// picture and header photo (those save straight away).
class EditProfileDialog extends StatefulWidget {
  const EditProfileDialog({super.key, required this.initial, this.images});

  final ProfileDetails initial;

  /// The user's own profile, whose pictures this changes.
  final PlayerProfileViewModel? images;

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  late final _bio = TextEditingController(text: widget.initial.bio);
  late final _pronouns = TextEditingController(text: widget.initial.pronouns);
  late final _hometown = TextEditingController(text: widget.initial.hometown);
  late final _school = TextEditingController(text: widget.initial.school);
  late final _since = TextEditingController(
    text: widget.initial.playingSince?.toString() ?? '',
  );
  late ThrowingHand? _hand = widget.initial.throwingHand;

  @override
  void dispose() {
    for (final c in [_bio, _pronouns, _hometown, _school, _since]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final year = int.tryParse(_since.text);
    final now = DateTime.now().year;
    Navigator.pop(
      context,
      ProfileDetails(
        bio: _bio.text,
        pronouns: _pronouns.text,
        hometown: _hometown.text,
        school: _school.text,
        throwingHand: _hand,
        playingSince: year != null && year >= 1960 && year <= now ? year : null,
        // Set in Settings → Privacy.
        visibility: widget.initial.visibility,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget field(
      TextEditingController controller,
      String label, {
      int maxLength = 60,
      int maxLines = 1,
      TextInputType? keyboard,
      List<TextInputFormatter>? formatters,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: keyboard,
        inputFormatters: formatters,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, counterText: ''),
      ),
    );
    return AlertDialog(
      title: const Text('Edit profile'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.images case final vm?) ...[
                _EditImages(viewModel: vm),
                const SizedBox(height: 12),
              ],
              field(_bio, 'Bio', maxLength: ProfileDetails.maxBio, maxLines: 4),
              field(_pronouns, 'Pronouns', maxLength: 30),
              field(_hometown, 'Based in (city)'),
              field(_school, 'School'),
              field(
                _since,
                'Playing since (year)',
                maxLength: 4,
                keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              Text(
                'Throwing hand',
                style: AppText.caption.copyWith(color: c.muted),
              ),
              const SizedBox(height: 6),
              AppSegmentedButton<ThrowingHand?>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: null, label: Text('–')),
                  for (final h in ThrowingHand.values)
                    ButtonSegment(value: h, label: Text(h.label)),
                ],
                selected: {_hand},
                onSelectionChanged: (s) => setState(() => _hand = s.first),
              ),
              const SizedBox(height: 16),
              Text(
                'Choose who sees your stats, games and teams in Settings → '
                'Privacy.',
                style: AppText.caption.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// The profile picture and header photo at the top of Edit profile, each
/// with a menu to choose, take or remove one.
class _EditImages extends StatelessWidget {
  const _EditImages({required this.viewModel});

  final PlayerProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: PersonAvatar(
              name: vm.name,
              photoUrl: vm.photoUrl,
              radius: 22,
            ),
            title: const Text('Profile picture'),
            trailing: _ImageMenu(
              viewModel: vm,
              kind: ProfileImage.photo,
              icon: Icons.photo_camera_outlined,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 64,
                height: 36,
                child: _Banner(
                  url: vm.headerUrl,
                  fallback: ColoredBox(color: c.feature),
                ),
              ),
            ),
            title: const Text('Header photo'),
            trailing: _ImageMenu(
              viewModel: vm,
              kind: ProfileImage.header,
              icon: Icons.add_a_photo_outlined,
            ),
          ),
          Text(
            'Photo changes save right away.',
            style: AppText.caption.copyWith(color: c.muted),
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}

// Settings ---------------------------------------------------------------

/// The gear that opens Settings, at the top right of the user's profile.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, this.outlined = false});

  final bool outlined;

  @override
  Widget build(BuildContext context) {
    void open() => context.push(Routes.settings);
    const icon = Icon(Icons.settings_outlined);
    return outlined
        ? IconButton.outlined(tooltip: 'Settings', onPressed: open, icon: icon)
        : IconButton(tooltip: 'Settings', onPressed: open, icon: icon);
  }
}

/// "Stall 10 staff" by a staff member's name (the website's staff-badge).
class StaffBadge extends StatelessWidget {
  const StaffBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      label: 'Stall 10 staff',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
        decoration: BoxDecoration(
          color: c.accent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 12, color: c.onAccent),
            const SizedBox(width: 4),
            Text(
              'STALL 10 STAFF',
              style: AppText.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: c.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
