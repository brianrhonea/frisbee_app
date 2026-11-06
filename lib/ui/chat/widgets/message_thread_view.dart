import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/chat.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/linkified_text.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/undo_snack_bar.dart';
import '../../videos/widgets/file_video_player.dart';
import '../view_models/message_thread_viewmodel.dart';
import '../../core/ui/skeleton.dart';

/// Messages with a composer below, for a team room or a direct message.
/// Shows [readOnlyNotice] in place of the composer when the user can't post.
class MessageThreadView extends StatefulWidget {
  const MessageThreadView({
    super.key,
    required this.viewModel,
    this.emptyMessage = 'Say hello.',
    this.readOnlyNotice = 'You can read this conversation but not post in it.',
    this.hintText = 'Message',
    this.footer,
    this.videoPlayer = fileVideoPlayer,
  });

  final MessageThreadViewModel viewModel;
  final String emptyMessage;
  final String readOnlyNotice;

  /// The composer's placeholder, e.g. "Message #general".
  final String hintText;

  /// Shown instead of the composer, e.g. a message request's Accept bar.
  final Widget? footer;

  /// Plays video attachments; tests swap in a stand-in.
  final FileVideoPlayerBuilder videoPlayer;

  @override
  State<MessageThreadView> createState() => _MessageThreadViewState();
}

class _MessageThreadViewState extends State<MessageThreadView> {
  MessageThreadViewModel get vm => widget.viewModel;
  final _text = TextEditingController();
  final _focus = FocusNode();

  late final List<Command<Object?>> _commands = [
    vm.send,
    vm.pickFiles,
    vm.takePhoto,
    vm.recordVideo,
    vm.deleteMessage,
    vm.saveAttachment,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
    _text.addListener(_onText);
  }

  String _lastText = '';

  void _onText() {
    // Selection changes notify too; only edits count as typing.
    if (_text.text == _lastText) return;
    _lastText = _text.text;
    vm.composerChanged(_text.text);
  }

