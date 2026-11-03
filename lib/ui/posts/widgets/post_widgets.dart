import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../domain/models/feed_item.dart';
import '../../../domain/models/user_post.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_route.dart';
import '../../../routing/open_link.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/layout.dart';
import '../../schedule/widgets/event_style.dart';
import '../../teams/widgets/team_post_widgets.dart';
import '../../workouts/widgets/route_widgets.dart';
import '../view_models/post_actions.dart';
import 'post_composer.dart';
import 'send_post_sheet.dart';

export '../../core/ui/layout.dart' show PersonAvatar;

enum _PostAction { edit, delete }

String _when(DateTime? d) =>
    d == null ? 'Just now' : DateFormat.MMMd().add_jm().format(d);

/// A post someone wrote: who and when, text, a workout, an event, photos
/// and links. A repost shows the reposter's note over the original. Tapping
/// the author opens their profile. [onEdit] and [onDelete] are for the
/// author.
///
/// With [actions], a footer to like, repost, comment on and send it (a
/// repost's original), and a repost's original is loaded from there.
/// [onRepost] asks how to repost or takes the repost back (see
/// [repostOrUndo]). Comment opens the post's page at the comment box,
/// unless [onComment] says otherwise. Send messages it to people.
class UserPostCard extends StatelessWidget {
  const UserPostCard({
    super.key,
    required this.post,
    required this.loadImage,
    this.onEdit,
    this.onDelete,
    this.onOpen,
    this.actions,
    this.onRepost,
    this.onComment,
  });

  final UserPost post;
  final ImageLoader loadImage;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Opens the post on its own page; null when already there.
  final VoidCallback? onOpen;

  final PostActions? actions;
  final VoidCallback? onRepost;

  /// On the post's own page: go to the comment box.
  final VoidCallback? onComment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final repostOf = post.repostOf;
    final subtitle = [
      switch (post.kind) {
        UserPostKind.workout => 'Shared a workout',
        UserPostKind.event => 'Shared an event',
        UserPostKind.repost =>
          'Reposted '
              '${repostOf!.authorName.isEmpty ? 'a post' : "${repostOf.authorName}'s post"}',
        UserPostKind.text => null,
      },
      _when(post.createdAt),
      if (post.edited) 'edited',
    ].nonNulls.join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () =>
                        openPage(context, Routes.player(post.authorId)),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: PersonAvatar(
                        name: post.authorName,
                        photoUrl: post.authorPhotoUrl,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () =>
                              openPage(context, Routes.player(post.authorId)),
                          child: Text(
                            post.authorName.isEmpty
                                ? 'Someone'
                                : post.authorName,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onEdit != null || onDelete != null)
                    PopupMenuButton<_PostAction>(
                      tooltip: 'Post options',
                      onSelected: (a) => switch (a) {
                        _PostAction.edit => onEdit?.call(),
                        _PostAction.delete => onDelete?.call(),
                      },
                      itemBuilder: (_) => [
                        if (onEdit != null)
                          const PopupMenuItem(
                            value: _PostAction.edit,
                            child: Text('Edit'),
                          ),
                        if (onDelete != null)
                          const PopupMenuItem(
                            value: _PostAction.delete,
                            child: Text('Delete'),
                          ),
                      ],
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12, left: 4),
                child: repostOf == null
                    ? _PostContent(post: post, loadImage: loadImage)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (post.body.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            SelectableText(
                              post.body,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                          const SizedBox(height: 10),
                          _EmbeddedPost(
                            loaded: actions?.originalLoaded(post) ?? false,
                            original: actions?.originalOf(post),
                            loadImage: loadImage,
                          ),
                        ],
                      ),
              ),
              if (actions case final a?)
                _PostFooter(
                  post: post,
                  actions: a,
                  onRepost: onRepost,
                  onComment: onComment,
                )
              else
                const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// A post's text, workout, event, photos and links.
class _PostContent extends StatelessWidget {
  const _PostContent({required this.post, required this.loadImage});

  final UserPost post;
  final ImageLoader loadImage;

  /// Where tapping a shared event goes: the event itself for its author,
  /// otherwise the team's page (which shows it if the event is public, and
  /// to members); nowhere for someone else's personal event.
  String? _eventLink(BuildContext context, SharedEvent e) {
    final me = context.read<AuthRepository?>()?.currentUser?.uid;
    final teamId = e.teamId;
    if (me != null && me == post.authorId) {
      return teamId == null
          ? Routes.myEvent(e.eventId)
          : Routes.event(teamId, e.eventId);
    }
    return teamId == null ? null : Routes.team(teamId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final workout = post.workout;
    final event = post.event;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.tournamentName case final t? when t.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'At $t',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (post.body.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(post.body, style: theme.textTheme.bodyMedium),
        ],
        if (workout != null) ...[
          const SizedBox(height: 10),
          WorkoutSummary(workout: workout),
        ],
        if (event != null) ...[
          const SizedBox(height: 10),
          SharedEventCard(
            event: event,
            onTap: switch (_eventLink(context, event)) {
              final link? => () => openPage(context, link),
              null => null,
            },
          ),
        ],
        if (post.images.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in post.images)
                PostImage(
                  image: i,
                  loadImage: loadImage,
                  size: post.images.length == 1 ? 320 : 156,
                ),
            ],
          ),
        ],
        for (final l in post.links)
          PostLinkRow(
            icon: Icons.link,
            text: shortLink(l),
            tooltip: l,
            onTap: () => openPostLink(context, Uri.parse(l)),
          ),
      ],
    );
  }
}

