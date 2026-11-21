import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/chat/team_chat_activity.dart';
import '../../../data/repositories/draft/message_draft_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/people/people_repository.dart';
import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../chat/widgets/chat_layout.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/app_search_field.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart' show SectionHeader;
import '../../core/ui/scroll_to_top.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/user_avatar.dart';
import '../../core/ui/view_model_host.dart';
import '../../shell/widgets/app_shell.dart' show ProfileButton;
import '../view_models/direct_chat_viewmodel.dart';
import '../view_models/inbox_viewmodel.dart';
import 'direct_chat_screen.dart';
import '../../moderation/widgets/report_sheet.dart';

/// Width of the inbox list beside an open conversation.
const _listWidth = 300.0;

/// Messages: the user's private conversations. Team chats live on team
/// pages. Wide screens list them on the left and open the picked one on
/// the right; phones list them and slide the picked one in full screen.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, required this.viewModel});

  final InboxViewModel viewModel;

  void _openFullScreen(BuildContext context, InboxItem item) =>
      context.push(Routes.conversation(item.conversation.id));

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final size = ScreenSize.of(context);
    if (size.isMobile) {
      return Scaffold(
        appBar: AppBar(
          leading: ProfileButton.leading(context),
          title: const Text('Inbox'),
          actions: [
            IconButton(
              tooltip: 'New message',
              onPressed: () => context.push(Routes.newMessage),
              icon: const Icon(Icons.edit_square),
            ),
          ],
        ),
        body: InboxList(
          viewModel: vm,
          onOpen: (item) => _openFullScreen(context, item),
        ),
      );
    }
    final c = AppColors.of(context);
    return Scaffold(
      body: Padding(
        padding: pagePadding(size).copyWith(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Your sideline, connected.',
              subtitle: 'Plan the next point. Keep the conversation going.',
              action: FilledButton.icon(
                onPressed: () => context.push(Routes.newMessage),
                icon: const Icon(Icons.edit_square, size: 18),
                label: const Text('New message'),
              ),
            ),
            Expanded(
              child: Card(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final split =
                        constraints.maxWidth >= chatSplitBreakpoint - 120;
                    return ListenableBuilder(
                      listenable: vm,
                      builder: (context, _) {
                        if (!split) {
                          return InboxList(
                            viewModel: vm,
                            onOpen: (i) => _openFullScreen(context, i),
                          );
                        }
                        final selected = vm.selected;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: constraints.maxWidth >= 900
                                  ? _listWidth
                                  : 260,
                              child: InboxList(
                                viewModel: vm,
                                flat: true,
                                selectedKey: selected?.key,
                                onOpen: vm.select,
                              ),
                            ),
                            VerticalDivider(width: 1, color: c.border),
                            Expanded(
                              child: selected == null
                                  ? const ChatPlaceholder(
                                      text:
                                          'Pick a conversation, or start a '
                                          'new one.',
                                    )
                                  : _Detail(item: selected),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The open conversation, beside the list.
class _Detail extends StatelessWidget {
  const _Detail({required this.item});

  final InboxItem item;

  @override
  Widget build(BuildContext context) => ViewModelHost(
    key: ValueKey('dm-pane-${item.conversation.id}'),
    create: (c) => DirectChatViewModel(
      outbox: c.read(),
      conversationId: item.conversation.id,
      directMessageRepository: c.read(),
      authRepository: c.read(),
      filePicker: c.read(),
      peopleRepository: c.read<PeopleRepository?>(),
      draftRepository: c.read<MessageDraftRepository?>(),
      notificationRepository: c.read<NotificationRepository?>(),
    ),
    builder: (_, dmVm) => DirectChatView(viewModel: dmVm),
  );
}

/// The inbox: a search box, All / Unread / Requests / Archived filters and
/// the entries; [selectedKey] is highlighted. Swipe an entry left to mute
/// or delete it; long-press (or right-click) for those and Archive. The
/// page around it has the one New message button.
class InboxList extends StatefulWidget {
  const InboxList({
    super.key,
    required this.viewModel,
    required this.onOpen,
    this.selectedKey,
    this.flat = false,
  });

  final InboxViewModel viewModel;
  final ValueChanged<InboxItem> onOpen;
  final String? selectedKey;

  /// Rows edge to edge with lines between, for a list that's already in
  /// a panel (beside an open conversation); else grouped in cards.
  final bool flat;

  @override
  State<InboxList> createState() => _InboxListState();
}

class _InboxListState extends State<InboxList> {
  InboxViewModel get viewModel => widget.viewModel;
  final _scroll = ScrollController();

  /// The entry swiped open, if any; opening another closes it.
  final _openSwipe = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    viewModel.archive.addListener(_onArchive);
    viewModel.delete.addListener(_onDelete);
    viewModel.toggleMute.addListener(_onMute);
  }

  @override
  void dispose() {
    viewModel.archive.removeListener(_onArchive);
    viewModel.delete.removeListener(_onDelete);
    viewModel.toggleMute.removeListener(_onMute);
    _scroll.dispose();
    _openSwipe.dispose();
    super.dispose();
  }

  void _onArchive() => _report(viewModel.archive, 'Done.');

  void _onDelete() => _report(viewModel.delete, 'Conversation deleted.');

  void _onMute() => _report(viewModel.toggleMute, null);

  void _report(Command<Object?> cmd, String? done) {
    if (cmd.error) {
      showErrorSnackBar(context, cmd.result);
    } else if (cmd.completed) {
      if (done != null) showSnackBar(context, done);
    } else {
      return;
    }
    cmd.clearResult();
  }

  Future<void> _confirmDelete(InboxItem item) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete conversation?',
      message:
          'Its messages are removed for you only; ${item.title} still '
          'has them. New messages will bring it back.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) viewModel.delete.execute(item);
  }

  Future<void> _actions(InboxItem item) async {
    final vm = viewModel;
    final action = await showModalBottomSheet<_InboxAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!item.isRequest && vm.canMute)
              ListTile(
                leading: Icon(
                  item.muted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                ),
                title: Text(item.muted ? 'Unmute' : 'Mute'),
                subtitle: item.muted
                    ? null
                    : const Text('No notifications from this conversation.'),
                onTap: () => Navigator.pop(context, _InboxAction.mute),
              ),
            if (!item.isRequest)
              ListTile(
                leading: Icon(
                  item.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                title: Text(item.isArchived ? 'Unarchive' : 'Archive'),
                onTap: () => Navigator.pop(context, _InboxAction.archive),
              ),
            if (!item.isRequest)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete conversation'),
                subtitle: Text('For you only; ${item.title} keeps it.'),
                onTap: () => Navigator.pop(context, _InboxAction.delete),
              ),
            if (item.isRequest)
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Open the request to accept or delete it.'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _InboxAction.mute:
        vm.toggleMute.execute(item);
      case _InboxAction.archive:
        vm.archive.execute(item);
      case _InboxAction.delete:
        await _confirmDelete(item);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      final selectedKey = widget.selectedKey;
      final onOpen = widget.onOpen;
      final c = AppColors.of(context);
      if (!vm.loaded) return const LoadingView();
      // Requests from someone blocked either way aren't shown.
      final blocks = watchBlocks(context);
      final items = [
        for (final i in vm.items)
          if (!(i.isRequest && !i.isGroup && blocks.hides(i.otherId))) i,
      ];
      final teamChats = vm.teamChats;
      // Section headings only when both kinds are listed.
      final headed = teamChats.isNotEmpty && items.isNotEmpty;
      final lead = teamChats.isEmpty ? 0 : teamChats.length + (headed ? 1 : 0);
      Widget heading(String text, {bool first = false}) => Padding(
        padding: EdgeInsets.fromLTRB(16, first ? 6 : 18, 16, 0),
        child: SectionHeader(text),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: AppSearchField(
              hint: 'Search messages',
              onChanged: vm.setQuery,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _FilterBar(
              selected: vm.filter,
              unread: vm.unreadCount,
              requests: vm.requestItems
                  .where((i) => i.isGroup || !blocks.hides(i.otherId))
                  .length,
              onSelect: vm.setFilter,
            ),
          ),
          if (vm.filter == InboxFilter.requests)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                "People you don't follow. Open one to read it; they won't "
                "know you've seen it unless you accept.",
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
          Expanded(
            child: items.isEmpty && teamChats.isEmpty
                ? vm.error != null
                      ? ErrorView(error: vm.error)
                      : EmptyView(
                          icon: Icons.chat_bubble_outline,
                          title: switch (vm.filter) {
                            InboxFilter.requests => 'No message requests',
                            InboxFilter.archived => 'Nothing archived',
                            _ when vm.allItems.isEmpty => 'No messages yet',
                            _ => 'Nothing here',
                          },
                          message:
                              vm.allItems.isEmpty &&
                                  vm.filter == InboxFilter.all
                              ? 'Message anyone on Stall 10 privately. Tap '
                                    'New message and search by name. Your '
                                    "teams' chats show here too."
                              : null,
                        )
                : ScrollToTop(
                    controller: _scroll,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.only(top: headed ? 0 : 4, bottom: 16),
                      itemCount: lead + (headed ? 1 : 0) + items.length,
                      itemBuilder: (context, i) {
                        if (headed && i == 0) {
                          return heading('Team chats', first: true);
                        }
                        if (i < lead) {
                          final t = i - (headed ? 1 : 0);
                          final s = teamChats[t];
                          return _CardSlice(
                            flat: widget.flat,
                            first: t == 0,
                            last: t == teamChats.length - 1,
                            child: _TeamChatTile(
                              summary: s,
                              onTap: () {
                                _openSwipe.value = null;
                                final room = s.openRoom;
                                context.push(
                                  room == null
                                      ? Routes.teamChat(s.team.id)
                                      : Routes.chatRoom(s.team.id, room.id),
                                );
                              },
                            ),
                          );
                        }
                        if (headed && i == lead) {
                          return heading('Direct messages');
                        }
                        final d = i - lead - (headed ? 1 : 0);
                        final item = items[d];
                        Widget slice(Widget child) => _CardSlice(
                          flat: widget.flat,
                          first: d == 0,
                          last: d == items.length - 1,
                          child: child,
                        );
                        final tile = _InboxTile(
                          item: item,
                          selected: item.key == selectedKey,
                          onTap: () {
                            _openSwipe.value = null;
                            onOpen(item);
                          },
                          onActions: () => _actions(item),
                        );
                        if (item.isRequest) return slice(tile);
                        return slice(
                          _SwipeActions(
                            key: ValueKey(item.key),
                            id: item.key,
                            open: _openSwipe,
                            actions: [
                              if (vm.canMute)
                                _SwipeAction(
                                  label: item.muted ? 'Unmute' : 'Mute',
                                  icon: item.muted
                                      ? Icons.notifications_active_outlined
                                      : Icons.notifications_off_outlined,
                                  color: c.field,
                                  foreground: c.ink,
                                  onTap: () => vm.toggleMute.execute(item),
                                ),
                              // Destructive, but in ink rather than red:
                              // red is kept for live games.
                              _SwipeAction(
                                label: 'Delete',
                                icon: Icons.delete_outline,
                                color: c.ink2,
                                foreground: c.card,
                                onTap: () => _confirmDelete(item),
                              ),
                            ],
                            child: tile,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      );
    },
  );
}

/// All / Unread / Requests / Archived as pill chips on one line, scrolling
/// sideways if they don't fit. Unread's count is amber (it's the user's to
/// do); Requests' is turf.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.unread,
    required this.requests,
    required this.onSelect,
  });

  final InboxFilter selected;
  final int unread;
  final int requests;
  final ValueChanged<InboxFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final filters = [
      (InboxFilter.all, 'All', 0),
      (InboxFilter.unread, 'Unread', unread),
      (InboxFilter.requests, 'Requests', requests),
      (InboxFilter.archived, 'Archived', 0),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (filter, label, count) in filters) ...[
            if (filter != InboxFilter.all) const SizedBox(width: 8),
            Semantics(
              button: true,
              selected: filter == selected,
              label: count > 0 ? '$label, $count' : label,
              excludeSemantics: true,
              child: Material(
                color: filter == selected ? c.chipOn : c.card,
                shape: StadiumBorder(
                  side: filter == selected
                      ? BorderSide.none
                      : BorderSide(color: c.border2),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onSelect(filter),
                  child: Container(
                    height: 36,
                    padding: EdgeInsets.only(
                      left: 14,
                      right: count > 0 ? 8 : 14,
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: filter == selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: filter == selected ? c.onChipOn : c.ink,
                          ),
                        ),
                        if (count > 0) ...[
                          const SizedBox(width: 6),
                          if (filter == InboxFilter.unread)
                            CountPill(count)
                          else
                            Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: filter == selected
                                    ? c.onChipOn
                                    : c.accent,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SwipeAction {
  const _SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;
}

/// One row of a card that's built row by row (so long lists stay lazy):
/// the card's border and rounded corners on its [first] and [last] rows,
/// a line between rows. [flat]: no card, just the line below.
class _CardSlice extends StatelessWidget {
  const _CardSlice({
    required this.first,
    required this.last,
    required this.child,
    this.flat = false,
  });

  final bool first;
  final bool last;
  final bool flat;
  final Widget child;

  static const _radius = Radius.circular(16);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (flat) {
      return DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: child,
      );
    }
    final radius = BorderRadius.vertical(
      top: first ? _radius : Radius.zero,
      bottom: last ? _radius : Radius.zero,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CustomPaint(
        foregroundPainter: _SlicePainter(
          color: c.border,
          first: first,
          last: last,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: ColoredBox(color: c.card, child: child),
        ),
      ),
    );
  }
}

/// The outline of a [_CardSlice]: its sides, its top (rounded) when it's
/// the first row, and its bottom: rounded when last, else the line under
/// the row.
class _SlicePainter extends CustomPainter {
  const _SlicePainter({
    required this.color,
    required this.first,
    required this.last,
  });

  final Color color;
  final bool first;
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const r = 16.0;
    final w = size.width - 0.5;
    final h = size.height - 0.5;
    const x = 0.5;
    const round = Radius.circular(r);
    final top = first ? x + r : 0.0;
    final bottom = last ? h - r : size.height;
    final path = Path()
      ..moveTo(x, top)
      ..lineTo(x, bottom)
      ..moveTo(w, top)
      ..lineTo(w, bottom);
    if (first) {
      path
        ..moveTo(x, x + r)
        ..arcToPoint(const Offset(x + r, x), radius: round)
        ..lineTo(w - r, x)
        ..arcToPoint(Offset(w, x + r), radius: round);
    }
    if (last) {
      path
        ..moveTo(x, h - r)
        ..arcToPoint(Offset(x + r, h), radius: round, clockwise: false)
        ..lineTo(w - r, h)
        ..arcToPoint(Offset(w, h - r), radius: round, clockwise: false);
    } else {
      path
        ..moveTo(x, h)
        ..lineTo(w, h);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SlicePainter old) =>
      old.color != color || old.first != first || old.last != last;
}

/// Swipe left to show buttons behind an entry, like a phone's own inbox.
/// [open] holds which entry is showing its buttons; one at a time.
class _SwipeActions extends StatefulWidget {
  const _SwipeActions({
    super.key,
    required this.id,
    required this.open,
    required this.actions,
    required this.child,
  });

  final String id;
  final ValueNotifier<String?> open;
  final List<_SwipeAction> actions;
  final Widget child;

  @override
  State<_SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<_SwipeActions>
    with SingleTickerProviderStateMixin {
  static const _buttonWidth = 76.0;

  late final _offset = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  double get _width => _buttonWidth * widget.actions.length;

  @override
  void initState() {
    super.initState();
    widget.open.addListener(_onOpenChanged);
  }

  @override
  void dispose() {
    widget.open.removeListener(_onOpenChanged);
    _offset.dispose();
    super.dispose();
  }

  void _onOpenChanged() {
    if (widget.open.value != widget.id && _offset.value > 0) {
      _offset.animateTo(0, curve: Curves.easeOut);
    }
  }

  void _drag(DragUpdateDetails d) {
    _offset.value = (_offset.value - d.delta.dx / _width).clamp(0.0, 1.0);
  }

  void _settle(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final open = v < -300 || (v <= 300 && _offset.value > 0.5);
    _offset.animateTo(open ? 1 : 0, curve: Curves.easeOut);
    if (open) {
      if (widget.open.value != widget.id) HapticFeedback.selectionClick();
      widget.open.value = widget.id;
    } else if (widget.open.value == widget.id) {
      widget.open.value = null;
    }
  }

  void _close() {
    _offset.animateTo(0, curve: Curves.easeOut);
    if (widget.open.value == widget.id) widget.open.value = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    return GestureDetector(
      onHorizontalDragUpdate: _drag,
      onHorizontalDragEnd: _settle,
      child: AnimatedBuilder(
        animation: _offset,
        builder: (context, child) {
          final shown = _offset.value * _width;
          return Stack(
            children: [
              if (shown > 0)
                Positioned.fill(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final a in widget.actions)
                        SizedBox(
                          width: shown / widget.actions.length,
                          child: Material(
                            color: a.color,
                            child: InkWell(
                              onTap: () {
                                _close();
                                a.onTap();
                              },
                              child: ClipRect(
                                child: OverflowBox(
                                  maxWidth: _buttonWidth,
                                  minWidth: _buttonWidth,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(a.icon, color: a.foreground),
                                      const SizedBox(height: 4),
                                      Text(
                                        a.label,
                                        style: TextStyle(
                                          color: a.foreground,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Transform.translate(offset: Offset(-shown, 0), child: child),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// A team's or community's chat in the inbox: its name, which rooms have
/// new messages, and when the newest was sent.
class _TeamChatTile extends StatelessWidget {
  const _TeamChatTile({required this.summary, required this.onTap});

  final TeamChatSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final unread = summary.unread;
    final when = summary.lastAt;
    return Material(
      color: c.card,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              TeamBadge(
                size: 44,
                community: summary.team.kind == TeamKind.community,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            summary.team.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _InboxTile._titleStyle(c, unread),
                          ),
                        ),
                        if (when != null)
                          Text(
                            _InboxTile._when(when),
                            style: _InboxTile._timeStyle(c, unread),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            summary.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _InboxTile._previewStyle(c, unread),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: c.highlight,
                            semanticLabel: 'Unread',
                          ),
                        ],
                      ],
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

class _InboxTile extends StatelessWidget {
  const _InboxTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onActions,
  });

  final InboxItem item;
  final bool selected;
  final VoidCallback onTap;

  /// Mute, archive or delete it: long-press, or right-click.
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final unread = item.unread;
    final when = item.lastAt;
    final typing = item.typing;
    return Material(
      color: selected ? c.accentSoft : c.card,
      child: InkWell(
        onTap: onTap,
        onLongPress: onActions,
        onSecondaryTap: onActions,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? c.accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(11, 12, 14, 12),
          child: Row(
            children: [
              if (item.isGroup)
                _GroupFaces(faces: item.faces)
              else
                UserAvatar(uid: item.otherId, name: item.title, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _titleStyle(c, unread),
                          ),
                        ),
                        if (item.muted)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.notifications_off_outlined,
                              size: 14,
                              color: c.muted,
                              semanticLabel: 'Muted',
                            ),
                          ),
                        if (when != null)
                          Text(_when(when), style: _timeStyle(c, unread)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: typing != null
                              ? Text(
                                  typing,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w600,
                                    color: c.accent,
                                  ),
                                )
                              : Text(
                                  item.preview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: _previewStyle(c, unread),
                                ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Icon(
                              Icons.circle,
                              size: 10,
                              color: c.highlight,
                              semanticLabel: 'Unread',
                            ),
                          ),
                        ],
                      ],
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

  /// Unread rows are bold, with the time in amber ink: they're the user's
  /// to read.
  static TextStyle _titleStyle(AppColors c, bool unread) => TextStyle(
    fontSize: 15,
    fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
    color: c.ink,
  );

  static TextStyle _timeStyle(AppColors c, bool unread) => TextStyle(
    fontSize: 12,
    fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
    color: unread ? c.highlightInk : c.muted,
  );

  static TextStyle _previewStyle(AppColors c, bool unread) => TextStyle(
    fontSize: 13,
    color: unread ? c.ink2 : c.muted,
    fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
  );

  static String _when(DateTime d) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(d, now)) return DateFormat.jm().format(d);
    if (now.difference(d).inDays < 2) return 'Yesterday';
    if (now.difference(d).inDays < 7) return DateFormat.E().format(d);
    return DateFormat.MMMd().format(d);
  }
}

/// A group's photo: two of its members, overlapping, in the space of one.
class _GroupFaces extends StatelessWidget {
  const _GroupFaces({required this.faces});

  final List<({String uid, String name})> faces;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (faces.length < 2) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: c.accentSoft,
        foregroundColor: c.accentInk,
        child: const Icon(Icons.groups, size: 22),
      );
    }
    Widget face(({String uid, String name}) f) => DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.card, width: 2),
      ),
      child: UserAvatar(uid: f.uid, name: f.name, radius: 15),
    );
    return SizedBox.square(
      dimension: 44,
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: face(faces[1])),
          Positioned(bottom: 0, right: 0, child: face(faces[0])),
        ],
      ),
    );
  }
}

enum _InboxAction { mute, archive, delete }
