import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/team_event.dart';
import '../../../domain/models/video_comment.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/layout.dart' show DateBadge, SectionCard, timeAgo;
import '../view_models/video_viewmodel.dart';

// A video page's extras (redesign F4-F6): the event it's tagged to, its
// notes and clips (tap one to play from there), and its comments.

/// The event the video is tagged to, and for admins tag / change / remove.
class VideoEventTag extends StatelessWidget {
  const VideoEventTag({super.key, required this.viewModel});

  final VideoViewModel viewModel;

  Future<void> _pick(BuildContext context) async {
    final vm = viewModel;
    final current = vm.video?.eventId ?? '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _EventPicker(viewModel: vm, current: current),
    );
    if (picked != null && picked != current) {
      await vm.tagEvent.execute(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    final eventId = vm.video?.eventId ?? '';
    if (eventId.isEmpty) {
      if (!vm.canTag) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: vm.tagEvent.running ? null : () => _pick(context),
          icon: const Icon(Icons.sports_outlined, size: 18),
          label: const Text('Tag a game or event'),
        ),
      );
    }
    final event = vm.taggedEvent;
    final actions = vm.canTag
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Change event',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: vm.tagEvent.running ? null : () => _pick(context),
              ),
              IconButton(
                tooltip: 'Remove tag',
                icon: const Icon(Icons.close, size: 20),
                onPressed: vm.tagEvent.running
                    ? null
                    : () => vm.tagEvent.execute(null),
              ),
            ],
          )
        : null;
    if (event == null) {
      return Row(
        children: [
          Icon(Icons.event_busy_outlined, size: 20, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              vm.taggedMissing ? 'Tagged event not available' : 'Loading…',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
          ?actions,
        ],
      );
    }
    return Material(
      color: c.field,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: () => context.push(Routes.teamEvent(vm.teamId, event)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              DateBadge(date: event.startsAt, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eventLine(event),
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                    Text(
                      event.title.isEmpty ? event.type.label : event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  ],
                ),
              ),
              actions ?? Icon(Icons.chevron_right, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventPicker extends StatelessWidget {
  const _EventPicker({required this.viewModel, required this.current});

  final VideoViewModel viewModel;
  final String current;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final events = viewModel.taggableEvents;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Tag a game or event',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
              ),
              if (events.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Text(
                    'No events from the last year.',
                    style: TextStyle(color: c.muted),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final e in events)
                        ListTile(
                          leading: DateBadge(date: e.startsAt, size: 36),
                          title: Text(
                            e.title.isEmpty ? e.type.label : e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(eventLine(e)),
                          trailing: e.id == current
                              ? Icon(Icons.check, color: c.accent)
                              : null,
                          onTap: () => Navigator.of(context).pop(e.id),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Notes and clips pinned to times in the video, with a composer that
/// marks where they start and end.
class VideoNotes extends StatefulWidget {
  const VideoNotes({super.key, required this.viewModel, this.watchUrl});

  final VideoViewModel viewModel;

  /// A YouTube link, opened at a note's time where the player can't seek.
  final String? watchUrl;

  @override
  State<VideoNotes> createState() => _VideoNotesState();
}

class _VideoNotesState extends State<VideoNotes> {
  final _text = TextEditingController();

  VideoViewModel get vm => widget.viewModel;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    if (await vm.addNote(body) && mounted) _text.clear();
  }

  void _open(VideoComment note) {
    if (vm.canSeek) {
      vm.seekTo(note);
    } else if (widget.watchUrl case final url?) {
      launchUrl(
        Uri.parse('$url&t=${(note.atMs ?? 0) ~/ 1000}s'),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final notes = vm.notes;
    final compose = vm.canComment && vm.canSeek;
    if (notes.isEmpty && !compose) return const SizedBox.shrink();
    final start = vm.noteStartMs;
    final end = vm.noteEndMs;
    return SectionCard(
      title: notes.isEmpty ? 'Notes' : 'Notes · ${notes.length}',
      icon: Icons.bookmark_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notes.isEmpty)
            Text(
              'Pin a note to a moment in the video. Tap one to play from '
              'there.',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          for (final n in notes)
            _CommentRow(
              key: ValueKey('note-${n.id}'),
              comment: n,
              viewModel: vm,
              time: n.timeLabel,
              onTap: () => _open(n),
            ),
          if (compose) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 16),
                  label: Text(
                    start == null
                        ? 'Mark start'
                        : 'At ${VideoComment.formatTime(start)}',
                  ),
                  onPressed: vm.markStart,
                ),
                if (end == null)
                  ActionChip(
                    avatar: const Icon(Icons.content_cut, size: 16),
                    label: const Text('Mark end (clip)'),
                    onPressed: vm.markEnd,
                  )
                else
                  InputChip(
                    avatar: const Icon(Icons.content_cut, size: 16),
                    label: Text('To ${VideoComment.formatTime(end)}'),
                    onPressed: vm.markEnd,
                    onDeleted: vm.clearEnd,
                    deleteButtonTooltipMessage: 'No end',
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _Composer(
              controller: _text,
              hint: start == null
                  ? 'Add a note at the current time'
                  : 'Add a note at ${VideoComment.formatTime(start)}',
              busy: vm.addComment.running,
              onSend: _send,
            ),
          ],
        ],
      ),
    );
  }
}

/// The video's comment thread, oldest first, with a composer.
class VideoComments extends StatefulWidget {
  const VideoComments({super.key, required this.viewModel});

  final VideoViewModel viewModel;

  @override
  State<VideoComments> createState() => _VideoCommentsState();
}

class _VideoCommentsState extends State<VideoComments> {
  final _text = TextEditingController();

  VideoViewModel get vm => widget.viewModel;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    await vm.addComment.execute((body: body, atMs: null, endMs: null));
    if (mounted && vm.addComment.completed) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final comments = vm.comments;
    if (comments.isEmpty && !vm.canComment) return const SizedBox.shrink();
    return SectionCard(
      title: comments.isEmpty ? 'Comments' : 'Comments · ${comments.length}',
      icon: Icons.chat_bubble_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (comments.isEmpty)
            Text(
              'No comments yet.',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          for (final m in comments)
            _CommentRow(
              key: ValueKey('comment-${m.id}'),
              comment: m,
              viewModel: vm,
            ),
          if (vm.canComment) ...[
            const SizedBox(height: 10),
            _Composer(
              controller: _text,
              hint: 'Add a comment',
              busy: vm.addComment.running,
              onSend: _send,
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    super.key,
    required this.comment,
    required this.viewModel,
    this.time,
    this.onTap,
  });

  final VideoComment comment;
  final VideoViewModel viewModel;

  /// A note's time chip ("1:23", "1:23–1:40").
  final String? time;
  final VoidCallback? onTap;

  Future<void> _delete(BuildContext context) async {
    final what = comment.isNote ? 'note' : 'comment';
    if (await confirmDialog(
      context,
      title: 'Delete this $what?',
      message: 'It will be removed for everyone on the team.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      await viewModel.deleteComment.execute(comment.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final created = comment.createdAt;
    final byline = [
      comment.authorName.isEmpty ? 'Someone' : comment.authorName,
      if (created != null) timeAgo(created, DateTime.now()),
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (time case final t?) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      comment.isClip ? Icons.content_cut : Icons.play_arrow,
                      size: 14,
                      color: c.accentInk,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      t,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.accentInk,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment.body,
                    style: TextStyle(fontSize: 14, height: 1.35, color: c.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(byline, style: TextStyle(fontSize: 12, color: c.muted)),
                ],
              ),
            ),
            if (viewModel.canDelete(comment))
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline, size: 18, color: c.muted),
                onPressed: viewModel.deleteComment.running
                    ? null
                    : () => _delete(context),
              ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.hint,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final String hint;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: controller,
          maxLength: VideoComment.maxBody,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            isDense: true,
          ),
          onSubmitted: (_) => onSend(),
        ),
      ),
      const SizedBox(width: 4),
      IconButton.filled(
        tooltip: 'Post',
        icon: const Icon(Icons.send, size: 18),
        onPressed: busy ? null : onSend,
      ),
    ],
  );
}

/// "Game · Nov 1, 2026" for an event row.
String eventLine(TeamEvent e) =>
    '${e.type.label} · ${DateFormat.yMMMd().format(e.startsAt)}';
