import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/chat.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/chat_list_viewmodel.dart';
import '../view_models/chat_room_viewmodel.dart';
import '../view_models/voice_channel_viewmodel.dart';
import 'chat_extras.dart';
import 'chat_polls.dart';
import 'chat_layout.dart';
import 'chat_tab.dart';
import 'message_thread_view.dart';
import 'voice_channel_view.dart';
import '../../../domain/models/moderation.dart';

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
        voiceRepository: c.read(),
        notificationRepository: c.read(),
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
        final team = vm.team;
        final count = team?.members.length ?? 0;
        final readable = room != null && vm.access.canRead;
        final bar = ChatHeaderBar(
          leading: leading,
          avatar: readable
              ? TeamBadge(size: 36, community: team?.isCommunity ?? false)
              : null,
          title: readable
              ? [
                  ?team?.name,
                  room.isGeneral
                      ? ((team?.isCommunity ?? false)
                            ? 'Community chat'
                            : 'Team chat')
                      : room.name,
                ].join(' · ')
              : null,
          subtitle: readable
              ? [
                  if (room.isVoice)
                    'Voice channel'
                  else if (count > 0)
                    '$count ${count == 1 ? 'member' : 'members'}',
                  if (team != null) room.audienceOn(team),
                ].join(' · ')
              : null,
          actions: [
            if ((readable && !room.isVoice) || (room != null && vm.canManage))
              PopupMenuButton<_RoomAction>(
                tooltip: 'Room options',
                icon: Icon(
                  vm.muted ? Icons.notifications_off_outlined : Icons.more_vert,
                ),
                onSelected: (a) => switch (a) {
                  _RoomAction.mute => vm.toggleMuted.execute(),
                  _RoomAction.settings => openSettings(),
                },
                itemBuilder: (_) => [
                  if (readable && !room.isVoice)
                    PopupMenuItem(
                      value: _RoomAction.mute,
                      enabled: !vm.toggleMuted.running,
                      child: ListTile(
                        leading: Icon(
                          vm.muted
                              ? Icons.notifications_outlined
                              : Icons.notifications_off_outlined,
                        ),
                        title: Text(
                          vm.muted
                              ? 'Unmute notifications'
                              : 'Mute notifications',
                        ),
                      ),
                    ),
                  if (vm.canManage)
                    const PopupMenuItem(
                      value: _RoomAction.settings,
                      child: ListTile(
                        leading: Icon(Icons.tune),
                        title: Text('Room settings'),
                      ),
                    ),
                ],
              ),
            const SizedBox(width: 4),
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
        } else if (room.isVoice) {
          body = SafeArea(
            top: false,
            child: ViewModelHost(
              key: ValueKey('voice-${vm.teamId}-${vm.roomId}'),
              create: (c) => VoiceChannelViewModel(
                teamId: vm.teamId,
                roomId: vm.roomId,
                teamRepository: c.read(),
                chatRepository: c.read(),
                voiceRepository: c.read(),
                authRepository: c.read(),
              ),
              builder: (_, voiceVm) => VoiceChannelView(viewModel: voiceVm),
            ),
          );
        } else {
          body = SafeArea(
            top: false,
            child: _RoomThread(viewModel: vm, handle: room.handle),
          );
        }
        return Scaffold(appBar: bar, drawer: drawer, body: body);
      },
    );
  }
}

enum _RoomAction { mute, settings }

/// A text room's thread, with its pins (redesign F2), event cards (F3) and
/// polls (F33): the pinned strip on top, Pin in each message's long-press
/// sheet for chat managers, and Share an event and Poll in the attach menu.
class _RoomThread extends StatefulWidget {
  const _RoomThread({required this.viewModel, required this.handle});

  final ChatRoomViewModel viewModel;
  final String handle;

  @override
  State<_RoomThread> createState() => _RoomThreadState();
}

class _RoomThreadState extends State<_RoomThread> {
  ChatRoomViewModel get vm => widget.viewModel;

  late final List<Command<void>> _commands = [
    vm.togglePin,
    vm.replacePin,
    vm.shareEvent,
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
    super.dispose();
  }

  void _onCommand() {
    for (final c in _commands) {
      if (c.result case Error(:final error)) {
        c.clearResult();
        if (error is PinsFullException) {
          showReplacePinSheet(context, vm, error.message);
        } else {
          showErrorSnackBar(context, error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => MessageThreadView(
    viewModel: vm,
    emptyMessage: 'Say hello to the team.',
    readOnlyNotice: 'You can read this room but not post in it.',
    hintText: 'Message #${widget.handle}',
    header: PinnedStrip(viewModel: vm),
    isPinned: vm.isPinned,
    eventCard: (_, ChatEventRef e) => ChatEventCard(teamId: vm.teamId, ref: e),
    pollCard: (m, _) => ChatPollCard(room: vm, message: m),
    onTogglePin: vm.canPin ? vm.togglePin.execute : null,
    onShareEvent: vm.canShareEvents
        ? () => showShareEventSheet(context, vm)
        : null,
    onCreatePoll: vm.canPoll ? () => showCreatePollSheet(context, vm) : null,
    // Team chat between people who blocked each other still shows (the
    // team is shared), but can be reported to the team's admins and staff.
    reportTarget: (m) => TeamMessageReport(vm.teamId, vm.roomId, m.id),
  );
}
