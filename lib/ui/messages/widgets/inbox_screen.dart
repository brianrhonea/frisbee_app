import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/direct_message.dart';
import '../../../routing/routes.dart';
import '../../chat/widgets/chat_layout.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/direct_chat_viewmodel.dart';
import '../view_models/inbox_viewmodel.dart';
import 'direct_chat_screen.dart';
import '../../core/ui/person_avatar.dart';

export '../../core/ui/person_avatar.dart';

/// Direct messages. Wide screens list conversations on the left and open
/// the picked one on the right; phones list them and slide the picked one
/// in full screen.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, required this.viewModel});

  final InboxViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            if (!isChatSplit(constraints)) {
              return ConversationList(
                viewModel: vm,
                onOpen: (id) => context.push(Routes.conversation(id)),
              );
            }
            final selected = vm.selectedId;
            return ChatSplit(
              list: ConversationList(
                viewModel: vm,
                selectedId: selected,
                onOpen: vm.select,
              ),
              placeholder: const ChatPlaceholder(
                text: 'Pick a conversation, or start a new one.',
              ),
              detail: selected == null
                  ? null
                  : ViewModelHost(
                      key: ValueKey('dm-pane-$selected'),
                      create: (c) => DirectChatViewModel(
                        conversationId: selected,
                        directMessageRepository: c.read(),
                        authRepository: c.read(),
                        filePicker: c.read(),
                      ),
                      builder: (_, dmVm) => DirectChatView(viewModel: dmVm),
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// The user's conversations with a New message button; [selectedId] is
/// highlighted.
class ConversationList extends StatelessWidget {
  const ConversationList({
    super.key,
    required this.viewModel,
    required this.onOpen,
    this.selectedId,
  });

  final InboxViewModel viewModel;
  final ValueChanged<String> onOpen;
  final String? selectedId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      if (!vm.loaded) return const LoadingView();
      final list = vm.conversations;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: FilledButton.tonalIcon(
              onPressed: () => context.push(Routes.newMessage),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('New message'),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? vm.error != null
                      ? ErrorView(error: vm.error)
                      : const EmptyView(
                          icon: Icons.chat_bubble_outline,
                          title: 'No messages yet',
                          message:
                              'Message anyone on UltiUP privately. Tap New '
                              'message and search by name.',
                        )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _ConversationTile(
                      conversation: list[i],
                      uid: vm.uid,
                      unread: vm.isUnread(list[i]),
                      selected: list[i].id == selectedId,
                      onTap: () => onOpen(list[i].id),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.uid,
    required this.unread,
    required this.selected,
    required this.onTap,
  });

  final Conversation conversation;
  final String uid;
  final bool unread;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final conv = conversation;
    final name = conv.otherName(uid);
    final mine = conv.lastSenderId == uid;
    final weight = unread ? FontWeight.w700 : FontWeight.w400;
    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: c.accentSoft,
      leading: PersonAvatar(name: name),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
          color: c.ink,
        ),
      ),
      subtitle: Text(
        '${mine ? 'You: ' : ''}${conv.lastMessage}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: unread ? c.ink : c.muted, fontWeight: weight),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _when(conv.lastMessageAt!),
            style: TextStyle(fontSize: 12, color: unread ? c.accent : c.muted),
          ),
          if (unread) ...[
            const SizedBox(height: 4),
            Icon(Icons.circle, size: 10, color: c.accent),
          ],
        ],
      ),
    );
  }

  static String _when(DateTime d) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(d, now)) return DateFormat.jm().format(d);
    if (now.difference(d).inDays < 7) return DateFormat.E().format(d);
    return DateFormat.MMMd().format(d);
  }
}
