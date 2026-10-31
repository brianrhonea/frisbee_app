import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/chat.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/chat_list_viewmodel.dart';
import '../view_models/chat_room_viewmodel.dart';
import 'chat_layout.dart';
import 'chat_room_screen.dart';

/// Team chat. Wide screens list rooms on the left and open the picked one
/// on the right; phones list rooms and slide the picked one in full screen.
class ChatTab extends StatelessWidget {
  const ChatTab({super.key, required this.viewModel});

  final ChatListViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          if (!isChatSplit(constraints)) {
            return RoomList(
              viewModel: vm,
              onOpen: (id) => context.push(Routes.chatRoom(vm.teamId, id)),
            );
          }
          final selected = vm.selectedId;
          return ChatSplit(
            list: RoomList(
              viewModel: vm,
              selectedId: selected,
              onOpen: vm.select,
            ),
            detail: selected == null
                ? null
                : ViewModelHost(
                    key: ValueKey('chat-pane-${vm.teamId}-$selected'),
                    create: (c) => ChatRoomViewModel(
                      teamId: vm.teamId,
                      roomId: selected,
                      teamRepository: c.read(),
                      chatRepository: c.read(),
                      notificationRepository: c.read(),
                      authRepository: c.read(),
                      filePicker: c.read(),
                    ),
                    builder: (_, roomVm) => ChatRoomView(viewModel: roomVm),
                  ),
          );
        },
      ),
    );
  }
}

/// The team's rooms, with a New room button for admins. [selectedId] is
/// highlighted.
class RoomList extends StatelessWidget {
  const RoomList({
    super.key,
    required this.viewModel,
    required this.onOpen,
    this.selectedId,
  });

  final ChatListViewModel viewModel;
  final ValueChanged<String> onOpen;
  final String? selectedId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      if (!vm.loaded) return const LoadingView();
      final rooms = vm.rooms;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (vm.canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: FilledButton.tonalIcon(
                onPressed: () => context.push(Routes.newChatRoom(vm.teamId)),
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('New room'),
              ),
            ),
          Expanded(
            child: rooms.isEmpty && vm.error != null
                ? ErrorView(error: vm.error)
                : rooms.isEmpty
                ? EmptyView(
                    icon: Icons.forum_outlined,
                    title: 'No chat rooms yet',
                    message: vm.canManage
                        ? 'Start a room for the team, or one just for coaches.'
                        : "You haven't been added to any rooms yet.",
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: rooms.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _RoomTile(
                      room: rooms[i],
                      access: vm.accessTo(rooms[i]),
                      selected: rooms[i].id == selectedId,
                      onTap: () => onOpen(rooms[i].id),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.access,
    required this.selected,
    required this.onTap,
  });

  final ChatRoom room;
  final ChatAccess access;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (icon, note) = switch (access) {
      ChatAccess.write => (Icons.forum_outlined, null),
      ChatAccess.read => (Icons.visibility_outlined, 'Read only'),
      // Admins see rooms they aren't in so they can manage access.
      ChatAccess.none => (Icons.lock_outline, 'Not a member'),
    };
    return Material(
      color: selected ? c.accentSoft : c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? c.accent : c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        selected: selected,
        leading: CircleAvatar(
          backgroundColor: selected ? c.card : c.accentSoft,
          foregroundColor: c.accent,
          child: Icon(icon),
        ),
        title: Text(
          room.name,
          style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
        ),
        subtitle: Text(
          [room.audience, ?note].join(' · '),
          style: TextStyle(color: c.muted),
        ),
        trailing: selected ? null : Icon(Icons.chevron_right, color: c.muted),
      ),
    );
  }
}
