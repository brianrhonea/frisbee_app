import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../view_models/community_feed_viewmodel.dart';
import 'browse_widgets.dart';

/// The newest public posts on Stall 10: where website visitors land, and
/// everyone's "what's happening" next to members' own Home feed.
class CommunityFeedScreen extends StatelessWidget {
  const CommunityFeedScreen({super.key, required this.viewModel});

  final CommunityFeedViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => BrowsePage(
        eyebrow: 'Community',
        title: "What's happening in ultimate",
        subtitle: 'The newest posts from players on Stall 10.',
        load: vm.load,
        loaded: vm.posts.isNotEmpty || vm.load.completed,
        children: [
          PublicPostList(
            posts: vm.posts,
            loadImage: vm.loadImage,
            loadMore: vm.loadMore,
            hasMore: vm.hasMore,
            onOpen: vm.signedIn ? (p) => context.push(Routes.post(p.id)) : null,
            empty: 'No posts yet. Be the first!',
          ),
        ],
      ),
    );
  }
}
