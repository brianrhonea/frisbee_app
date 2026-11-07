import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/chat.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../../utils/on_screen.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/linkified_text.dart';
import '../../core/ui/scroll_to_top.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/undo_snack_bar.dart';
import '../../core/ui/user_avatar.dart';
import '../../videos/widgets/file_video_player.dart';
import '../view_models/message_thread_viewmodel.dart';
import '../../core/ui/skeleton.dart';

/// Messages with a composer below, for a team room or a direct message.
/// Shows [readOnlyNotice] in place of the composer when the user can't post.
///
/// Long-press a message (right-click, or hover, with a mouse) to react,
/// reply, copy or delete it; swipe one to the right to reply.
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

  /// Starts with whatever was left unsent last time.
  late final _text = TextEditingController(text: vm.draft);
  final _focus = FocusNode();
  final _undo = UndoHistoryController();
  final _scroll = ScrollController();

  late final List<Command<Object?>> _commands = [
    vm.send,
    vm.pickFiles,
    vm.takePhoto,
    vm.recordVideo,
    vm.deleteMessage,
    vm.saveAttachment,
    vm.react,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
    _lastText = _text.text;
    _text.addListener(_onText);
    if (vm.noticeKey case final key?) {
      _unregister = OnScreen.register(key, () => mounted && _visible);
    }
  }

  void Function()? _unregister;

  /// On top of the navigator, in the tab that's showing.
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (visible && !_visible) vm.shown();
    _visible = visible;
  }

  late String _lastText;

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
    _undo.dispose();
    _scroll.dispose();
    _unregister?.call();
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

  void _reply(ChatMessage m) {
    vm.replyTo(m);
    _focus.requestFocus();
  }

  void _copy(ChatMessage m) {
    Clipboard.setData(ClipboardData(text: m.text));
    showSnackBar(context, 'Copied.');
  }

  void _react(ChatMessage m, String emoji) => vm.react.execute((m, emoji));

  /// The author's profile, over the conversation so back returns here.
  void _openProfile(String uid) {
    if (uid.isEmpty || !vm.opensProfiles) return;
    context.push(Routes.personOver(uid));
  }

  bool _canReply(ChatMessage m) =>
      vm.canWrite && vm.canReact && m.createdAt != null;

  Future<void> _actions(ChatMessage m) async {
    HapticFeedback.mediumImpact();
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      builder: (_) => _MessageActionsSheet(
        message: m,
        mine: m.reactionOf(vm.uid),
        canReact: vm.canReact && m.createdAt != null,
        canReply: _canReply(m),
        canDelete: vm.canDelete(m),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _React(:final emoji):
        _react(m, emoji);
      case _Reply():
        _reply(m);
      case _Copy():
        _copy(m);
      case _Delete():
        _delete(m);
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
            child: ScrollToTop(
              controller: _scroll,
              reverse: true,
              child: _MessageList(
                viewModel: vm,
                controller: _scroll,
                emptyMessage: widget.emptyMessage,
                videoPlayer: widget.videoPlayer,
                actions: _RowActions(
                  onActions: _actions,
                  onReply: (m) => _canReply(m) ? _reply(m) : null,
                  onReact: vm.canReact ? _react : null,
                  onDelete: _delete,
                  onProfile: _openProfile,
                ),
              ),
            ),
          ),
          if (vm.showsTyping) _TypingIndicator(label: vm.typingLabel),
          if (widget.footer case final footer?)
            footer
          else if (vm.canWrite)
            _Composer(
              viewModel: vm,
              controller: _text,
              undoController: _undo,
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

/// What a message's long-press sheet picked.
sealed class _MessageAction {
  const _MessageAction();
}

class _React extends _MessageAction {
  const _React(this.emoji);
  final String emoji;
}

class _Reply extends _MessageAction {
  const _Reply();
}

class _Copy extends _MessageAction {
  const _Copy();
}

class _Delete extends _MessageAction {
  const _Delete();
}

/// What a message row can do, handed down from the view.
class _RowActions {
  const _RowActions({
    required this.onActions,
    required this.onReply,
    required this.onReact,
    required this.onDelete,
    required this.onProfile,
  });

  /// The long-press sheet.
  final ValueChanged<ChatMessage> onActions;

  /// Starts a reply (ignored where replies aren't allowed).
  final ValueChanged<ChatMessage> onReply;

  /// Toggles a reaction; null where reactions aren't offered.
  final void Function(ChatMessage, String)? onReact;
  final ValueChanged<ChatMessage> onDelete;
  final ValueChanged<String> onProfile;
}

/// Long-press on a message: a row of quick reactions, then Reply, Copy
/// and Delete.
class _MessageActionsSheet extends StatelessWidget {
  const _MessageActionsSheet({
    required this.message,
    required this.mine,
    required this.canReact,
    required this.canReply,
    required this.canDelete,
  });

  final ChatMessage message;

  /// The user's current reaction, highlighted.
  final String? mine;
  final bool canReact;
  final bool canReply;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    void pick(_MessageAction a) => Navigator.pop(context, a);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canReact)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(
                alignment: WrapAlignment.spaceEvenly,
                children: [
                  for (final e in quickReactions)
                    Semantics(
                      button: true,
                      selected: e == mine,
                      label: 'React $e',
                      child: InkResponse(
                        radius: 26,
                        onTap: () => pick(_React(e)),
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: e == mine ? c.accentSoft : null,
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 26)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (canReply)
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () => pick(const _Reply()),
            ),
          if (message.text.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy text'),
              onTap: () => pick(const _Copy()),
            ),
          if (canDelete)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
              title: Text(
                'Delete message',
                style: TextStyle(color: Colors.red.shade400),
              ),
              onTap: () => pick(const _Delete()),
            ),
        ],
      ),
    );
  }
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
    required this.controller,
    required this.emptyMessage,
    required this.videoPlayer,
    required this.actions,
  });

  final MessageThreadViewModel viewModel;
  final ScrollController controller;
  final String emptyMessage;
  final FileVideoPlayerBuilder videoPlayer;
  final _RowActions actions;

  /// A gap this long between two messages shows the time between them in
  /// bubbles, as a phone's messages app does.
  static const _timeGap = Duration(minutes: 15);

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
    final bubbles = vm.style == ThreadStyle.bubbles;
    // Newest at the bottom; a reversed list starts scrolled there.
    final count = messages.length + (vm.hasMore ? 1 : 0);
    return ListView.builder(
      controller: controller,
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
        final next = index + 1 < messages.length ? messages[index + 1] : null;
        final newDay = prev == null || !_sameDay(prev.createdAt, m.createdAt);
        final gap = !newDay && _apart(prev.createdAt, m.createdAt) >= _timeGap;
        final grouped =
            !newDay &&
            !gap &&
            prev.authorId == m.authorId &&
            _apart(prev.createdAt, m.createdAt) < const Duration(minutes: 5);
        // The last of a run: the next is someone else's, or a while later.
        final endsRun =
            next == null ||
            next.authorId != m.authorId ||
            !_sameDay(m.createdAt, next.createdAt) ||
            _apart(m.createdAt, next.createdAt) >= const Duration(minutes: 5);
        final color = vm.nameColorOf(m.authorId);
        final onDelete = vm.canDelete(m) ? () => actions.onDelete(m) : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (newDay && m.createdAt != null)
              _DayDivider(label: _dayLabel(m.createdAt!))
            else if (bubbles && gap && m.createdAt != null)
              _TimeLabel(time: m.createdAt!),
            _SwipeToReply(
              key: ValueKey(m.id),
              enabled: vm.canWrite && vm.canReact && m.createdAt != null,
              onReply: () => actions.onReply(m),
              child: bubbles
                  ? _BubbleRow(
                      message: m,
                      mine: vm.isMine(m),
                      startsRun: !grouped,
                      endsRun: endsRun,
                      viewModel: vm,
                      actions: actions,
                      onDelete: onDelete,
                      videoPlayer: videoPlayer,
                    )
                  : _FeedRow(
                      message: m,
                      showAuthor: !grouped,
                      nameColor: color == null ? null : Color(color),
                      viewModel: vm,
                      actions: actions,
                      onDelete: onDelete,
                      videoPlayer: videoPlayer,
                    ),
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

  static Duration _apart(DateTime? a, DateTime? b) =>
      a == null || b == null ? Duration.zero : b.difference(a).abs();

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

/// Drag a message to the right to reply to it, as in most messaging apps.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    super.key,
    required this.enabled,
    required this.onReply,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const _trigger = 56.0;
  static const _max = 80.0;
  double _dx = 0;
  bool _armed = false;

  void _update(DragUpdateDetails d) {
    final dx = (_dx + d.delta.dx).clamp(0.0, _max);
    final armed = dx >= _trigger;
    if (armed && !_armed) HapticFeedback.selectionClick();
    setState(() {
      _dx = dx;
      _armed = armed;
    });
  }

  void _end([DragEndDetails? _]) {
    if (_armed) widget.onReply();
    setState(() {
      _dx = 0;
      _armed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final c = AppColors.of(context);
    return GestureDetector(
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: _end,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (_dx > 0)
            Positioned(
              left: 12,
              child: Opacity(
                opacity: (_dx / _trigger).clamp(0.0, 1.0),
                child: Icon(
                  Icons.reply,
                  size: 22,
                  color: _armed ? c.accent : c.muted,
                ),
              ),
            ),
          AnimatedContainer(
            duration: _dx == 0
                ? const Duration(milliseconds: 180)
                : Duration.zero,
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// A message's text, with tappable links. Selectable with a mouse; on a
/// touch screen a long-press opens the message's actions instead (Copy
/// is one).
class _MessageText extends StatelessWidget {
  const _MessageText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) =>
      LinkifiedText(text, style: style, selectable: _usesMouse(context));
}

/// Whether the device is driven by a pointer rather than touch.
bool _usesMouse(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.windows ||
  TargetPlatform.macOS ||
  TargetPlatform.linux => true,
  _ => false,
};

/// The quote above a reply: who it answers and what they said.
class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.reply, required this.onBubble});

  final MessageReply reply;

  /// In a colored bubble (the user's own), so it's drawn to suit.
  final bool onBubble;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final name = reply.authorName.isEmpty ? 'Someone' : reply.authorName;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: c.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: c.accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.reply, size: 13, color: c.muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ),
          if (reply.text.isNotEmpty)
            Text(
              reply.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
        ],
      ),
    );
  }
}