  @override
  void dispose() {
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onCommand() {
    if (vm.send.completed) {
      vm.send.clearResult();
      _text.clear();
    }
    if (vm.saveAttachment.result case Ok(value: true)) {
      vm.saveAttachment.clearResult();
      showSnackBar(context, 'Saved.');
    }
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  void _send() {
    if (!vm.send.running) vm.send.execute(_text.text);
  }

  void _delete(ChatMessage m) {
    vm.removals.remove(m);
    showUndoSnackBar(
      context,
      message: 'Message deleted',
      onUndo: () => vm.removals.undo(m),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => ConstrainedContent(
      maxWidth: 900,
      child: Column(
        children: [
          Expanded(
            child: _MessageList(
              viewModel: vm,
              onDelete: _delete,
              emptyMessage: widget.emptyMessage,
              videoPlayer: widget.videoPlayer,
            ),
          ),
          if (vm.showsTyping) _TypingIndicator(label: vm.typingLabel),
          if (widget.footer case final footer?)
            footer
          else if (vm.canWrite)
            _Composer(
              viewModel: vm,
              controller: _text,
              focusNode: _focus,
              onSend: _send,
              hintText: widget.hintText,
            )
          else
            _ReadOnlyBar(text: widget.readOnlyNotice),
        ],
      ),
    ),
  );
}

/// "Avery is typing…" just above the composer; keeps its height when
/// nobody is, so the messages don't jump.
class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      height: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: label == null
                ? const SizedBox.shrink()
                : Text(
                    label!,
                    key: ValueKey(label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: c.muted,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// Messages -----------------------------------------------------------------

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.viewModel,
    required this.onDelete,
    required this.emptyMessage,
    required this.videoPlayer,
  });

  final MessageThreadViewModel viewModel;
  final ValueChanged<ChatMessage> onDelete;
  final String emptyMessage;
  final FileVideoPlayerBuilder videoPlayer;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    if (!vm.messagesLoaded) return const LoadingView();
    final messages = vm.messages;
    if (messages.isEmpty) {
      return vm.messageError != null
          ? ErrorView(error: vm.messageError)
          : EmptyView(
              icon: Icons.chat_bubble_outline,
              title: 'No messages yet',
              message: vm.canWrite ? emptyMessage : null,
            );
    }
    // Newest at the bottom; a reversed list starts scrolled there.
    final count = messages.length + (vm.hasMore ? 1 : 0);
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      itemCount: count,
      itemBuilder: (context, i) {
        if (i == messages.length) {
          // Scrolled to the top: fetch the page above (one page of reads).
          if (vm.autoLoadMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) => vm.loadMore());
          }
          return Center(
            child: vm.loadingMore
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: vm.loadMore,
                    child: const Text('Load earlier messages'),
                  ),
          );
        }
        final index = messages.length - 1 - i;
        final m = messages[index];
        final prev = index > 0 ? messages[index - 1] : null;
        final newDay = prev == null || !_sameDay(prev.createdAt, m.createdAt);
        final grouped =
            !newDay &&
            prev.authorId == m.authorId &&
            _minutesApart(prev.createdAt, m.createdAt) < 5;
        final color = vm.nameColorOf(m.authorId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (newDay && m.createdAt != null)
              _DayDivider(label: _dayLabel(m.createdAt!)),
            _MessageRow(
              key: ValueKey(m.id),
              message: m,
              showAuthor: !grouped,
              nameColor: color == null ? null : Color(color),
              viewModel: vm,
              onDelete: vm.canDelete(m) ? () => onDelete(m) : null,
              videoPlayer: videoPlayer,
            ),
            if (vm.receiptFor(m) case final receipt?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                child: Text(
                  receipt,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static bool _sameDay(DateTime? a, DateTime? b) =>
      a == null || b == null || DateUtils.isSameDay(a, b);

  static int _minutesApart(DateTime? a, DateTime? b) =>
      a == null || b == null ? 0 : b.difference(a).inMinutes.abs();

  static String _dayLabel(DateTime d) {
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.dateOnly(d);
    return switch (today.difference(day).inDays) {
      0 => 'Today, ${DateFormat.MMMMd().format(d)}',
      1 => 'Yesterday, ${DateFormat.MMMMd().format(d)}',
      _ => DateFormat.yMMMEd().format(d),
    };
  }
}

/// One message, Discord style: everyone's on the left. The first of a run
/// shows the author's avatar, name and time; the rest of the run sits
/// under it, with the time in the gutter on hover.
class _MessageRow extends StatefulWidget {
  const _MessageRow({
    super.key,
    required this.message,
    required this.showAuthor,
    required this.nameColor,
    required this.viewModel,
    required this.onDelete,
    required this.videoPlayer,
  });

  final FileVideoPlayerBuilder videoPlayer;

  final ChatMessage message;
  final bool showAuthor;
  final Color? nameColor;
  final MessageThreadViewModel viewModel;
  final VoidCallback? onDelete;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow> {
  bool _hover = false;

  static const _gutter = 56.0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final m = widget.message;
    final time = m.createdAt;
    final onDelete = widget.onDelete;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showAuthor)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                Text(
                  m.authorName.isEmpty ? 'Member' : m.authorName,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: widget.nameColor ?? c.ink,
                  ),
                ),
                if (widget.viewModel.usernameOf(m.authorId) case final handle?)
                  Text(
                    '@$handle',
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                Text(
                  time == null ? 'Sending…' : _stamp(time),
                  style: TextStyle(fontSize: 11.5, color: c.muted),
                ),
              ],
            ),
          ),
        if (m.text.isNotEmpty)
          LinkifiedText(
            m.text,
            style: TextStyle(
              color: time == null ? c.muted : c.ink,
              fontSize: 14.5,
              height: 1.375,
            ),
          ),
        for (final a in m.attachments)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: a.isImage
                ? _ImageAttachment(attachment: a, viewModel: widget.viewModel)
                : a.isVideo
                ? _VideoAttachment(
                    attachment: a,
                    viewModel: widget.viewModel,
                    player: widget.videoPlayer,
                  )
                : _FileAttachment(attachment: a, viewModel: widget.viewModel),
          ),
      ],
    );
    final gutter = SizedBox(
      width: _gutter,
      child: widget.showAuthor
          ? Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, top: 2),
                child: PersonAvatar(name: m.authorName, radius: 20),
              ),
            )
          : _hover && time != null
          ? Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Text(
                DateFormat.jm().format(time),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: c.muted),
              ),
            )
          : null,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onDelete,
        child: Padding(
          padding: EdgeInsets.only(top: widget.showAuthor ? 14 : 0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                color: _hover ? c.ink.withValues(alpha: 0.04) : null,
                padding: const EdgeInsets.fromLTRB(0, 2, 16, 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    gutter,
                    Expanded(child: body),
                  ],
                ),
              ),
              if (_hover && onDelete != null)
                Positioned(
                  right: 16,
                  top: -16,
                  child: _HoverActions(onDelete: onDelete),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Today at 3:45 PM", "Yesterday at 9:02 AM", else "10/14/2026 3:45 PM".
  static String _stamp(DateTime d) {
    final today = DateUtils.dateOnly(DateTime.now());
    final time = DateFormat.jm().format(d);
    return switch (today.difference(DateUtils.dateOnly(d)).inDays) {
      0 => 'Today at $time',
      1 => 'Yesterday at $time',
      _ => '${DateFormat.yMd().format(d)} $time',
    };
  }
}

