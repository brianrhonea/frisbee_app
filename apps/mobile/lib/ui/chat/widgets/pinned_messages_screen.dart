import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/chat.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/status_views.dart';
import '../view_models/chat_room_viewmodel.dart';

/// Opens a room's pinned messages (the room's ⋯ menu, as in Discord); a
/// pin tapped there closes it and jumps to that message in the thread,
/// loading older messages as needed.
Future<void> openPinnedMessages(
  BuildContext context,
  ChatRoomViewModel vm,
) async {
  final id = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => PinnedMessagesScreen(viewModel: vm)),
  );
  if (id == null || !context.mounted) return;
  final found = await vm.jumpTo(id);
  if (!found && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          "That message is too far back to show. It's still pinned.",
        ),
      ),
    );
  }
}

/// A room's pins, newest pin first, each a card with its author, date,
/// whole text and files. Tap one to see it in the chat; chat managers
/// unpin from its ⋯.
class PinnedMessagesScreen extends StatelessWidget {
  const PinnedMessagesScreen({super.key, required this.viewModel});

  final ChatRoomViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final room = vm.room;
        final pins = vm.pins;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pinned messages'),
                if (room != null)
                  Text(
                    '#${room.handle} · ${pins.length} of $chatPinsMax',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          body: pins.isEmpty
              ? EmptyState(
                  icon: Icons.push_pin_outlined,
                  title: 'Nothing pinned yet',
                  message: vm.canPin
                      ? 'Press and hold a message and choose Pin message '
                            'to keep it here.'
                      : 'Coaches and captains pin important messages here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: pins.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => ConstrainedContent(
                    maxWidth: 720,
                    child: _PinCard(
                      key: Key('pin-${pins[i].id}'),
                      message: pins[i],
                      onOpen: () => Navigator.pop(context, pins[i].id),
                      onUnpin: vm.canPin && !vm.togglePin.running
                          ? () => vm.togglePin.execute(pins[i])
                          : null,
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _PinCard extends StatelessWidget {
  const _PinCard({
    super.key,
    required this.message,
    required this.onOpen,
    this.onUnpin,
  });

  final ChatMessage message;
  final VoidCallback onOpen;
  final VoidCallback? onUnpin;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final m = message;
    final name = m.authorName.isEmpty ? 'Member' : m.authorName;
    final sent = m.createdAt;
    final text = m.text.isNotEmpty ? m.text : m.preview;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: c.accentSoft,
                    child: Text(
                      name.characters.first.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: c.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                          if (sent != null)
                            TextSpan(
                              text:
                                  '  ${DateFormat.yMMMd().add_jm().format(sent)}',
                              style: TextStyle(fontSize: 12, color: c.muted),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onUnpin case final unpin?)
                    PopupMenuButton<void>(
                      tooltip: 'Pin options',
                      icon: Icon(Icons.more_horiz, color: c.muted),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          onTap: unpin,
                          child: const ListTile(
                            leading: Icon(Icons.push_pin_outlined),
                            title: Text('Unpin'),
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox(width: 10),
                ],
              ),
              if (text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    text,
                    maxLines: 12,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
              if (m.attachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in m.attachments) _FileChip(attachment: a),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Tap to see it in the chat',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pinned message's file: its kind and name.
class _FileChip extends StatelessWidget {
  const _FileChip({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final a = attachment;
    final icon = a.contentType.startsWith('image/')
        ? Icons.image_outlined
        : a.contentType.startsWith('video/')
        ? Icons.movie_outlined
        : a.contentType == 'application/pdf'
        ? Icons.picture_as_pdf_outlined
        : Icons.insert_drive_file_outlined;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: c.ink2),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: c.ink),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            formatFileSize(a.size),
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ],
      ),
    );
  }
}