/// The reactions under a message: each emoji and how many gave it. Tap
/// one to give (or take back) the same.
class _ReactionChips extends StatelessWidget {
  const _ReactionChips({
    required this.message,
    required this.uid,
    required this.onReact,
  });

  final ChatMessage message;
  final String uid;
  final void Function(ChatMessage, String)? onReact;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final counts = message.reactionCounts(uid);
    if (counts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final r in counts)
            Semantics(
              button: onReact != null,
              selected: r.mine,
              label: '${r.emoji} ${r.count}',
              excludeSemantics: true,
              child: Material(
                color: r.mine ? c.accentSoft : c.card,
                shape: StadiumBorder(
                  side: BorderSide(color: r.mine ? c.accent : c.border),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onReact == null
                      ? null
                      : () => onReact!(message, r.emoji),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    child: Text(
                      r.count > 1 ? '${r.emoji} ${r.count}' : r.emoji,
                      style: TextStyle(fontSize: 13, color: c.ink),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A message's attachments, one under another.
class _Attachments extends StatelessWidget {
  const _Attachments({
    required this.message,
    required this.viewModel,
    required this.videoPlayer,
  });

  final ChatMessage message;
  final MessageThreadViewModel viewModel;
  final FileVideoPlayerBuilder videoPlayer;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final a in message.attachments)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: a.isImage
              ? _ImageAttachment(attachment: a, viewModel: viewModel)
              : a.isVideo
              ? _VideoAttachment(
                  attachment: a,
                  viewModel: viewModel,
                  player: videoPlayer,
                )
              : _FileAttachment(attachment: a, viewModel: viewModel),
        ),
    ],
  );
}

/// Hover, long-press and right-click handling shared by both row styles.
///
/// With a mouse (Windows, macOS, Linux) every message carries a small
/// react / reply strip at its end, faint until hovered; [builder] places
/// it. On touch screens there's none: tap and hold opens the actions.
class _Hoverable extends StatefulWidget {
  const _Hoverable({
    required this.message,
    required this.actions,
    required this.canReply,
    required this.myReaction,
    required this.builder,
  });

