import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/services/meeting_call.dart';
import '../../../domain/models/chat.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/chat_list_viewmodel.dart';
import '../view_models/chat_room_viewmodel.dart';
import 'chat_layout.dart';
import 'chat_room_screen.dart';
import 'chat_room_settings_screen.dart';

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

/// The team's rooms in their folders, Discord style: compact # and voice
/// rows under collapsible folder names. Chat managers drag rooms and
/// folders to rearrange them (press and hold on phones). Whoever's in a
/// voice channel with the user shows under it, and a bar at the bottom
/// keeps voice controls in reach. [selectedId] is highlighted.
class RoomList extends StatefulWidget {
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
  State<RoomList> createState() => _RoomListState();
}

class _RoomListState extends State<RoomList> {
  /// What's being dragged, so drop zones can show.
  Object? _dragging;

  void _dragStarted(Object item) => setState(() => _dragging = item);
  void _dragEnded() => setState(() => _dragging = null);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel,
    builder: (context, _) {
      final vm = widget.viewModel;
      if (!vm.loaded) return const LoadingView();
      final groups = vm.groups;
      final hasUnfiled = groups.isNotEmpty && groups.first.folder == null;
      final drag = _DragHooks(
        enabled: vm.canManage,
        onStart: _dragStarted,
        onEnd: _dragEnded,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (vm.canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          context.push(Routes.newChatRoom(vm.teamId)),
                      icon: const Icon(Icons.add),
                      label: const Text('New channel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'New folder',
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: () => _editFolder(context, vm, null),
                  ),
                ],
              ),
            ),
          Expanded(
            child: groups.isEmpty && vm.error != null
                ? ErrorView(error: vm.error)
                : groups.isEmpty
                ? EmptyView(
                    icon: Icons.forum_outlined,
                    title: 'No channels yet',
                    message: vm.canManage
                        ? 'Start a channel for everyone, or one just for a role.'
                        : "You haven't been added to any channels yet.",
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                    children: [
                      // Somewhere to drop a room to take it out of its
                      // folder, when no room is outside one.
                      if (!hasUnfiled && _dragging is ChatRoom)
                        _UnfiledDropZone(viewModel: vm),
                      for (final g in groups) ...[
                        if (g.folder case final folder?)
                          _FolderHeader(
                            viewModel: vm,
                            folder: folder,
                            index: vm.folders.indexWhere(
                              (f) => f.id == folder.id,
                            ),
                            drag: drag,
                          ),
                        if (g.folder == null || !vm.isCollapsed(g.folder!.id))
                          for (final (i, room) in g.rooms.indexed) ...[
                            _RoomDropTarget(
                              viewModel: vm,
                              folderId: g.folder?.id,
                              index: i,
                              siblings: g.rooms,
                              child: _RoomRow(
                                room: room,
                                access: vm.accessTo(room),
                                audience: vm.audienceOf(room),
                                selected: room.id == widget.selectedId,
                                onTap: () => widget.onOpen(room.id),
                                drag: drag,
                                menu: vm.canManage
                                    ? _RoomMenu(
                                        viewModel: vm,
                                        room: room,
                                        first: i == 0,
                                        last: i == g.rooms.length - 1,
                                      )
                                    : null,
                              ),
                            ),
                            if (room.isVoice)
                              for (final p in vm.voiceParticipants(room))
                                _VoiceMember(p: p),
                          ],
                      ],
                    ],
                  ),
          ),
          if (vm.voiceChannel case final channel?)
            _VoiceBar(
              viewModel: vm,
              onOpen: channel.teamId == vm.teamId
                  ? () => widget.onOpen(channel.roomId)
                  : null,
            ),
        ],
      );
    },
  );
}

/// How rows start and end drags, for chat managers.
class _DragHooks {
  const _DragHooks({
    required this.enabled,
    required this.onStart,
    required this.onEnd,
  });

  final bool enabled;
  final ValueChanged<Object> onStart;
  final VoidCallback onEnd;

