import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
/// Long-press (or right-click) a message to react, reply, copy or delete
/// it; swipe a message's bubble to the right to reply. Drag anywhere to the
/// left to see every message's time.
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

class _MessageThreadViewState extends State<MessageThreadView>
    with SingleTickerProviderStateMixin {
  MessageThreadViewModel get vm => widget.viewModel;
  late final _reveal = _TimeReveal(this);

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
    _reveal.dispose();
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
        canOpenProfile:
            vm.opensProfiles && m.authorId.isNotEmpty && !vm.isMine(m),
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
      case _Profile():
        _openProfile(m.authorId);
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
              child: _RevealTimes(
                reveal: _reveal,
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
                    reveal: _reveal,
                  ),
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

class _Profile extends _MessageAction {
  const _Profile();
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
    required this.reveal,
  });

  /// The long-press sheet.
  final ValueChanged<ChatMessage> onActions;

  /// Starts a reply (ignored where replies aren't allowed).
  final ValueChanged<ChatMessage> onReply;

  /// Toggles a reaction; null where reactions aren't offered.
  final void Function(ChatMessage, String)? onReact;
  final ValueChanged<ChatMessage> onDelete;
  final ValueChanged<String> onProfile;

  /// Every message's time, shown while the thread is dragged left.
  final _TimeReveal reveal;
}

/// Long-press on a message: when it was sent, a row of quick reactions,
/// then Reply, Copy and Delete. The time is here too so it isn't only
/// behind the drag-left gesture.
class _MessageActionsSheet extends StatelessWidget {
  const _MessageActionsSheet({
    required this.message,
    required this.mine,
    required this.canReact,
    required this.canReply,
    required this.canDelete,
    required this.canOpenProfile,
  });

  final ChatMessage message;

  /// The user's current reaction, highlighted.
  final String? mine;
  final bool canReact;
  final bool canReply;
  final bool canDelete;
  final bool canOpenProfile;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    void pick(_MessageAction a) => Navigator.pop(context, a);
    final name = message.authorName.isEmpty ? 'Member' : message.authorName;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message.createdAt case final sent?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _FeedRow._stamp(sent),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: c.muted),
              ),
            ),
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
          if (canOpenProfile)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text("View $name's profile"),
              onTap: () => pick(const _Profile()),
            ),
          // Destructive, but neutral: red is kept for live games, and the
          // confirm dialog says what deleting does.
          if (canDelete)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete message'),
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
        final canSwipeReply = vm.canWrite && vm.canReact && m.createdAt != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (newDay && m.createdAt != null)
              _DayDivider(label: _dayLabel(m.createdAt!))
            else if (bubbles && gap && m.createdAt != null)
              _TimeLabel(time: m.createdAt!),
            _TimeSlide(
              key: ValueKey(m.id),
              reveal: actions.reveal,
              time: m.createdAt,
              // Like a phone's messages app: your own bubbles slide over
              // to make room; the other person's have room already.
              moves: !bubbles || vm.isMine(m),
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
                      canSwipeReply: canSwipeReply,
                    )
                  : _FeedRow(
                      message: m,
                      showAuthor: !grouped,
                      nameColor: color == null ? null : Color(color),
                      viewModel: vm,
                      actions: actions,
                      onDelete: onDelete,
                      videoPlayer: videoPlayer,
                      canSwipeReply: canSwipeReply,
                    ),
            ),
            if (vm.statusFor(m) case final receipt?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                child: Text(
                  receipt,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: vm.isFailed(m)
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
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

/// Drag a message's bubble to the right to reply to it, as in most
/// messaging apps. A drag to the left isn't this widget's: the thread
/// scrolls and shows the times ([_RevealTimes]).
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
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
    // The whole message counts, even beside short text in a feed row.
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _RightSwipe: GestureRecognizerFactoryWithHandlers<_RightSwipe>(
          () => _RightSwipe(debugOwner: this),
          (r) => r
            ..onUpdate = _update
            ..onEnd = _end
            ..onCancel = _end,
        ),
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        fit: StackFit.passthrough,
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

/// A horizontal drag that only claims drags to the right. One that sets
/// off to the left gives way at once, so the thread keeps scrolling while
/// it shows the times ([_RevealTimes]).
class _RightSwipe extends HorizontalDragGestureRecognizer {
  _RightSwipe({super.debugOwner});

  final _travel = <int, double>{};
  bool _won = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _travel[event.pointer] = 0;
    super.addAllowedPointer(event);
  }

  @override
  void acceptGesture(int pointer) {
    _won = true;
    super.acceptGesture(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_won && event is PointerMoveEvent) {
      final dx = (_travel[event.pointer] ?? 0) + event.delta.dx;
      _travel[event.pointer] = dx;
      if (dx < -kTouchSlop / 3) {
        resolvePointer(event.pointer, GestureDisposition.rejected);
        return;
      }
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _won = false;
    _travel.clear();
    super.didStopTrackingLastPointer(pointer);
  }
}

/// How far every message's time is pulled in from the right: 0 hidden,
/// 1 shown. Dragging the thread left pulls them in; letting go slides
/// them away again, as on a phone's messages app.
class _TimeReveal {
  _TimeReveal(TickerProvider vsync)
    : controller = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 200),
      );

  final AnimationController controller;

  /// The room the times take at the right.
  static const width = 68.0;

  void drag(double dx) =>
      controller.value = (controller.value - dx / width).clamp(0.0, 1.0);

  void release() => controller.animateBack(0, curve: Curves.easeOut);

  void dispose() => controller.dispose();
}