/// The original inside a repost: its author and content, opening on its
/// own page. Says so when it has been deleted.
class _EmbeddedPost extends StatelessWidget {
  const _EmbeddedPost({
    required this.loaded,
    required this.original,
    required this.loadImage,
  });

  final bool loaded;
  final UserPost? original;
  final ImageLoader loadImage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final post = original;
    Widget box(Widget child, {VoidCallback? onTap}) => Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    );
    if (!loaded) {
      return box(
        const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (post == null) {
      return box(
        Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This post is no longer available.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return box(
      onTap: () => context.push(Routes.post(post.id)),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonAvatar(
                name: post.authorName,
                photoUrl: post.authorPhotoUrl,
                radius: 12,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  post.authorName.isEmpty ? 'Someone' : post.authorName,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              Text(
                _when(post.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          _PostContent(post: post, loadImage: loadImage),
        ],
      ),
    );
  }
}

/// Like and Repost, with how many of each. For a repost they count toward
/// its original.
class _PostFooter extends StatelessWidget {
  const _PostFooter({
    required this.post,
    required this.actions,
    this.onRepost,
    this.onComment,
  });

  final UserPost post;
  final PostActions actions;
  final VoidCallback? onRepost;
  final VoidCallback? onComment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = actions.target(post);
    if (target == null) return const SizedBox(height: 8);
    final liked = actions.isLiked(post);
    final reposted = actions.isReposted(post);
    final canRepost = actions.canRepost(post) && onRepost != null;
    // Narrow phones drop the words and keep the counts.
    final narrow = MediaQuery.sizeOf(context).width < 400;
    String count(String label, int n) => n > 0 ? '$n' : (narrow ? '' : label);
    final muted = TextButton.styleFrom(
      foregroundColor: scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => actions.toggleLike.execute(post),
            style: TextButton.styleFrom(
              foregroundColor: liked
                  ? Colors.red.shade400
                  : scheme.onSurfaceVariant,
            ),
            icon: Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              size: 20,
            ),
            label: Text(
              count('Like', target.likeCount),
              semanticsLabel: liked ? 'Unlike' : 'Like',
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            // Your own posts show how often they were reposted.
            onPressed: canRepost ? onRepost : null,
            style: TextButton.styleFrom(
              foregroundColor: reposted
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
            icon: Icon(reposted ? Icons.repeat_on : Icons.repeat, size: 20),
            label: Text(
              reposted
                  ? (target.repostCount > 1
                        ? '${target.repostCount}'
                        : 'Reposted')
                  : count('Repost', target.repostCount),
              semanticsLabel: reposted ? 'Undo repost' : 'Repost',
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed:
                onComment ??
                () => openPage(context, Routes.post(target.id, comment: true)),
            style: muted,
            icon: const Icon(Icons.chat_bubble_outline, size: 20),
            label: Text(
              count('Comment', target.commentCount),
              semanticsLabel: 'Comment',
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Send',
            onPressed: () => showSendPost(context, target),
            color: scheme.onSurfaceVariant,
            icon: const Icon(Icons.send_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Reposts [post] (a repost's original) after asking for an optional note,
/// or, when already reposted, asks to take it back.
Future<void> repostOrUndo(
  BuildContext context,
  PostActions actions,
  UserPost post,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  String problem(Result<void>? r) => r is Error<void>
      ? r.error.toString().replaceFirst('Exception: ', '')
      : '';

  if (actions.isReposted(post)) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Undo your repost?'),
        content: const Text("Your followers won't see it from you any more."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Undo repost'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await actions.undoRepost.execute(post);
    final r = actions.undoRepost.result;
    say(r is Error ? "Couldn't undo it. ${problem(r)}" : 'Repost removed');
    return;
  }
  final original = actions.target(post);
  if (original == null || !context.mounted) return;
  final note = await showDialog<String>(
    context: context,
    builder: (context) => _RepostDialog(original: original),
  );
  if (note == null) return;
  await actions.repost.execute((post: post, note: note));
  final r = actions.repost.result;
  say(
    r is Error
        ? "Couldn't repost it. ${problem(r)}"
        : 'Reposted to your followers',
  );
}

/// Shows what's being reposted and asks for an optional note. Pops with the
/// note (maybe empty), or null when cancelled.
class _RepostDialog extends StatefulWidget {
  const _RepostDialog({required this.original});

  final UserPost original;

  @override
  State<_RepostDialog> createState() => _RepostDialogState();
}

class _RepostDialogState extends State<_RepostDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.original;
    final theme = Theme.of(context);
    final preview = [
      if (o.event case final e?) e.title,
      if (o.workout case final w?) w.activity.label,
      if (o.body.isNotEmpty) o.body,
      if (o.images.isNotEmpty)
        o.images.length == 1 ? 'A photo' : '${o.images.length} photos',
    ].join(' · ');
    return AlertDialog(
      title: const Text('Repost to your followers?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (o.event case final e?)
              SharedEventCard(event: e)
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.authorName.isEmpty ? 'Someone' : o.authorName,
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preview.isEmpty ? 'A post' : preview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Add a note (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _note.text.trim()),
          icon: const Icon(Icons.repeat),
          label: const Text('Repost'),
        ),
      ],
    );
  }
}

/// An event shared in a post: its date, type, title, time, place and team.
class SharedEventCard extends StatelessWidget {
  const SharedEventCard({super.key, required this.event, this.onTap});

  final SharedEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = event.type.color(scheme);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    Widget detail(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: muted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return Material(
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A calendar page: month over day.
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      DateFormat.MMM().format(event.startsAt).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      DateFormat.d().format(event.startsAt),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(event.type.icon, size: 16, color: color),
                        const SizedBox(width: 4),
                        Text(
                          event.type.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(event.title, style: theme.textTheme.titleSmall),
                    detail(
                      Icons.schedule,
                      '${DateFormat.EEEE().format(event.startsAt)} · '
                      '${eventTimeRange(event.asEvent)}',
                    ),
                    if (event.location.isNotEmpty)
                      detail(Icons.place_outlined, event.location),
                    if (event.teamName case final t? when t.isNotEmpty)
                      detail(Icons.groups_outlined, t),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

IconData workoutIcon(WorkoutActivity a) => switch (a) {
  WorkoutActivity.run => Icons.directions_run,
  WorkoutActivity.ride => Icons.directions_bike,
  WorkoutActivity.walk => Icons.directions_walk,
  WorkoutActivity.hike => Icons.hiking,
  WorkoutActivity.sprints => Icons.bolt,
  WorkoutActivity.throwing => Icons.sports_handball,
  WorkoutActivity.gym => Icons.fitness_center,
  WorkoutActivity.agility => Icons.swap_calls,
  WorkoutActivity.mobility => Icons.self_improvement,
  WorkoutActivity.other => Icons.sports,
};

/// A workout's route map, its stats, then its exercises.
class WorkoutSummary extends StatelessWidget {
  const WorkoutSummary({super.key, required this.workout});

  final Workout workout;

  static const _paced = {
    WorkoutActivity.run,
    WorkoutActivity.walk,
    WorkoutActivity.hike,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unit = distanceUnitOf(context);
    final route = workout.route;
    final gain = route?.elevationGainMeters;
    final stats = <(IconData, String, String)>[
      if (workout.distanceLabel(unit) case final d?)
        (Icons.straighten, 'Distance', d),
      (Icons.timer_outlined, 'Time', workout.durationLabel),
      if (workout.activity.showsSpeed)
        if (workout.speedLabel(unit) case final v?) (Icons.speed, 'Speed', v),
      if (_paced.contains(workout.activity))
        if (workout.paceLabel(unit) case final p?) (Icons.speed, 'Pace', p),
      if (gain != null && gain >= 1)
        (
          Icons.terrain_outlined,
          'Elev gain',
          unit == DistanceUnit.mi
              ? '${(gain * 3.28084).round()} ft'
              : '${gain.round()} m',
        ),
      if (workout.effort case final e?)
        (Icons.local_fire_department_outlined, 'Effort', '$e/10'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (route != null && route.path.length >= 2)
            SizedBox(height: 200, child: RouteMap(path: route.path)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(workoutIcon(workout.activity), color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      workout.activity.label,
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    for (final (icon, label, value) in stats)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icon,
                                size: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          Text(value, style: theme.textTheme.titleSmall),
                        ],
                      ),
                  ],
                ),
                if (workout.exercises.isNotEmpty) ...[
                  const Divider(height: 20),
                  for (final e in workout.exercises)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.name,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            e.detail,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One feed entry. Team posts get a header naming the team, which opens
/// it.
class FeedItemCard extends StatelessWidget {
  const FeedItemCard({
    super.key,
    required this.item,
    required this.loadImage,
    required this.uid,
    this.onDeleteUserPost,
  });

  final FeedItem item;
  final ImageLoader loadImage;

  /// The signed-in user, who may edit and delete their own posts.
  final String uid;
  final void Function(UserPost post)? onDeleteUserPost;

  @override
  Widget build(BuildContext context) => switch (item) {
    UserPostItem(:final post) => UserPostCard(
      post: post,
      loadImage: loadImage,
      onOpen: () => context.push(Routes.post(post.id)),
      onEdit: post.authorId == uid
          ? () => showPostComposer(context, postId: post.id)
          : null,
      onDelete: post.authorId == uid && onDeleteUserPost != null
          ? () => onDeleteUserPost!(post)
          : null,
    ),
    TeamPostItem(:final teamId, :final teamName, :final post) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(Routes.team(teamId)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
            child: Row(
              children: [
                Icon(
                  Icons.groups_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    teamName,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        TeamPostCard(post: post, loadImage: loadImage),
      ],
    ),
  };
}