  /// Phones drag after a press and hold, so a swipe still scrolls; mice
  /// drag straight away.
  static bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Widget wrap<T extends Object>({
    required T data,
    required Widget child,
    required Widget feedback,
  }) {
    if (!enabled) return child;
    final dimmed = Opacity(opacity: 0.35, child: child);
    final lifted = Material(
      color: Colors.transparent,
      child: SizedBox(width: 260, child: feedback),
    );
    return _touch
        ? LongPressDraggable<T>(
            data: data,
            feedback: lifted,
            childWhenDragging: dimmed,
            onDragStarted: () => onStart(data),
            onDragEnd: (_) => onEnd(),
            child: child,
          )
        : Draggable<T>(
            data: data,
            feedback: lifted,
            childWhenDragging: dimmed,
            onDragStarted: () => onStart(data),
            onDragEnd: (_) => onEnd(),
            child: child,
          );
  }
}

/// A room being dragged over this one goes where this one is: before it
/// when coming from above or from elsewhere, after it when moving down.
class _RoomDropTarget extends StatelessWidget {
  const _RoomDropTarget({
    required this.viewModel,
    required this.folderId,
    required this.index,
    required this.siblings,
    required this.child,
  });

  final ChatListViewModel viewModel;
  final String? folderId;
  final int index;
  final List<ChatRoom> siblings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DragTarget<ChatRoom>(
      onWillAcceptWithDetails: (d) => d.data.id != siblings[index].id,
      onAcceptWithDetails: (d) => viewModel.placeRoom.execute((
        roomId: d.data.id,
        folderId: folderId,
        index: index,
      )),
      builder: (context, candidates, _) {
        final dragged = candidates.firstOrNull;
        if (dragged == null) return child;
        final from = siblings.indexWhere((r) => r.id == dragged.id);
        final below = from >= 0 && from < index;
        final line = Container(height: 2, color: c.accent);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [if (!below) line, child, if (below) line],
        );
      },
    );
  }
}

/// Shown while dragging a room when every room is in a folder.
class _UnfiledDropZone extends StatelessWidget {
  const _UnfiledDropZone({required this.viewModel});

  final ChatListViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DragTarget<ChatRoom>(
      onAcceptWithDetails: (d) => viewModel.placeRoom.execute((
        roomId: d.data.id,
        folderId: null,
        index: 0,
      )),
      builder: (context, candidates, _) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: candidates.isEmpty ? null : c.accentSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.accent),
        ),
        child: Text(
          'Drop here to take it out of its folder',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: c.accent),
        ),
      ),
    );
  }
}

/// Creates a folder ([folder] null) or edits one, then saves it.
Future<void> _editFolder(
  BuildContext context,
  ChatListViewModel vm,
  ChatFolder? folder,
) async {
  final edited = await showDialog<ChatFolder>(
    context: context,
    builder: (_) => _FolderDialog(
      folder: folder ?? const ChatFolder(id: '', name: ''),
      audiences: vm.audiences,
      label: vm.audienceLabel,
    ),
  );
  if (edited != null) await vm.saveFolder.execute(edited);
}

enum _FolderAction { newRoom, edit, up, down, delete }

/// A folder's name, like a Discord category: tap to collapse. Chat
/// managers drag it to reorder folders, drop rooms on it to move them in,
/// and get a menu.
class _FolderHeader extends StatelessWidget {
  const _FolderHeader({
    required this.viewModel,
    required this.folder,
    required this.index,
    required this.drag,
  });

