import 'package:flutter/material.dart';

import '../../../domain/models/team_post.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/user_avatar.dart';
import '../view_models/team_post_comments_viewmodel.dart';
import '../../../domain/models/moderation.dart';
import '../../moderation/widgets/report_sheet.dart';

/// A team post's comments in a sheet (redesign F24): the thread, oldest
/// first, and a box to add one. [create] makes its view model, which the
/// sheet disposes.
class TeamPostCommentsSheet extends StatefulWidget {
  const TeamPostCommentsSheet({
    super.key,
    required this.create,
    required this.title,
  });

  final TeamPostCommentsViewModel Function() create;
  final String title;

  @override
  State<TeamPostCommentsSheet> createState() => _TeamPostCommentsSheetState();
}

class _TeamPostCommentsSheetState extends State<TeamPostCommentsSheet> {
  late final TeamPostCommentsViewModel vm = widget.create();
  final _text = TextEditingController();

  /// The last add or delete that failed, shown in the sheet (a snack bar
  /// would sit under it).
  String? _problem;

  @override
  void initState() {
    super.initState();
    vm.add.addListener(_onAdd);
    vm.delete.addListener(_onDelete);
  }

  @override
  void dispose() {
    vm.add.removeListener(_onAdd);
    vm.delete.removeListener(_onDelete);
    vm.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onAdd() {
    final result = vm.add.result;
    if (result == null || vm.add.running) return;
    vm.add.clearResult();
    setState(() {
      if (result case Error(:final error)) {
        _problem = errorMessage(error);
      } else {
        _problem = null;
        _text.clear();
      }
    });
  }

  void _onDelete() {
    final result = vm.delete.result;
    if (result == null || vm.delete.running) return;
    vm.delete.clearResult();
    setState(
      () => _problem = switch (result) {
        Error(:final error) => errorMessage(error),
        _ => null,
      },
    );
  }

  Future<void> _delete(TeamPostComment c) async {
    if (await confirmDialog(
      context,
      title: 'Delete comment?',
      message: "It can't be undone.",
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      vm.delete.execute(c.id);
    }
  }

  void _send() {
    if (vm.add.running || _text.text.trim().isEmpty) return;
    vm.add.execute(_text.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListenableBuilder(
          listenable: vm,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: c.ink,
                  ),
                ),
              ),
              Flexible(
                child: !vm.loaded
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpace.xl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : vm.error != null
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(errorMessage(vm.error)),
                      )
                    : vm.comments.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'No comments yet.',
                          style: TextStyle(color: c.muted),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          for (final comment in vm.comments)
                            _CommentRow(
                              comment: comment,
                              onDelete: vm.canDelete(comment)
                                  ? () => _delete(comment)
                                  : null,
                              onReport: canReport(context, comment.authorId)
                                  ? () => showReportSheet(
                                      context,
                                      target: TeamPostCommentReport(
                                        vm.teamId,
                                        vm.postId,
                                        comment.id,
                                      ),
                                      authorName: comment.authorName,
                                      authorId: comment.authorId,
                                    )
                                  : null,
                            ),
                        ],
                      ),
              ),
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    _problem!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const Divider(height: 1),
              if (vm.canWrite)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _text,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: TeamPostComment.maxLength,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Add a comment',
                            counterText: '',
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Send',
                        onPressed: vm.add.running ? null : _send,
                        icon: Icon(Icons.send, color: c.accent),
                      ),
                    ],
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(AppSpace.lg),
                  child: Text('Update the app to comment.'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, this.onDelete, this.onReport});

  final TeamPostComment comment;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final name = comment.authorName.isEmpty ? 'Member' : comment.authorName;
    final when = comment.createdAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(uid: comment.authorId, name: name, radius: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      if (when != null)
                        TextSpan(
                          text: '  ${timeAgo(when, DateTime.now())}',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(comment.body, style: TextStyle(color: c.ink)),
              ],
            ),
          ),
          if (onReport != null)
            IconButton(
              tooltip: 'Report comment',
              visualDensity: VisualDensity.compact,
              onPressed: onReport,
              icon: Icon(Icons.flag_outlined, size: 18, color: c.muted),
            ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete comment',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, size: 18, color: c.muted),
            ),
        ],
      ),
    );
  }
}
