import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/post_comment.dart';
import '../../../routing/open_link.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/linkified_text.dart';
import '../../core/ui/status_views.dart';
import '../view_models/post_detail_viewmodel.dart';
import 'post_widgets.dart';
import 'post_composer.dart';
import '../../workouts/widgets/route_widgets.dart';

/// A post on its own page, with its comments and a box to add one.
/// [focusComment] puts the cursor in the box (Comment on a feed post).
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.viewModel,
    this.focusComment = false,
  });

  final PostDetailViewModel viewModel;
  final bool focusComment;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();

  PostDetailViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.delete.addListener(_onDelete);
    vm.addComment.addListener(_onAddComment);
    vm.deleteComment.addListener(_onDeleteComment);
    _comment.addListener(() => setState(() {}));
    if (widget.focusComment) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _commentFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    vm.delete.removeListener(_onDelete);
    vm.addComment.removeListener(_onAddComment);
    vm.deleteComment.removeListener(_onDeleteComment);
    _comment.dispose();
    _commentFocus.dispose();
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

  void _onAddComment() {
    final cmd = vm.addComment;
    switch (cmd.result) {
      case Ok():
        cmd.clearResult();
        _comment.clear();
      case Error():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  void _onDeleteComment() {
    final cmd = vm.deleteComment;
    if (cmd.result is Error) {
      showErrorSnackBar(context, cmd.result);
      cmd.clearResult();
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete post?',
      message: 'It, its photos and its comments are removed for everyone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) vm.delete.execute();
  }

  Future<void> _confirmDeleteComment(PostComment c) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete comment?',
      message: 'It is removed for everyone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) vm.deleteComment.execute(c);
  }

  void _send() {
    if (vm.addComment.running) return;
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    vm.addComment.execute(text);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.addComment]),
    builder: (context, _) {
      final post = vm.post;
      final comments = vm.comments;
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
            : Column(
                children: [
                  Expanded(
                    child: ConstrainedContent(
                      maxWidth: 640,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          UserPostCard(
                            post: post,
                            loadImage: vm.imageData,
                            onEdit: vm.isMine
                                ? () =>
                                      showPostComposer(context, postId: post.id)
                                : null,
                            onDelete: vm.isMine ? _confirmDelete : null,
                            actions: vm.actions,
                            onRepost: () =>
                                repostOrUndo(context, vm.actions, post),
                            onComment: vm.canComment
                                ? _commentFocus.requestFocus
                                : null,
                          ),
                          if (post.workout case final w? when w.route != null)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: WorkoutSplits(workout: w),
                              ),
                            ),
                          if (vm.canComment) ...[
                            const SizedBox(height: 12),
                            _CommentsHeading(count: comments?.length),
                            if (comments == null)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (vm.commentsError != null &&
                                comments.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(errorMessage(vm.commentsError)),
                              )
                            else if (comments.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Text(
                                  'No comments yet. Be the first.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            else
                              for (final c in comments)
                                CommentTile(
                                  comment: c,
                                  onDelete: vm.canDeleteComment(c)
                                      ? () => _confirmDeleteComment(c)
                                      : null,
                                ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (vm.canComment && vm.commentPostId != null)
                    _CommentBox(
                      controller: _comment,
                      focusNode: _commentFocus,
                      sending: vm.addComment.running,
                      onSend: _send,
                    ),
                ],
              ),
      );
    },
  );
}

class _CommentsHeading extends StatelessWidget {
  const _CommentsHeading({required this.count});

  final int? count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Text(
      count == null || count == 0 ? 'Comments' : 'Comments ($count)',
      style: Theme.of(context).textTheme.titleSmall,
    ),
  );
}

/// One comment: who, when, and what they said. Tapping the person opens
/// their profile.
class CommentTile extends StatelessWidget {
  const CommentTile({super.key, required this.comment, this.onDelete});

  final PostComment comment;

  /// For the comment's author and the post's author.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = comment;
    final name = c.authorName.isEmpty ? 'Someone' : c.authorName;
    final when = c.createdAt == null
        ? 'Just now'
        : DateFormat.MMMd().add_jm().format(c.createdAt!);
    void openAuthor() => openPage(context, Routes.player(c.authorId));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: openAuthor,
            child: PersonAvatar(
              name: c.authorName,
              photoUrl: c.authorPhotoUrl,
              radius: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: InkWell(
                          onTap: openAuthor,
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        when,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  LinkifiedText(c.body, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete comment',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
        ],
      ),
    );
  }
}

class _CommentBox extends StatelessWidget {
  const _CommentBox({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final empty = controller.text.trim().isEmpty;
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: ConstrainedContent(
          maxWidth: 640,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: PostComment.maxBody,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment…',
                      border: OutlineInputBorder(),
                      isDense: true,
                      counterText: '',
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                IconButton(
                  tooltip: 'Post comment',
                  onPressed: empty || sending ? null : onSend,
                  icon: sending
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
