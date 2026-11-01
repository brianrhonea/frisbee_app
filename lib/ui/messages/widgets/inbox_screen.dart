import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../routing/routes.dart';
import '../../chat/view_models/chat_room_viewmodel.dart';
import '../../chat/widgets/chat_layout.dart';
import '../../chat/widgets/chat_room_screen.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/direct_chat_viewmodel.dart';
import '../view_models/inbox_viewmodel.dart';
import 'direct_chat_screen.dart';

/// Width of the inbox list beside an open conversation.
const _listWidth = 300.0;

/// Messages: direct messages and team chats in one inbox. Wide screens
/// list them on the left and open the picked one on the right; phones list
/// them and slide the picked one in full screen.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, required this.viewModel});

  final InboxViewModel viewModel;

  void _openFullScreen(BuildContext context, InboxItem item) => switch (item) {
    DirectItem(:final conversation) => context.push(
      Routes.conversation(conversation.id),
    ),
    RoomItem(:final team, :final room) => context.push(
      Routes.chatRoom(team.id, room.id),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final size = ScreenSize.of(context);
    if (size.isMobile) {
      return Scaffold(
        appBar: AppBar(
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
          showHeader: false,
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

/// The open conversation or team room, beside the list.
class _Detail extends StatelessWidget {
  const _Detail({required this.item});

  final InboxItem item;

  @override
  Widget build(BuildContext context) => switch (item) {
    DirectItem(:final conversation) => ViewModelHost(
      key: ValueKey('dm-pane-${conversation.id}'),
      create: (c) => DirectChatViewModel(
        conversationId: conversation.id,
        directMessageRepository: c.read(),
        authRepository: c.read(),
        filePicker: c.read(),
      ),
      builder: (_, dmVm) => DirectChatView(viewModel: dmVm),
    ),
    RoomItem(:final team, :final room) => ViewModelHost(
      key: ValueKey('room-pane-${team.id}-${room.id}'),
      create: (c) => ChatRoomViewModel(
        teamId: team.id,
        roomId: room.id,
        teamRepository: c.read(),
        chatRepository: c.read(),
        notificationRepository: c.read(),
        authRepository: c.read(),
        filePicker: c.read(),
      ),
      builder: (_, roomVm) => ChatRoomView(viewModel: roomVm),
    ),
  };
}

/// The inbox: a search box, All / Unread filters and the entries;
/// [selectedKey] is highlighted.
class InboxList extends StatelessWidget {
  const InboxList({
    super.key,
    required this.viewModel,
    required this.onOpen,
    this.selectedKey,
    this.showHeader = true,
  });

  final InboxViewModel viewModel;
  final ValueChanged<InboxItem> onOpen;
  final String? selectedKey;

  /// The "Messages" title with a new-message button.
  final bool showHeader;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      final c = AppColors.of(context);
      if (!vm.loaded) return const LoadingView();
      final items = vm.items;
      final unread = vm.unreadCount;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Messages',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: c.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'New message',
                    onPressed: () => context.push(Routes.newMessage),
                    icon: Icon(Icons.edit_square, size: 20, color: c.ink),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SizedBox(
              height: 38,
              child: TextField(
                onChanged: vm.setQuery,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search messages',
                  hintStyle: TextStyle(fontSize: 12.5, color: c.muted),
                  prefixIcon: Icon(Icons.search, size: 18, color: c.muted),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 6,
              children: [
                for (final (filter, label) in [
                  (InboxFilter.all, 'All messages'),
                  (InboxFilter.unread, 'Unread ($unread)'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: c.card,
                    side: BorderSide.none,
                    selected: vm.filter == filter,
                    onSelected: (_) => vm.setFilter(filter),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          Expanded(
            child: items.isEmpty
                ? vm.error != null
                      ? ErrorView(error: vm.error)
                      : EmptyView(
                          icon: Icons.chat_bubble_outline,
                          title: vm.allItems.isEmpty
                              ? 'No messages yet'
                              : 'Nothing here',
                          message: vm.allItems.isEmpty
                              ? 'Message anyone on UltiUP privately, or '
                                    'chat with your team. Tap New message '
                                    'and search by name.'
                              : null,
                        )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _InboxTile(
                      item: items[i],
                      selected: items[i].key == selectedKey,
                      onTap: () => onOpen(items[i]),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final InboxItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final unread = item.unread;
    final when = item.lastAt;
    return Material(
      color: selected ? c.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? c.ink : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(11, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              switch (item) {
                DirectItem(:final title) => PersonAvatar(
                  name: title,
                  radius: 18,
                ),
                RoomItem(:final team) => TeamBadge(
                  size: 36,
                  community: team.isCommunity,
                ),
              },
              const SizedBox(width: 10),
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
                              fontSize: 13,
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                        ),
                        if (when != null)
                          Text(
                            _when(when),
                            style: TextStyle(fontSize: 10.5, color: c.muted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: unread ? c.ink : c.muted,
                              fontWeight: unread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.circle, size: 9, color: c.ink),
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