  final ChatListViewModel viewModel;
  final ChatFolder folder;
  final int index;
  final _DragHooks drag;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final collapsed = vm.isCollapsed(folder.id);
    final first = index == 0;
    final last = index == vm.folders.length - 1;
    Widget label({bool lifted = false}) => Row(
      children: [
        Icon(
          collapsed ? Icons.chevron_right : Icons.expand_more,
          size: 16,
          color: c.muted,
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Text(
            folder.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: lifted ? c.ink : c.muted,
            ),
          ),
        ),
      ],
    );
    final header = Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: drag.wrap<ChatFolder>(
              data: folder,
              feedback: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(blurRadius: 8, color: Colors.black26),
                  ],
                ),
                child: label(lifted: true),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => vm.toggleFolder(folder.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: label(),
                ),
              ),
            ),
          ),
          if (vm.canManage) ...[
            IconButton(
              tooltip: 'New channel in ${folder.name}',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: c.muted,
              icon: const Icon(Icons.add),
              onPressed: () => context.push(
                Routes.newChatRoom(vm.teamId, folderId: folder.id),
              ),
            ),
            PopupMenuButton<_FolderAction>(
              tooltip: 'Folder options',
              iconSize: 18,
              icon: Icon(Icons.more_horiz, color: c.muted),
              onSelected: (a) async {
                switch (a) {
                  case _FolderAction.newRoom:
                    context.push(
                      Routes.newChatRoom(vm.teamId, folderId: folder.id),
                    );
                  case _FolderAction.edit:
                    await _editFolder(context, vm, folder);
                  case _FolderAction.up:
                    vm.shiftFolder.execute((id: folder.id, by: -1));
                  case _FolderAction.down:
                    vm.shiftFolder.execute((id: folder.id, by: 1));
                  case _FolderAction.delete:
                    if (await confirmDialog(
                      context,
                      title: 'Delete ${folder.name}?',
                      message:
                          'Its channels stay, outside any folder, with their '
                          'messages.',
                      confirmLabel: 'Delete folder',
                      destructive: true,
                    )) {
                      vm.deleteFolder.execute(folder.id);
                    }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _FolderAction.newRoom,
                  child: Text('New channel here'),
                ),
                const PopupMenuItem(
                  value: _FolderAction.edit,
                  child: Text('Edit folder'),
                ),
                if (!first)
                  const PopupMenuItem(
                    value: _FolderAction.up,
                    child: Text('Move up'),
                  ),
                if (!last)
                  const PopupMenuItem(
                    value: _FolderAction.down,
                    child: Text('Move down'),
                  ),
                const PopupMenuItem(
                  value: _FolderAction.delete,
                  child: Text('Delete folder'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    if (!vm.canManage) return header;
    // Rooms dropped here go to the top of the folder; folders dropped
    // here take this one's place.
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) =>
          d.data is ChatRoom ||
          (d.data is ChatFolder && (d.data as ChatFolder).id != folder.id),
      onAcceptWithDetails: (d) => switch (d.data) {
        final ChatRoom room => vm.placeRoom.execute((
          roomId: room.id,
          folderId: folder.id,
          index: 0,
        )),
        final ChatFolder f => vm.placeFolder.execute((
          folderId: f.id,
          index: index,
        )),
        _ => null,
      },
      builder: (context, candidates, _) => candidates.isEmpty
          ? header
          : DecoratedBox(
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: header,
            ),
    );
  }
}

/// Moves a room between folders or up and down, for chat managers who'd
/// rather not drag.
class _RoomMenu extends StatelessWidget {
  const _RoomMenu({
    required this.viewModel,
    required this.room,
    required this.first,
    required this.last,
  });

  final ChatListViewModel viewModel;
  final ChatRoom room;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return PopupMenuButton<String>(
      tooltip: 'Channel options',
      iconSize: 18,
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz, color: AppColors.of(context).muted),
      onSelected: (a) async {
        switch (a) {
          case 'settings':
            context.push(Routes.chatRoomSettings(vm.teamId, room.id));
          case 'up':
            vm.shiftRoom.execute((id: room.id, by: -1));
          case 'down':
            vm.shiftRoom.execute((id: room.id, by: 1));
          case 'move':
            final picked = await showDialog<({String? id})>(
              context: context,
              builder: (context) => SimpleDialog(
                title: Text('Move ${room.name} to'),
                children: [
                  for (final f in [null, ...vm.folders])
                    ListTile(
                      leading: Icon(
                        f?.id == room.folderId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(f?.name ?? 'No folder'),
                      onTap: () => Navigator.pop(context, (id: f?.id)),
                    ),
                ],
              ),
            );
            if (picked != null && picked.id != room.folderId) {
              vm.moveRoom.execute((room: room, folderId: picked.id));
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'settings', child: Text('Edit channel')),
        if (!first) const PopupMenuItem(value: 'up', child: Text('Move up')),
        if (!last) const PopupMenuItem(value: 'down', child: Text('Move down')),
        if (vm.folders.isNotEmpty)
          const PopupMenuItem(value: 'move', child: Text('Move to folder')),
      ],
    );
  }
}

/// A channel: # for text, a speaker for voice, a lock when the member
/// isn't in it (chat managers see those too).
class _RoomRow extends StatefulWidget {
  const _RoomRow({
    required this.room,
    required this.access,
    required this.audience,
    required this.selected,
    required this.onTap,
    required this.drag,
    this.menu,
  });

  final ChatRoom room;
  final ChatAccess access;
  final String audience;
  final bool selected;
  final VoidCallback onTap;
  final _DragHooks drag;
  final Widget? menu;

  @override
  State<_RoomRow> createState() => _RoomRowState();
}

class _RoomRowState extends State<_RoomRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final room = widget.room;
    final icon = switch (widget.access) {
      ChatAccess.none => Icons.lock_outline,
      _ when room.isVoice => Icons.volume_up_rounded,
      _ => Icons.tag,
    };
    final color = widget.selected || _hover ? c.ink : c.muted;
    Widget row({bool lifted = false}) => Row(
      children: [
        Icon(icon, size: 20, color: lifted ? c.ink : color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            room.isVoice ? room.name : room.handle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              color: lifted ? c.ink : color,
            ),
          ),
        ),
        if (!lifted && widget.access == ChatAccess.read && !room.isVoice)
          Tooltip(
            message: 'Read only',
            child: Icon(Icons.visibility_outlined, size: 15, color: c.muted),
          ),
      ],
    );
    final showMenu =
        widget.menu != null && (_hover || widget.selected || _DragHooks._touch);
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: widget.audience,
        waitDuration: const Duration(milliseconds: 800),
        child: Material(
          color: widget.selected
              ? c.accentSoft
              : _hover
              ? c.ink.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: SizedBox(
              height: 38,
              child: Padding(
                padding: EdgeInsets.only(left: 8, right: showMenu ? 0 : 8),
                child: Row(
                  children: [
                    Expanded(child: row()),
                    if (showMenu) widget.menu!,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: widget.drag.wrap<ChatRoom>(
        data: room,
        feedback: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
          ),
          child: row(lifted: true),
        ),
        child: tile,
      ),
    );
  }
}

