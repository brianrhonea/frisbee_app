import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/draft/message_draft_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/people/people_repository.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../chat/widgets/chat_layout.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/app_search_field.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scroll_to_top.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/user_avatar.dart';
import '../../core/ui/view_model_host.dart';
import '../../shell/widgets/app_shell.dart' show ProfileButton;
import '../view_models/direct_chat_viewmodel.dart';
import '../view_models/inbox_viewmodel.dart';
import 'direct_chat_screen.dart';

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
          title: const Text('Messages'),
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
  });

  final InboxViewModel viewModel;
  final ValueChanged<InboxItem> onOpen;
  final String? selectedKey;

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
      final items = vm.items;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: AppSearchField(
              hint: 'Search messages',
              onChanged: vm.setQuery,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _FilterBar(
              selected: vm.filter,
              unread: vm.unreadCount,
              requests: vm.requestCount,
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
          Divider(height: 1, color: c.border),
          Expanded(
            child: items.isEmpty
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
                                    'New message and search by name. Team '
                                    "chats are on each team's page."
                              : null,
                        )
                : ScrollToTop(
                    controller: _scroll,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        final tile = _InboxTile(
                          item: item,
                          selected: item.key == selectedKey,
                          onTap: () {
                            _openSwipe.value = null;
                            onOpen(item);
                          },
                          onActions: () => _actions(item),
                        );
                        if (item.isRequest) return tile;
                        return _SwipeActions(
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
                                color: const Color(0xFF6E56CF),
                                onTap: () => vm.toggleMute.execute(item),
                              ),
                            _SwipeAction(
                              label: 'Delete',
                              icon: Icons.delete_outline,
                              color: Colors.red.shade600,
                              onTap: () => _confirmDelete(item),
                            ),
                          ],
                          child: tile,
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

/// All / Unread / Requests / Archived on one line at any width: each takes
/// a quarter, and its label shrinks to fit rather than wrapping.
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
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          for (final (filter, label, count) in filters)
            Expanded(
              child: Semantics(
                button: true,
                selected: filter == selected,
                label: count > 0 ? '$label, $count' : label,
                excludeSemantics: true,
                child: Material(
                  color: filter == selected ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onSelect(filter),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            count > 0 ? '$label ($count)' : label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: filter == selected ? c.onAccent : c.ink,
                            ),
                          ),
                        ),
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

class _SwipeAction {
  const _SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
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
                                      Icon(a.icon, color: Colors.white),
                                      const SizedBox(height: 4),
                                      Text(
                                        a.label,
                                        style: const TextStyle(
                                          color: Colors.white,
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
      color: selected ? c.accentSoft : Theme.of(context).cardColor,
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
          padding: const EdgeInsets.fromLTRB(11, 10, 14, 10),
          child: Row(
            children: [
              if (item.isGroup)
                _GroupFaces(faces: item.faces)
              else
                UserAvatar(uid: item.otherId, name: item.title, radius: 24),
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
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: c.ink,
                            ),
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
                          Text(
                            _when(when),
                            style: TextStyle(fontSize: 11, color: c.muted),
                          ),
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
                                    fontSize: 12.5,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w600,
                                    color: c.accent,
                                  ),
                                )
                              : Text(
                                  item.preview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: unread ? c.ink : c.muted,
                                    fontWeight: unread
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Icon(Icons.circle, size: 10, color: c.ink),
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
        radius: 24,
        backgroundColor: c.accentSoft,
        foregroundColor: c.ink,
        child: const Icon(Icons.groups, size: 24),
      );
    }
    Widget face(({String uid, String name}) f) => DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).cardColor, width: 2),
      ),
      child: UserAvatar(uid: f.uid, name: f.name, radius: 16),
    );
    return SizedBox.square(
      dimension: 48,
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
