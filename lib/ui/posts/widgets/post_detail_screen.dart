import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/post_detail_viewmodel.dart';
import 'post_widgets.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.viewModel});

  final PostDetailViewModel viewModel;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  PostDetailViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.delete.addListener(_onDelete);
  }

  @override
  void dispose() {
    vm.delete.removeListener(_onDelete);
    super.dispose();
  }

  void _onDelete() {
    final cmd = vm.delete;
    switch (cmd.result) {
      case Ok():
        cmd.clearResult();
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(Routes.home);
        }
      case Error():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete post?',
      message: 'It and its photos are removed for everyone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) vm.delete.execute();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final post = vm.post;
      return Scaffold(
        appBar: AppBar(title: const Text('Post')),
        body: !vm.loaded
            ? const LoadingView()
            : vm.error != null
            ? ErrorView(error: vm.error)
            : post == null
            ? const EmptyView(
                icon: Icons.article_outlined,
                title: 'Post not found',
                message: 'It may have been deleted.',
              )
            : ConstrainedContent(
                maxWidth: 640,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    UserPostCard(
                      post: post,
                      loadImage: vm.imageData,
                      onEdit: vm.isMine
                          ? () => context.push(Routes.editPost(post.id))
                          : null,
                      onDelete: vm.isMine ? _confirmDelete : null,
                    ),
                  ],
                ),
              ),
      );
    },
  );
}
