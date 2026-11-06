import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/people/people_repository.dart';
import '../../../routing/routes.dart';
import '../../chat/widgets/chat_layout.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../../utils/command.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/direct_chat_viewmodel.dart';
import '../view_models/inbox_viewmodel.dart';
import 'direct_chat_screen.dart';
import '../../core/ui/app_search_field.dart';

/// Width of the inbox list beside an open conversation.
const _listWidth = 300.0;

/// Messages: the user's private conversations. Team chats live on team
/// pages. Wide screens
/// list them on the left and open the picked one on the right; phones list
/// them and slide the picked one in full screen.
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
      notificationRepository: c.read<NotificationRepository?>(),
    ),
    builder: (_, dmVm) => DirectChatView(viewModel: dmVm),
  );
}

/// The inbox: a search box, All / Unread / Requests / Archived filters and
/// the entries; [selectedKey] is highlighted. Long-press (or right-click)
/// an entry to archive or delete it. The page around it has the one New
/// message button.
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

  @override
  void initState() {
    super.initState();
    viewModel.archive.addListener(_onArchive);
    viewModel.delete.addListener(_onDelete);
  }

  @override
  void dispose() {
    viewModel.archive.removeListener(_onArchive);
    viewModel.delete.removeListener(_onDelete);
    super.dispose();
  }

  void _onArchive() => _report(viewModel.archive, 'Done.');

  void _onDelete() => _report(viewModel.delete, 'Conversation deleted.');

  void _report(Command<Object?> cmd, String done) {
    if (cmd.error) {
      showErrorSnackBar(context, cmd.result);
    } else if (cmd.completed) {
      showSnackBar(context, done);
    } else {
      return;
    }
    cmd.clearResult();
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
      case _InboxAction.archive:
        vm.archive.execute(item);
      case _InboxAction.delete:
        final ok = await confirmDialog(
          context,
          title: 'Delete conversation?',
          message:
              'Its messages are removed for you only; ${item.title} still '
              'has them. New messages will bring it back.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (ok) vm.delete.execute(item);
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
      final unread = vm.unreadCount;
      final requests = vm.requestCount;
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
            child: Wrap(
              spacing: 6,
              children: [
                for (final (filter, label) in [
                  (InboxFilter.all, 'All messages'),
                  (InboxFilter.unread, 'Unread ($unread)'),
                  (
                    InboxFilter.requests,
                    requests == 0 ? 'Requests' : 'Requests ($requests)',
                  ),
                  (InboxFilter.archived, 'Archived'),
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
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _InboxTile(
                      item: items[i],
                      selected: items[i].key == selectedKey,
                      onTap: () => onOpen(items[i]),
                      onActions: () => _actions(items[i]),
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
    required this.onActions,
  });

  final InboxItem item;
  final bool selected;
  final VoidCallback onTap;

  /// Archive or delete it: long-press, or right-click.
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final unread = item.unread;
    final when = item.lastAt;
    return Material(
      color: selected ? c.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onActions,
        onSecondaryTap: onActions,
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
              PersonAvatar(name: item.title, radius: 18),
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

enum _InboxAction { archive, delete }