/// The whole thread: a drag to the left, from anywhere (a bubble too),
/// shows the times until let go. It watches the finger rather than
/// competing for it, so the thread still scrolls up and down meanwhile,
/// as on a phone's messages app.
class _RevealTimes extends StatefulWidget {
  const _RevealTimes({required this.reveal, required this.child});

  final _TimeReveal reveal;
  final Widget child;

  @override
  State<_RevealTimes> createState() => _RevealTimesState();
}

class _RevealTimesState extends State<_RevealTimes> {
  /// The finger being followed, and how far it has gone since it touched.
  int? _pointer;
  Offset _moved = Offset.zero;

  /// Pulled left far enough, more across than down: showing the times.
  bool _revealing = false;

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _moved = Offset.zero;
    _revealing = false;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (_revealing) {
      widget.reveal.drag(e.delta.dx);
      return;
    }
    _moved += e.delta;
    if (_moved.dx < -kTouchSlop && _moved.dx.abs() > _moved.dy.abs()) {
      _revealing = true;
      widget.reveal.drag(_moved.dx + kTouchSlop);
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_revealing) widget.reveal.release();
    _revealing = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.child,
  );
}

/// One message row, with its time waiting off the right edge to slide in
/// while the thread is dragged left. [moves]: the row slides over to make
/// room.
class _TimeSlide extends StatelessWidget {
  const _TimeSlide({
    super.key,
    required this.reveal,
    required this.time,
    required this.moves,
    required this.child,
  });

  final _TimeReveal reveal;
  final DateTime? time;
  final bool moves;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = time;
    return AnimatedBuilder(
      animation: reveal.controller,
      child: child,
      builder: (context, child) {
        final r = reveal.controller.value;
        const w = _TimeReveal.width;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.translate(
              offset: Offset(moves ? -r * w : 0, 0),
              child: child,
            ),
            if (r > 0 && t != null)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: w,
                child: Transform.translate(
                  offset: Offset((1 - r) * w, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      DateFormat.jm().format(t),
                      maxLines: 1,
                      style: TextStyle(fontSize: 11.5, color: c.muted),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A message's text, with tappable links. A long-press opens the
/// message's actions (Copy is one).
class _MessageText extends StatelessWidget {
  const _MessageText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) =>
      LinkifiedText(text, style: style, selectable: false);
}

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
        spacing: 6,
        runSpacing: 6,
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
                  side: BorderSide(color: r.mine ? c.accent : c.border2),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onReact == null
                      ? null
                      : () => onReact!(message, r.emoji),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    child: Text(
                      r.count > 1 ? '${r.emoji} ${r.count}' : r.emoji,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: r.mine ? c.accentInk : c.ink2,
                      ),
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

/// Long-press (or right-click) handling shared by both row styles: opens
/// the message's actions.
class _Pressable extends StatelessWidget {
  const _Pressable({
    required this.message,
    required this.actions,
    required this.child,
  });

  final ChatMessage message;
  final _RowActions actions;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPress: () => actions.onActions(message),
    onSecondaryTap: () => actions.onActions(message),
    child: child,
  );
}

/// One message, Discord style: everyone's on the left. The first of a run
/// shows the author's photo, name and time (tap either for their
/// profile); the rest of the run sits under it.
class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.message,
    required this.showAuthor,
    required this.nameColor,
    required this.viewModel,
    required this.actions,
    required this.onDelete,
    required this.videoPlayer,
    required this.canSwipeReply,
  });

  final ChatMessage message;
  final bool showAuthor;
  final Color? nameColor;
  final MessageThreadViewModel viewModel;
  final _RowActions actions;
  final VoidCallback? onDelete;
  final FileVideoPlayerBuilder videoPlayer;