/// Someone in a voice channel with the user, under the channel's row.
class _VoiceMember extends StatelessWidget {
  const _VoiceMember({required this.p});

  final CallParticipant p;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 1, 8, 3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: p.isSpeaking
                    ? Colors.green.shade500
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: PersonAvatar(name: p.name, photoUrl: p.photoUrl, radius: 10),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
          if (!p.micOn) Icon(Icons.mic_off, size: 14, color: c.muted),
        ],
      ),
    );
  }
}

/// "Voice Connected" with mute and disconnect, under the room list while
/// the user is in a voice channel.
class _VoiceBar extends StatelessWidget {
  const _VoiceBar({required this.viewModel, required this.onOpen});

  final ChatListViewModel viewModel;

  /// Opens the channel; null when it's on another team.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final channel = vm.voiceChannel!;
    final status = vm.voiceConnected ? 'Voice Connected' : 'Connecting…';
    final statusColor = vm.voiceConnected
        ? Colors.green.shade600
        : Colors.orange.shade700;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          Icon(Icons.network_cell_rounded, size: 18, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                  Text(
                    [
                      channel.name,
                      if (channel.teamName.isNotEmpty) channel.teamName,
                    ].join(' / '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: !vm.canSpeak
                ? 'You can only listen here'
                : vm.micOn
                ? 'Mute'
                : 'Unmute',
            icon: Icon(
              vm.micOn ? Icons.mic : Icons.mic_off,
              color: vm.micOn ? c.ink : Colors.red.shade400,
            ),
            onPressed: vm.voiceConnected && vm.canSpeak
                ? vm.toggleMic.execute
                : null,
          ),
          IconButton(
            tooltip: 'Disconnect',
            icon: Icon(Icons.call_end, color: Colors.red.shade400),
            onPressed: vm.leaveVoice.execute,
          ),
        ],
      ),
    );
  }
}

/// A folder's name and the access new rooms in it start with.
class _FolderDialog extends StatefulWidget {
  const _FolderDialog({
    required this.folder,
    required this.audiences,
    required this.label,
  });

  final ChatFolder folder;
  final List<String> audiences;
  final String Function(String) label;

  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  late ChatFolder _draft = widget.folder;
  late final _name = TextEditingController(text: widget.folder.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      title: Text(widget.folder.isNew ? 'New folder' : 'Edit folder'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: ChatFolder.maxNameLength,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Folder name',
                  hintText: 'e.g. Tournaments, Coaching',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text(
                'New rooms in this folder start with this access; each '
                'room can change its own.',
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
              for (final id in widget.audiences)
                ChatAccessRow(
                  title: widget.label(id),
                  value: _draft.roleAccess(id),
                  onChanged: (a) =>
                      setState(() => _draft = _draft.withRoleAccess(id, a)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  _draft.copyWith(name: _name.text.trim()),
                ),
          child: Text(widget.folder.isNew ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