/// A rule across the list with the day in the middle.
class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.border, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ),
          Expanded(child: Divider(color: c.border, height: 1)),
        ],
      ),
    );
  }
}

/// The little toolbar that floats over a hovered message.
class _HoverActions extends StatelessWidget {
  const _HoverActions({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: c.card,
      elevation: 2,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.border),
      ),
      child: IconButton(
        tooltip: 'Delete message',
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        color: Colors.red.shade400,
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}

class _ImageAttachment extends StatefulWidget {
  const _ImageAttachment({required this.attachment, required this.viewModel});

  final ChatAttachment attachment;
  final MessageThreadViewModel viewModel;

  @override
  State<_ImageAttachment> createState() => _ImageAttachmentState();
}

class _ImageAttachmentState extends State<_ImageAttachment> {
  late var _data = widget.viewModel.attachmentData(widget.attachment);

  void _retry() => setState(
    () => _data = widget.viewModel.attachmentData(widget.attachment),
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final a = widget.attachment;
    return FutureBuilder(
      future: _data,
      builder: (context, snap) {
        final Widget child = switch (snap.data) {
          null => ClipRRect(
            borderRadius: BorderRadius.circular(controlRadius),
            child: const SkeletonImage(width: 220, height: 160),
          ),
          Error() => SizedBox(
            width: 220,
            height: 80,
            child: TextButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.broken_image_outlined),
              label: const Text("Couldn't load photo. Retry"),
            ),
          ),
          Ok(:final value) => InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => _PhotoDialog(
                bytes: value,
                name: a.name,
                onSave: () => widget.viewModel.saveAttachment.execute(a),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
              child: Image.memory(
                value,
                fit: BoxFit.contain,
                semanticLabel: a.name,
                frameBuilder: fadeInImageFrame,
                errorBuilder: (_, _, _) =>
                    _FileAttachment(attachment: a, viewModel: widget.viewModel),
              ),
            ),
          ),
        };
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ColoredBox(color: c.background, child: child),
        );
      },
    );
  }
}

class _PhotoDialog extends StatelessWidget {
  const _PhotoDialog({
    required this.bytes,
    required this.name,
    required this.onSave,
  });

  final Uint8List bytes;
  final String name;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Dialog(
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: InteractiveViewer(child: Image.memory(bytes))),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              TextButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Save'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FileAttachment extends StatelessWidget {
  const _FileAttachment({required this.attachment, required this.viewModel});

  final ChatAttachment attachment;
  final MessageThreadViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final a = attachment;
    return Material(
      color: c.background,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => viewModel.saveAttachment.execute(a),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_fileIcon(a.contentType), color: c.accent),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      formatFileSize(a.size),
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.download_outlined, size: 20, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A video: a play card that opens the player. Videos stream from a
/// download URL rather than loading into memory like photos.
class _VideoAttachment extends StatelessWidget {
  const _VideoAttachment({
    required this.attachment,
    required this.viewModel,
    required this.player,
  });

  final ChatAttachment attachment;
  final MessageThreadViewModel viewModel;
  final FileVideoPlayerBuilder player;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Material(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => _VideoDialog(
                  attachment: a,
                  viewModel: viewModel,
                  player: player,
                ),
              ),
              child: Stack(
                children: [
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      size: 52,
                      color: Colors.white,
                      semanticLabel: 'Play video',
                    ),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 8,
                    child: Text(
                      'Video · ${formatFileSize(a.size)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoDialog extends StatefulWidget {
  const _VideoDialog({
    required this.attachment,
    required this.viewModel,
    required this.player,
  });

  final ChatAttachment attachment;
  final MessageThreadViewModel viewModel;
  final FileVideoPlayerBuilder player;

  @override
  State<_VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<_VideoDialog> {
  late var _url = widget.viewModel.videoUrl(widget.attachment);

  @override
  Widget build(BuildContext context) => Dialog(
    clipBehavior: Clip.antiAlias,
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FutureBuilder(
            future: _url,
            builder: (context, snap) => switch (snap.data) {
              null => const AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              Ok(:final value) => widget.player(value),
              Error(:final error) => AspectRatio(
                aspectRatio: 16 / 9,
                child: ErrorView(
                  error: error,
                  onRetry: () => setState(
                    () => _url = widget.viewModel.videoUrl(widget.attachment),
                  ),
                ),
              ),
            },
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () =>
                    widget.viewModel.saveAttachment.execute(widget.attachment),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Save'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

IconData _fileIcon(String contentType) => switch (contentType) {
  'application/pdf' => Icons.picture_as_pdf_outlined,
  final t when t.startsWith('image/') => Icons.image_outlined,
  final t when t.startsWith('video/') => Icons.movie_outlined,
  final t when t.startsWith('text/') => Icons.description_outlined,
  _ => Icons.insert_drive_file_outlined,
};

// Composer -----------------------------------------------------------------

class _ReadOnlyBar extends StatelessWidget {
  const _ReadOnlyBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.visibility_outlined, size: 18, color: c.muted),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: c.muted)),
        ],
      ),
    );
  }
}