  /// Swiping the message to the right replies to it.
  final bool canSwipeReply;

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
                    onTap: canOpen ? () => actions.onProfile(m.authorId) : null,
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: nameColor ?? c.ink,
                      ),
                    ),
                  ),
                ),
                if (vm.usernameOf(m.authorId) case final handle?)
                  Text(
                    '@$handle',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                Text(
                  time == null ? 'Sending…' : _stamp(time),
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ],
            ),
          ),
        if (m.text.isNotEmpty)
          _MessageText(
            text: m.text,
            style: TextStyle(
              color: time == null ? c.muted : c.ink,
              fontSize: 15,
              height: 1.4,
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
                  onTap: canOpen ? () => actions.onProfile(m.authorId) : null,
                  child: UserAvatar(
                    uid: m.authorId,
                    name: m.authorName,
                    radius: _avatar,
                  ),
                ),
              ),
            )
          : null,
    );
    return _Pressable(
      message: m,
      actions: actions,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, showAuthor ? 16 : 2, 16, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            gutter,
            Expanded(
              child: _SwipeToReply(
                enabled: canSwipeReply,
                onReply: () => actions.onReply(m),
                child: body,
              ),
            ),
          ],
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
    required this.canSwipeReply,
  });

  final ChatMessage message;
  final bool mine;
  final bool startsRun;
  final bool endsRun;
  final MessageThreadViewModel viewModel;
  final _RowActions actions;
  final VoidCallback? onDelete;
  final FileVideoPlayerBuilder videoPlayer;

  /// Swiping the bubble to the right replies to it.
  final bool canSwipeReply;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final m = message;
    final vm = viewModel;
    final sending = m.createdAt == null;
    final fill = mine ? c.accent : c.card;
    final ink = mine ? c.onAccent : c.ink;
    const big = Radius.circular(18);
    const small = Radius.circular(6);
    // Square the corners on the side the run continues.
    final radius = BorderRadius.only(
      topLeft: !mine && !startsRun ? small : big,
      bottomLeft: !mine && !endsRun ? small : big,
      topRight: mine && !startsRun ? small : big,
      bottomRight: mine && !endsRun ? small : big,
    );
    return _Pressable(
      message: m,
      actions: actions,
      child: Padding(
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
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: radius,
                        border: mine ? null : Border.all(color: c.border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: _MessageText(
                          text: m.text,
                          style: TextStyle(
                            color: sending ? ink.withValues(alpha: 0.7) : ink,
                            fontSize: 15,
                            height: 1.4,
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
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: _SwipeToReply(
                enabled: canSwipeReply,
                onReply: () => actions.onReply(m),
                child: bubble,
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: c.accent, width: 3)),
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

  // Its buttons (send, attach) keep the keyboard open.
  @override
  Widget build(BuildContext context) =>
      TextFieldTapRegion(child: _bar(context));

  Widget _bar(BuildContext context) {
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
            ? Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: c.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.border2),
                ),
                child: _attachMenu(context, c, vm, sending),
              )
            : const SizedBox.shrink();
        return Container(
          decoration: BoxDecoration(
            color: c.card,
            border: Border(top: BorderSide(color: c.border)),
          ),
          padding: EdgeInsets.fromLTRB(12, 8, 12, wide ? 16 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (vm.drafts.isNotEmpty)
                SizedBox(
                  height: 84,
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
              if (vm.replyingTo case final reply?)
                _ReplyBar(message: reply, onCancel: vm.cancelReply),
              if (sending)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  attach,
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: c.field,
                        borderRadius: BorderRadius.circular(22),
                      ),
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
                          style: TextStyle(fontSize: 15, color: c.ink),
                          decoration: InputDecoration(
                            hintText: hintText,
                            hintStyle: TextStyle(fontSize: 15, color: c.muted),
                            counterText: '',
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Always shown: touch screens of any size (tablets
                  // included) may have no Enter key to send with.
                  ValueListenableBuilder(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final empty =
                          value.text.trim().isEmpty && vm.drafts.isEmpty;
                      return IconButton.filled(
                        tooltip: 'Send',
                        style: IconButton.styleFrom(
                          fixedSize: const Size(44, 44),
                          backgroundColor: c.accent,
                          foregroundColor: c.onAccent,
                          disabledBackgroundColor: c.field,
                          disabledForegroundColor: c.muted,
                        ),
                        icon: const Icon(Icons.send_rounded, size: 20),
                        onPressed: sending || empty ? null : onSend,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// The attach button's menu: camera (where there is one), photo, file.
  Widget _attachMenu(
    BuildContext context,
    AppColors c,
    MessageThreadViewModel vm,
    bool sending,
  ) => PopupMenuButton<_AttachKind>(
    tooltip: 'Upload a photo, video or file',
    enabled: !sending && !vm.pickFiles.running && !vm.recordVideo.running,
    padding: EdgeInsets.zero,
    icon: Icon(Icons.add, color: c.ink2),
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
  );
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
