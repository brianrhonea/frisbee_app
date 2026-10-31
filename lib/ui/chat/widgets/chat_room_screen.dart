import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../routing/routes.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/chat_list_viewmodel.dart';
import '../view_models/chat_room_viewmodel.dart';
import 'chat_layout.dart';
import 'chat_tab.dart';
import 'message_thread_view.dart';

/// A team chat room opened as its own page. Phones show it full screen
/// with the chat panel (the room list) behind the top-left Chats button;
/// wide windows show the room list beside it.
class ChatRoomScreen extends StatelessWidget {
  const ChatRoomScreen({super.key, required this.viewModel});

  final ChatRoomViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ViewModelHost(
      create: (c) => ChatListViewModel(
        teamId: vm.teamId,
        teamRepository: c.read(),
        chatRepository: c.read(),
        authRepository: c.read(),
      ),
      builder: (context, listVm) {
        // Switching rooms replaces this page, so back still leaves chat.
        void open(String id) {
          if (id != vm.roomId) {
            context.pushReplacement(Routes.chatRoom(vm.teamId, id));
          }
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            if (isChatSplit(constraints)) {
              return Scaffold(
                appBar: AppBar(
                  title: ListenableBuilder(
                    listenable: listVm,
                    builder: (_, _) => Text(listVm.team?.name ?? 'Chat'),
                  ),
                ),
                body: ChatSplit(
                  list: RoomList(
                    viewModel: listVm,
                    selectedId: vm.roomId,
                    onOpen: open,
                  ),
                  detail: ChatRoomView(viewModel: vm),
                ),
              );
            }
            return ChatRoomView(
              viewModel: vm,
              leading: const ChatListButton(),
              drawer: ListenableBuilder(
                listenable: listVm,
                builder: (context, _) => ChatDrawer(
                  title: listVm.team?.name ?? 'Team',
                  list: RoomList(
                    viewModel: listVm,
                    selectedId: vm.roomId,
                    onOpen: (id) {
                      Navigator.pop(context); // close the panel
                      open(id);
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// A room's header and messages. [leading] replaces the back button, for
/// the phone's Chats button; [drawer] is the chat panel it opens.
class ChatRoomView extends StatelessWidget {
  const ChatRoomView({
    super.key,
    required this.viewModel,
    this.leading,
    this.drawer,
  });

  final ChatRoomViewModel viewModel;
  final Widget? leading;
  final Widget? drawer;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final room = vm.room;
        void openSettings() =>
            context.push(Routes.chatRoomSettings(vm.teamId, vm.roomId));
        final bar = AppBar(
          automaticallyImplyLeading: false,
          leading: leading,
          title: room == null || !vm.access.canRead
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(room.name),
                    Text(
                      room.audience,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
          actions: [
            if (room != null && vm.canManage)
              IconButton(
                tooltip: 'Room settings',
                icon: const Icon(Icons.tune),
                onPressed: openSettings,
              ),
          ],
        );
        final Widget body;
        if (!vm.loaded) {
          body = const LoadingView();
        } else if (room == null || !vm.access.canRead) {
          body = room == null && vm.error != null
              ? ErrorView(error: vm.error)
              : EmptyView(
                  icon: Icons.lock_outline,
                  title: room == null
                      ? 'Room not available'
                      : "You're not in this room",
                  message: room == null
                      ? 'It may have been deleted.'
                      : vm.canManage
                      ? 'Give yourself access in the room settings.'
                      : 'Ask a coach or captain for access.',
                  action: room != null && vm.canManage
                      ? FilledButton.tonal(
                          onPressed: openSettings,
                          child: const Text('Room settings'),
                        )
                      : null,
                );
        } else {
          body = SafeArea(
            top: false,
            child: MessageThreadView(
              viewModel: vm,
              emptyMessage: 'Say hello to the team.',
              readOnlyNotice: 'You can read this room but not post in it.',
            ),
          );
        }
        return Scaffold(appBar: bar, drawer: drawer, body: body);
      },
    );
  }
}