  final ChatMessage message;
  final _RowActions actions;
  final bool canReply;

  /// The user's reaction to it, highlighted in the picker.
  final String? myReaction;

  /// Builds the row; `strip` is null on touch screens, or while sending.
  final Widget Function(BuildContext context, bool hover, Widget? strip)
  builder;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hover = false;

  /// Kept lit while the emoji picker is open.
  bool _picking = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final a = widget.actions;
    final react = a.onReact;
    final strip =
        _usesMouse(context) &&
            m.createdAt != null &&
            (react != null || widget.canReply)
        ? _MessageStrip(
            lit: _hover || _picking,
            current: widget.myReaction,
            onReact: react == null ? null : (e) => react(m, e),
            onReply: widget.canReply ? () => a.onReply(m) : null,
            onPicking: (open) => setState(() => _picking = open),
          )
        : null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => a.onActions(m),
        onSecondaryTap: () => a.onActions(m),
        child: widget.builder(context, _hover, strip),
      ),
    );
  }
}

/// One message, Discord style: everyone's on the left. The first of a run
/// shows the author's photo, name and time (tap either for their
/// profile); the rest of the run sits under it, with the time in the
/// gutter on hover.
class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.message,
    required this.showAuthor,
    required this.nameColor,
    required this.viewModel,
    required this.actions,
    required this.onDelete,
    required this.videoPlayer,
  });

  final ChatMessage message;
  final bool showAuthor;
  final Color? nameColor;
  final MessageThreadViewModel viewModel;
  final _RowActions actions;
  final VoidCallback? onDelete;
  final FileVideoPlayerBuilder videoPlayer;

  /// Photo size, and the gutter it sits in: 16 in, the photo, 12 out.
  static const _avatar = 18.0;
  static const _gutter = 16.0 + _avatar * 2 + 12;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final m = message;
    final time = m.createdAt;
    final vm = viewModel;
    final name = m.authorName.isEmpty ? 'Member' : m.authorName;
    final canOpen = vm.opensProfiles && m.authorId.isNotEmpty;
    return _Hoverable(
      message: m,
      actions: actions,
      canReply: vm.canWrite && vm.canReact,
      myReaction: m.reactionOf(vm.uid),
      builder: (context, hover, strip) {
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.replyTo case final r?) _ReplyQuote(reply: r, onBubble: false),
            if (showAuthor)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  children: [
                    Semantics(
                      button: canOpen,
                      label: canOpen ? "$name's profile" : null,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: canOpen
                            ? () => actions.onProfile(m.authorId)
                            : null,
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: nameColor ?? c.ink,
                          ),
                        ),
                      ),
                    ),
                    if (vm.usernameOf(m.authorId) case final handle?)
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
              _MessageText(
                text: m.text,
                style: TextStyle(
                  color: time == null ? c.muted : c.ink,
                  fontSize: 14.5,
                  height: 1.375,
                ),
              ),
            _Attachments(message: m, viewModel: vm, videoPlayer: videoPlayer),
            _ReactionChips(message: m, uid: vm.uid, onReact: actions.onReact),
          ],
        );
        final gutter = SizedBox(
          width: _gutter,
          child: showAuthor
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    // Lines the photo's middle up between the name and
                    // the first line under it.
                    padding: EdgeInsets.only(
                      left: 16,
                      top: m.replyTo == null ? 2 : 46,
                    ),
                    child: GestureDetector(
                      onTap: canOpen
                          ? () => actions.onProfile(m.authorId)
                          : null,
                      child: UserAvatar(
                        uid: m.authorId,
                        name: m.authorName,
                        radius: _avatar,
                      ),
                    ),
                  ),
                )
              : hover && time != null
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
        return Padding(
          padding: EdgeInsets.only(top: showAuthor ? 14 : 0),
          child: Container(
            color: hover ? c.ink.withValues(alpha: 0.04) : null,
            padding: const EdgeInsets.fromLTRB(0, 2, 16, 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                gutter,
                Expanded(child: body),
                if (strip != null)
                  Padding(
                    // Level with the message's first line.
                    padding: EdgeInsets.only(
                      left: 8,
                      top: showAuthor && m.replyTo == null ? 20 : 0,
                    ),
                    child: strip,
                  ),
              ],
            ),
          ),
        );
      },
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