enum _AttachKind { camera, video, photo, file }

class _Composer extends StatelessWidget {
  const _Composer({
    required this.viewModel,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.hintText,
  });

  final MessageThreadViewModel viewModel;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    return ListenableBuilder(
      listenable: Listenable.merge([
        vm.send,
        vm.pickFiles,
        vm.takePhoto,
        vm.recordVideo,
      ]),
      builder: (context, _) {
        final sending = vm.send.running;
        final wide = !ScreenSize.of(context).isMobile;
        final attach = vm.canAttach
            ? PopupMenuButton<_AttachKind>(
                tooltip: 'Upload a photo, video or file',
                enabled:
                    !sending &&
                    !vm.pickFiles.running &&
                    !vm.recordVideo.running,
                icon: Icon(Icons.add_circle, color: c.muted),
                onSelected: (k) => switch (k) {
                  _AttachKind.camera => vm.takePhoto.execute(),
                  _AttachKind.video => vm.recordVideo.execute(),
                  _AttachKind.photo => vm.pickFiles.execute(true),
                  _AttachKind.file => vm.pickFiles.execute(false),
                },
                itemBuilder: (_) => [
                  if (vm.canUseCamera)
                    const PopupMenuItem(
                      value: _AttachKind.camera,
                      child: ListTile(
                        leading: Icon(Icons.photo_camera_outlined),
                        title: Text('Take photo'),
                      ),
                    ),
                  if (vm.canUseCamera)
                    const PopupMenuItem(
                      value: _AttachKind.video,
                      child: ListTile(
                        leading: Icon(Icons.videocam_outlined),
                        title: Text('Record video'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: _AttachKind.photo,
                    child: ListTile(
                      leading: Icon(Icons.photo_outlined),
                      title: Text('Photo'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _AttachKind.file,
                    child: ListTile(
                      leading: Icon(Icons.insert_drive_file_outlined),
                      title: Text('File'),
                    ),
                  ),
                ],
              )
            : const SizedBox(width: 12);
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, wide ? 20 : 10),
          child: Container(
            decoration: BoxDecoration(
              color: c.background,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (vm.drafts.isNotEmpty)
                  Container(
                    height: 88,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final d in vm.drafts)
                          _DraftChip(
                            draft: d,
                            onRemove: sending ? null : () => vm.removeDraft(d),
                          ),
                      ],
                    ),
                  ),
                if (vm.drafts.isNotEmpty) Divider(height: 1, color: c.border),
                if (sending) const LinearProgressIndicator(minHeight: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    attach,
                    Expanded(
                      child: Focus(
                        // Enter sends; Shift+Enter adds a line.
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.enter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            onSend();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          enabled: !sending,
                          minLines: 1,
                          maxLines: 8,
                          maxLength: 4000,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(fontSize: 14.5, color: c.ink),
                          decoration: InputDecoration(
                            hintText: hintText,
                            counterText: '',
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Always shown: touch screens of any size (tablets
                    // included) may have no Enter key to send with.
                    ValueListenableBuilder(
                      valueListenable: controller,
                      builder: (context, value, _) {
                        final empty =
                            value.text.trim().isEmpty && vm.drafts.isEmpty;
                        return IconButton(
                          tooltip: 'Send',
                          color: c.accent,
                          icon: const Icon(Icons.send_rounded, size: 22),
                          onPressed: sending || empty ? null : onSend,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DraftChip extends StatelessWidget {
  const _DraftChip({required this.draft, required this.onRemove});

  final NewAttachment draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: Container(
        width: draft.isImage ? 64 : 180,
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (draft.isImage)
              Image.memory(
                draft.bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 28, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      draft.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      formatFileSize(draft.size),
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'Remove ${draft.name}',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                style: IconButton.styleFrom(
                  backgroundColor: c.card.withValues(alpha: 0.8),
                ),
                icon: const Icon(Icons.close),
                onPressed: onRemove,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
