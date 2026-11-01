import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/feed_item.dart';
import '../../../domain/models/user_post.dart';
import '../../../domain/models/workout.dart';
import '../../../routing/routes.dart';
import '../../core/ui/person_avatar.dart';
import '../../teams/widgets/team_post_widgets.dart';

export '../../core/ui/person_avatar.dart';

enum _PostAction { edit, delete }

String _when(DateTime? d) =>
    d == null ? 'Just now' : DateFormat.MMMd().add_jm().format(d);

/// A post someone wrote: who and when, text, a workout, photos and links.
/// Tapping the author opens their profile. [onEdit] and [onDelete] are for
/// the author.
class UserPostCard extends StatelessWidget {
  const UserPostCard({
    super.key,
    required this.post,
    required this.loadImage,
    this.onEdit,
    this.onDelete,
    this.onOpen,
  });

  final UserPost post;
  final ImageLoader loadImage;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Opens the post on its own page; null when already there.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final workout = post.workout;
    final subtitle = [
      _when(post.createdAt),
      if (post.edited) 'edited',
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => context.push(Routes.person(post.authorId)),
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
                              context.push(Routes.person(post.authorId)),
                          child: Text(
                            post.authorName.isEmpty
                                ? 'Someone'
                                : post.authorName,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          workout == null
                              ? subtitle
                              : 'Shared a workout · $subtitle',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post.tournamentName case final t?
                        when t.isNotEmpty) ...[
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
                      SelectableText(
                        post.body,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (workout != null) ...[
                      const SizedBox(height: 10),
                      WorkoutSummary(workout: workout),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData workoutIcon(WorkoutActivity a) => switch (a) {
  WorkoutActivity.run => Icons.directions_run,
  WorkoutActivity.sprints => Icons.bolt,
  WorkoutActivity.throwing => Icons.sports_handball,
  WorkoutActivity.gym => Icons.fitness_center,
  WorkoutActivity.agility => Icons.swap_calls,
  WorkoutActivity.mobility => Icons.self_improvement,
  WorkoutActivity.other => Icons.sports,
};

/// A workout's stats as chips, then its exercises.
class WorkoutSummary extends StatelessWidget {
  const WorkoutSummary({super.key, required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = <(IconData, String, String)>[
      (Icons.timer_outlined, 'Time', workout.durationLabel),
      if (workout.distanceLabel case final d?)
        (Icons.straighten, 'Distance', d),
      if (workout.activity == WorkoutActivity.run)
        if (workout.paceLabel case final p?) (Icons.speed, 'Pace', p),
      if (workout.effort case final e?)
        (Icons.local_fire_department_outlined, 'Effort', '$e/10'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
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
                          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
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
                        child: Text(e.name, style: theme.textTheme.bodyMedium),
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
          ? () => context.push(Routes.editPost(post.id))
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