/// One message as a bubble, like a phone's messages app: the user's on
/// the right in the accent color, the other person's on the left. A run
/// of messages stacks closely, its corners squared where they meet.
class _BubbleRow extends StatelessWidget {
  const _BubbleRow({
    required this.message,
    required this.mine,
    required this.startsRun,
    required this.endsRun,
    required this.viewModel,
    required this.actions,
    required this.onDelete,
    required this.videoPlayer,
  });

  final ChatMessage message;
  final bool mine;
  final bool startsRun;
  final bool endsRun;
  final MessageThreadViewModel viewModel;
  final _RowActions actions;
  final VoidCallback? onDelete;
  final FileVideoPlayerBuilder videoPlayer;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final m = message;
    final vm = viewModel;
    final sending = m.createdAt == null;
    final fill = mine ? c.accent : c.card;
    final ink = mine ? c.onAccent : c.ink;
    const big = Radius.circular(18);
    const small = Radius.circular(5);
    // Square the corners on the side the run continues.
    final radius = BorderRadius.only(
      topLeft: !mine && !startsRun ? small : big,
      bottomLeft: !mine && !endsRun ? small : big,
      topRight: mine && !startsRun ? small : big,
      bottomRight: mine && !endsRun ? small : big,
    );
    return _Hoverable(
      message: m,
      actions: actions,
      canReply: vm.canWrite && vm.canReact,
      myReaction: m.reactionOf(vm.uid),
      builder: (context, hover, strip) => Padding(
        padding: EdgeInsets.fromLTRB(16, startsRun ? 8 : 2, 16, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bubble = ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(constraints.maxWidth * 0.78, 520),
              ),
              child: Column(
                crossAxisAlignment: mine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (m.replyTo case final r?)
                    _ReplyQuote(reply: r, onBubble: false),
                  if (m.text.isNotEmpty)
                    Tooltip(
                      message: sending
                          ? 'Sending…'
                          : DateFormat.jm().format(m.createdAt!),
                      waitDuration: const Duration(milliseconds: 600),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: fill,
                          borderRadius: radius,
                          border: mine ? null : Border.all(color: c.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          child: _MessageText(
                            text: m.text,
                            style: TextStyle(
                              color: sending ? ink.withValues(alpha: 0.7) : ink,
                              fontSize: 15,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  _Attachments(
                    message: m,
                    viewModel: vm,
                    videoPlayer: videoPlayer,
                  ),
                  _ReactionChips(
                    message: m,
                    uid: vm.uid,
                    onReact: actions.onReact,
                  ),
                ],
              ),
            );
            // The strip sits at the bubble's end, toward the middle:
            // after theirs, before the user's own.
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: strip == null
                  ? bubble
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (mine) ...[strip, const SizedBox(width: 6)],
                        Flexible(child: bubble),
                        if (!mine) ...[const SizedBox(width: 6), strip],
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// The time, centered, over a message that came a while after the last.
class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.time});

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Text(
        DateFormat.jm().format(time),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: c.muted,
        ),
      ),
    );
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

/// React and Reply, at the end of a message when there's a mouse. Faint
/// until the message is hovered ([lit]); React opens the emoji in a row.
class _MessageStrip extends StatefulWidget {
  const _MessageStrip({
    required this.lit,
    required this.current,
    required this.onReact,
    required this.onReply,
    required this.onPicking,
  });

