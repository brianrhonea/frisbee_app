import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/chat.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/message_thread_viewmodel.dart';

/// Messages with a composer below, for a team room or a direct message.
/// Shows [readOnlyNotice] in place of the composer when the user can't post.
class MessageThreadView extends StatefulWidget {
  const MessageThreadView({
    super.key,
    required this.viewModel,
    this.emptyMessage = 'Say hello.',
    this.readOnlyNotice = 'You can read this conversation but not post in it.',
  });

  final MessageThreadViewModel viewModel;
  final String emptyMessage;
  final String readOnlyNotice;

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
    vm.deleteMessage,
    vm.saveAttachment,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
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

  Future<void> _delete(ChatMessage m) async {
    if (await confirmDialog(
      context,
      title: 'Delete message?',
      message: m.attachments.isEmpty
          ? 'It will be removed for everyone.'
          : 'It and its attachments will be removed for everyone.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      vm.deleteMessage.execute(m);
    }
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
            ),
          ),
          if (vm.canWrite)
            _Composer(
              viewModel: vm,
              controller: _text,
              focusNode: _focus,
              onSend: _send,
            )
          else
            _ReadOnlyBar(text: widget.readOnlyNotice),
        ],
      ),
    ),
  );
}

// Messages -----------------------------------------------------------------

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.viewModel,
    required this.onDelete,
    required this.emptyMessage,
  });

  final MessageThreadViewModel viewModel;
  final ValueChanged<ChatMessage> onDelete;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      itemCount: count,
      itemBuilder: (context, i) {
        if (i == messages.length) {
          return Center(
            child: TextButton(
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (newDay && m.createdAt != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _dayLabel(m.createdAt!),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
              ),
            _MessageBubble(
              message: m,
              mine: vm.isMine(m),
              showAuthor: !grouped,
              viewModel: vm,
              onDelete: vm.canDelete(m) ? () => onDelete(m) : null,
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
      0 => 'Today',
      1 => 'Yesterday',
      _ => DateFormat.yMMMEd().format(d),
    };
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.showAuthor,
    required this.viewModel,
    required this.onDelete,
  });

  final ChatMessage message;
  final bool mine;
  final bool showAuthor;
  final MessageThreadViewModel viewModel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final m = message;
    final time = m.createdAt;
    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: mine ? c.accentSoft : c.card,
        border: mine ? null : Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in m.attachments)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: a.isImage
                  ? _ImageAttachment(attachment: a, viewModel: viewModel)
                  : _FileAttachment(attachment: a, viewModel: viewModel),
            ),
          if (m.text.isNotEmpty)
            SelectableText(
              m.text,
              style: TextStyle(color: c.ink, fontSize: 15),
            ),
          const SizedBox(height: 2),
          Text(
            time == null ? 'Sending…' : DateFormat.jm().format(time),
            style: TextStyle(fontSize: 11, color: c.muted),
          ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: showAuthor ? 8 : 2),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (showAuthor && !mine)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text(
                m.authorName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.muted,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (mine && onDelete != null) _DeleteButton(onDelete: onDelete!),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: GestureDetector(onLongPress: onDelete, child: bubble),
                ),
              ),
              if (!mine && onDelete != null) _DeleteButton(onDelete: onDelete!),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Delete message',
    visualDensity: VisualDensity.compact,
    iconSize: 18,
    color: AppColors.of(context).muted,
    icon: const Icon(Icons.delete_outline),
    onPressed: onDelete,
  );
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
          null => const SizedBox(
            width: 220,
            height: 160,
            child: Center(child: CircularProgressIndicator()),
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

enum _AttachKind { photo, file }

class _Composer extends StatelessWidget {
  const _Composer({
    required this.viewModel,
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  final MessageThreadViewModel viewModel;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    return ListenableBuilder(
      listenable: Listenable.merge([vm.send, vm.pickFiles]),
      builder: (context, _) {
        final sending = vm.send.running;
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (vm.drafts.isNotEmpty)
                SizedBox(
                  height: 72,
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
              if (sending) const LinearProgressIndicator(minHeight: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (vm.canAttach)
                    PopupMenuButton<_AttachKind>(
                      tooltip: 'Attach',
                      enabled: !sending && !vm.pickFiles.running,
                      icon: const Icon(Icons.attach_file),
                      onSelected: (k) =>
                          vm.pickFiles.execute(k == _AttachKind.photo),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _AttachKind.photo,
                          child: ListTile(
                            leading: Icon(Icons.photo_outlined),
                            title: Text('Photo'),
                          ),
                        ),
                        PopupMenuItem(
                          value: _AttachKind.file,
                          child: ListTile(
                            leading: Icon(Icons.insert_drive_file_outlined),
                            title: Text('File'),
                          ),
                        ),
                      ],
                    ),
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
                        maxLines: 5,
                        maxLength: 4000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          counterText: '',
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    color: c.accent,
                    icon: const Icon(Icons.send),
                    onPressed: sending ? null : onSend,
                  ),
                ],
              ),
            ],
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
