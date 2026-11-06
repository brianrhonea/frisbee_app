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
import '../../core/ui/undo_snack_bar.dart';
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
    vm.editComment.addListener(_onEditComment);
    vm.toggleCommentLike.addListener(_onLikeComment);
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
    vm.editComment.removeListener(_onEditComment);
    vm.toggleCommentLike.removeListener(_onLikeComment);
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

  void _onEditComment() {
    final cmd = vm.editComment;
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

  void _onLikeComment() {
    final cmd = vm.toggleCommentLike;
    if (cmd.result is Error) {
      showErrorSnackBar(context, cmd.result);
      cmd.clearResult();
    }
  }

  void _reply(PostComment c) {
    if (vm.editing != null) _comment.clear();
    vm.replyTo(c);
    _commentFocus.requestFocus();
  }

  void _edit(PostComment c) {
    vm.startEditing(c);
    _comment.text = c.body;
    _comment.selection = TextSelection.collapsed(offset: c.body.length);
    _commentFocus.requestFocus();
  }

  void _cancelReplyOrEdit() {
    if (vm.editing != null) _comment.clear();
    vm.replyTo(null);
  }

  CommentTile _tile(PostComment c) => CommentTile(
    comment: c,
    liked: c.likedByUser(vm.uid),
    onLike: vm.uid.isEmpty ? null : () => vm.toggleCommentLike.execute(c),
    onReply: () => _reply(c),
    onEdit: vm.canEditComment(c) ? () => _edit(c) : null,
    onDelete: vm.canDeleteComment(c) ? () => _deleteComment(c) : null,
  );

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

  void _deleteComment(PostComment c) {
    if (!vm.canDeleteComment(c)) return;
    vm.removals.remove(c);
    showUndoSnackBar(
      context,
      message: 'Comment deleted',
      onUndo: () => vm.removals.undo(c),
    );
  }

  void _send() {
    if (vm.addComment.running || vm.editComment.running) return;
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    if (vm.editing != null) {
      vm.editComment.execute(text);
    } else {
      vm.addComment.execute(text);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.addComment, vm.editComment]),
    builder: (context, _) {
      final post = vm.post;
      final comments = vm.comments;
      final threads = vm.threads ?? const <CommentThread>[];
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
                              for (final t in threads) ...[
                                _tile(t.comment),
                                for (final r in t.replies)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 42),
                                    child: _tile(r),
                                  ),
                              ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (vm.canComment && vm.commentPostId != null)
                    _CommentBox(
                      controller: _comment,
                      focusNode: _commentFocus,
                      sending: vm.addComment.running || vm.editComment.running,
                      onSend: _send,
                      editing: vm.editing != null,
                      replyingTo: vm.replyingTo?.authorName,
                      onCancel: _cancelReplyOrEdit,
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

/// One comment: who, when, and what they said, with Like and Reply
/// below it. Tapping the person opens their profile.
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    this.liked = false,
    this.onLike,
    this.onReply,
    this.onEdit,
    this.onDelete,
  });

  final PostComment comment;

  /// Whether the signed-in user likes it.
  final bool liked;
  final VoidCallback? onLike;
  final VoidCallback? onReply;

  /// For the comment's author.
  final VoidCallback? onEdit;

  /// For the comment's author and the post's author.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final c = comment;
    final name = c.authorName.isEmpty ? 'Someone' : c.authorName;
    final when = c.createdAt == null
        ? 'Just now'
        : DateFormat.MMMd().add_jm().format(c.createdAt!);
    void openAuthor() => openPage(context, Routes.player(c.authorId));
    final small = theme.textTheme.bodySmall?.copyWith(color: muted);
    final action = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: muted,
      textStyle: theme.textTheme.labelMedium,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: openAuthor,
            child: PersonAvatar(
              name: c.authorName,
              photoUrl: c.authorPhotoUrl,
              radius: c.isReply ? 13 : 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
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
                          Text(when, style: small),
                          if (c.edited) Text(' · edited', style: small),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (c.replyToName case final to?)
                        Text(
                          '@$to',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      LinkifiedText(c.body, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      style: liked
                          ? action.copyWith(
                              foregroundColor: WidgetStatePropertyAll(
                                theme.colorScheme.error,
                              ),
                            )
                          : action,
                      onPressed: onLike,
                      icon: Icon(
                        liked ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                      ),
                      label: Text(
                        c.likeCount == 0 ? 'Like' : '${c.likeCount}',
                        semanticsLabel:
                            '${liked ? 'Unlike' : 'Like'}, ${c.likeCount} likes',
                      ),
                    ),
                    if (onReply != null)
                      TextButton(
                        style: action,
                        onPressed: onReply,
                        child: const Text('Reply'),
                      ),
                    if (onEdit != null)
                      TextButton(
                        style: action,
                        onPressed: onEdit,
                        child: const Text('Edit'),
                      ),
                  ],
                ),
              ],
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
    this.editing = false,
    this.replyingTo,
    this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  /// Rewriting one of the user's comments rather than adding one.
  final bool editing;

  /// Whose comment the new one answers.
  final String? replyingTo;

  /// Stops replying or editing.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final empty = controller.text.trim().isEmpty;
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: ConstrainedContent(
          maxWidth: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (editing || replyingTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          editing
                              ? 'Editing your comment'
                              : 'Replying to $replyingTo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      IconButton(
                        tooltip: editing ? 'Cancel editing' : 'Cancel reply',
                        visualDensity: VisualDensity.compact,
                        onPressed: onCancel,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              Padding(
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
                        decoration: InputDecoration(
                          hintText: replyingTo != null
                              ? 'Add a reply…'
                              : 'Add a comment…',
                          border: OutlineInputBorder(),
                          isDense: true,
                          counterText: '',
                        ),
                        onSubmitted: (_) => onSend(),
                      ),
                    ),
                    IconButton(
                      tooltip: editing ? 'Save comment' : 'Post comment',
                      onPressed: empty || sending ? null : onSend,
                      icon: sending
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(editing ? Icons.check : Icons.send),
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