  final bool lit;
  final String? current;
  final ValueChanged<String>? onReact;
  final VoidCallback? onReply;
  final ValueChanged<bool> onPicking;

  @override
  State<_MessageStrip> createState() => _MessageStripState();
}

class _MessageStripState extends State<_MessageStrip> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final react = widget.onReact;
    final reply = widget.onReply;
    return AnimatedOpacity(
      opacity: widget.lit ? 1 : 0.35,
      duration: const Duration(milliseconds: 120),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (react != null)
            MenuAnchor(
              controller: _menu,
              onOpen: () => widget.onPicking(true),
              onClose: () => widget.onPicking(false),
              alignmentOffset: const Offset(0, 4),
              style: MenuStyle(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 4),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: BorderSide(color: c.border),
                  ),
                ),
              ),
              menuChildren: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in quickReactions)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: InkResponse(
                          radius: 20,
                          onTap: () {
                            _menu.close();
                            react(e);
                          },
                          child: Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: e == widget.current
                                ? BoxDecoration(
                                    color: c.accentSoft,
                                    shape: BoxShape.circle,
                                  )
                                : null,
                            child: Text(
                              e,
                              style: const TextStyle(fontSize: 21),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              builder: (context, menu, _) => _StripButton(
                tooltip: 'React',
                icon: Icons.add_reaction_outlined,
                onTap: () => menu.isOpen ? menu.close() : menu.open(),
              ),
            ),
          if (reply != null)
            _StripButton(tooltip: 'Reply', icon: Icons.reply, onTap: reply),
        ],
      ),
    );
  }
}

