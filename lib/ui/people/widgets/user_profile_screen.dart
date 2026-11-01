import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../follow/widgets/follow_button.dart';
import '../../posts/widgets/post_widgets.dart';
import '../view_models/user_profile_viewmodel.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.viewModel});

  final UserProfileViewModel viewModel;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  UserProfileViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.message.addListener(_onMessage);
    vm.deletePost.addListener(_onDelete);
  }

  @override
  void dispose() {
    vm.message.removeListener(_onMessage);
    vm.deletePost.removeListener(_onDelete);
    super.dispose();
  }

  void _onMessage() {
    final cmd = vm.message;
    switch (cmd.result) {
      case Ok(:final value):
        cmd.clearResult();
        context.push(Routes.conversation(value));
      case Error():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  void _onDelete() {
    final cmd = vm.deletePost;
    if (cmd.result case Error()) showErrorSnackBar(context, cmd.result);
    cmd.clearResult();
  }

  Future<void> _delete(String id) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete post?',
      message: 'It and its photos are removed for everyone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) vm.deletePost.execute(id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final theme = Theme.of(context);
      final profile = vm.profile;
      return Scaffold(
        appBar: AppBar(title: Text(vm.loaded ? vm.name : '')),
        floatingActionButton: vm.isMe
            ? FloatingActionButton.extended(
                onPressed: () => context.push(Routes.newPost),
                icon: const Icon(Icons.edit),
                label: const Text('New post'),
              )
            : null,
        body: !vm.loaded
            ? const LoadingView()
            : ConstrainedContent(
                maxWidth: 640,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    Row(
                      children: [
                        PersonAvatar(
                          name: vm.name,
                          photoUrl: profile?.photoUrl,
                          radius: 36,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vm.name,
                                style: theme.textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${vm.followers} '
                                '${vm.followers == 1 ? 'follower' : 'followers'}'
                                ' · ${vm.following} following',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (vm.isMe)
                          OutlinedButton.icon(
                            onPressed: () => context.push(Routes.following),
                            icon: const Icon(Icons.people_outline),
                            label: const Text('Following'),
                          )
                        else ...[
                          if (vm.follow case final follow?)
                            FollowControl(viewModel: follow),
                          if (profile != null)
                            ListenableBuilder(
                              listenable: vm.message,
                              builder: (context, _) => OutlinedButton.icon(
                                onPressed: vm.message.running
                                    ? null
                                    : vm.message.execute,
                                icon: const Icon(Icons.chat_bubble_outline),
                                label: const Text('Message'),
                              ),
                            ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('Posts', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (!vm.postsLoaded)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (vm.postsError != null)
                      ErrorView(error: vm.postsError)
                    else if (vm.posts.isEmpty)
                      EmptyView(
                        icon: Icons.dynamic_feed_outlined,
                        title: 'No posts yet',
                        message: vm.isMe
                            ? 'Share an update or a workout with the people '
                                  'who follow you.'
                            : null,
                      )
                    else
                      for (final p in vm.posts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: UserPostCard(
                            post: p,
                            loadImage: vm.imageData,
                            onOpen: () => context.push(Routes.post(p.id)),
                            onEdit: vm.isMe
                                ? () => context.push(Routes.editPost(p.id))
                                : null,
                            onDelete: vm.isMe ? () => _delete(p.id) : null,
                          ),
                        ),
                  ],
                ),
              ),
      );
    },
  );
}
