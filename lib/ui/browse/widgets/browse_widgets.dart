import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/user_post.dart';
import '../../../utils/command.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../posts/widgets/post_widgets.dart';
import '../../teams/widgets/team_post_widgets.dart' show ImageLoader;
import '../../web/widgets/join_prompt.dart';

/// A browse page: an app bar on phones, a page header elsewhere, then
/// [children] (or the load's status while there's nothing to show).
class BrowsePage extends StatelessWidget {
  const BrowsePage({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    required this.load,
    required this.loaded,
    required this.children,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;

  /// The page's load, for its spinner, error and retry.
  final Command0<void> load;

  /// Whether there's something to show yet.
  final bool loaded;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mobile = ScreenSize.of(context).isMobile;
    return Scaffold(
      appBar: mobile ? AppBar(title: Text(title)) : null,
      body: ListenableBuilder(
        listenable: load,
        builder: (context, _) => PageScroll(
          children: [
            if (!mobile)
              PageHeader(eyebrow: eyebrow, title: title, subtitle: subtitle),
            if (!loaded && load.running)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: LoadingView(),
              )
            else if (!loaded && load.error)
              ErrorView(
                error: "Couldn't load this page.",
                onRetry: load.execute,
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

/// Like, repost and comment counts under a public post. Visitors are asked
/// to join; [onOpen] (for members) opens the post to do it there.
class LockedPostFooter extends StatelessWidget {
  const LockedPostFooter({super.key, required this.post, this.onOpen});

  final UserPost post;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget button(IconData icon, int count, String label, LockedAction a) =>
        TextButton.icon(
          onPressed: onOpen ?? () => showJoinPrompt(context, a),
          style: TextButton.styleFrom(foregroundColor: c.muted),
          icon: Icon(icon, size: 19),
          label: Text(
            count > 0 ? '$count' : '',
            semanticsLabel: '$count $label',
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Row(
        children: [
          button(
            Icons.favorite_border,
            post.likeCount,
            'likes',
            LockedAction.like,
          ),
          button(
            Icons.repeat,
            post.repostCount,
            'reposts',
            LockedAction.repost,
          ),
          button(
            Icons.mode_comment_outlined,
            post.commentCount,
            'comments',
            LockedAction.comment,
          ),
        ],
      ),
    );
  }
}

/// Public posts as cards with [LockedPostFooter]s, and a button for more.
class PublicPostList extends StatelessWidget {
  const PublicPostList({
    super.key,
    required this.posts,
    required this.loadImage,
    required this.loadMore,
    required this.hasMore,
    this.onOpen,
    this.empty = 'No posts yet.',
  });

  final List<UserPost> posts;
  final ImageLoader loadImage;
  final Command0<void> loadMore;
  final bool hasMore;

  /// Opens a post (members); null for visitors.
  final void Function(UserPost post)? onOpen;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return EmptyView(icon: Icons.forum_outlined, title: empty);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in posts) ...[
          UserPostCard(
            post: p,
            loadImage: loadImage,
            onOpen: onOpen == null ? null : () => onOpen!(p),
          ),
          LockedPostFooter(
            post: p,
            onOpen: onOpen == null ? null : () => onOpen!(p),
          ),
          const SizedBox(height: 8),
        ],
        if (hasMore)
          ListenableBuilder(
            listenable: loadMore,
            builder: (context, _) => Center(
              child: loadMore.running
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    )
                  : TextButton(
                      onPressed: loadMore.execute,
                      child: const Text('Show more'),
                    ),
            ),
          ),
      ],
    );
  }
}

/// "Sat, Apr 12 · 6:00 PM".
String eventWhen(DateTime d) => DateFormat('EEE, MMM d · h:mm a').format(d);