class _StripButton extends StatelessWidget {
  const _StripButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: SizedBox.square(
          dimension: 28,
          child: Icon(icon, size: 17, color: c.muted),
        ),
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

/// The text box's menu: the usual cut, copy, paste and select all, plus
/// Undo and Redo while there's something to undo or redo.
Widget composerContextMenu(
  BuildContext context,
  EditableTextState state,
  UndoHistoryController undo,
) {
  final value = undo.value;
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: [
      if (value.canUndo)
        ContextMenuButtonItem(
          label: 'Undo',
          onPressed: () {
            undo.undo();
            state.hideToolbar();
          },
        ),
      if (value.canRedo)
        ContextMenuButtonItem(
          label: 'Redo',
          onPressed: () {
            undo.redo();
            state.hideToolbar();
          },
        ),
      ...state.contextMenuButtonItems,
    ],
  );
}

/// Spell check where the platform has it (phones), else none.
SpellCheckConfiguration? composerSpellCheck() {
  try {
    final native = WidgetsBinding
        .instance
        .platformDispatcher
        .nativeSpellCheckServiceDefined;
    return native ? const SpellCheckConfiguration() : null;
  } on Object {
    return null;
  }
}

/// Above the text box while replying: who to, what they said, and a way
/// out.
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.message, required this.onCancel});

  final ChatMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final name = message.authorName.isEmpty ? 'Someone' : message.authorName;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, size: 18, color: c.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                if (message.preview.isNotEmpty)
                  Text(
                    message.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: const Icon(Icons.close),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.viewModel,
    required this.controller,
    required this.undoController,
    required this.focusNode,
    required this.onSend,
    required this.hintText,
  });

  final MessageThreadViewModel viewModel;
  final TextEditingController controller;
  final UndoHistoryController undoController;
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
                if (vm.replyingTo case final reply?)
                  _ReplyBar(message: reply, onCancel: vm.cancelReply),
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
                          undoController: undoController,
                          // Stays enabled while sending, so the keyboard
                          // (and what's typed next) isn't lost.
                          readOnly: sending,
                          minLines: 1,
                          maxLines: 8,
                          maxLength: 4000,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          autocorrect: true,
                          enableSuggestions: true,
                          spellCheckConfiguration: composerSpellCheck(),
                          contextMenuBuilder: (context, state) =>
                              composerContextMenu(
                                context,
                                state,
                                undoController,
                              ),
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
