import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../routing/routes.dart';
import '../../chat/widgets/chat_layout.dart';
import '../../chat/widgets/message_thread_view.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart' show PersonAvatar;
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/direct_chat_viewmodel.dart';
import '../view_models/inbox_viewmodel.dart';
import 'inbox_screen.dart';

/// A conversation opened as its own page. Phones show it full screen with
/// a back arrow to Messages, which is right underneath, like any phone's
/// messages app; wide windows show the conversation list beside it.
class DirectChatScreen extends StatelessWidget {
  const DirectChatScreen({super.key, required this.viewModel});

  final DirectChatViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!isChatSplit(constraints)) {
          // Opened from a link, there's no list underneath: back goes to it.
          return DirectChatView(
            viewModel: vm,
            leading: backOr(context, Routes.messages),
            onLeave: () => context.go(Routes.messages),
          );
        }
        return ViewModelHost(
          create: (c) => InboxViewModel(
            directMessageRepository: c.read(),
            authRepository: c.read(),
          ),
          builder: (context, inbox) => Scaffold(
            appBar: AppBar(title: const Text('Messages')),
            body: ChatSplit(
              list: InboxList(
                viewModel: inbox,
                selectedKey: 'dm:${vm.conversationId}',
                // Switching conversations replaces this page, so back
                // still leaves.
                onOpen: (item) {
                  final id = item.conversation.id;
                  if (id != vm.conversationId) {
                    context.pushReplacement(Routes.conversation(id));
                  }
                },
              ),
              detail: DirectChatView(
                viewModel: vm,
                onLeave: () => context.go(Routes.messages),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A conversation's header and messages. [leading] replaces the back
/// button; [drawer] is a panel it can open; [onLeave] runs once the
/// conversation is deleted or declined (beside the inbox, the list moves
/// on by itself).
class DirectChatView extends StatefulWidget {
  const DirectChatView({
    super.key,
    required this.viewModel,
    this.leading,
    this.drawer,
    this.onLeave,
  });

  final DirectChatViewModel viewModel;
  final Widget? leading;
  final Widget? drawer;
  final VoidCallback? onLeave;

  @override
  State<DirectChatView> createState() => _DirectChatViewState();
}

class _DirectChatViewState extends State<DirectChatView> {
  DirectChatViewModel get vm => widget.viewModel;

  late final _commands = [vm.accept, vm.decline, vm.toggleArchived, vm.clear];

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
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
    if (vm.decline.completed || vm.clear.completed) {
      final declined = vm.decline.completed;
      vm.decline.clearResult();
      vm.clear.clearResult();
      showSnackBar(
        context,
        declined ? 'Request deleted.' : 'Conversation deleted.',
      );
      widget.onLeave?.call();
    }
    if (vm.toggleArchived.completed) {
      vm.toggleArchived.clearResult();
      showSnackBar(
        context,
        vm.isArchived ? 'Moved to Archived.' : 'Moved back to your inbox.',
      );
    }
  }

  Future<void> _confirmClear() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete conversation?',
      message:
          'Its messages are removed for you only; ${vm.otherName} still has '
          'them. New messages will bring it back.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) vm.clear.execute();
  }

  Future<void> _confirmDecline() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete request?',
      message: "${vm.otherName} won't be told, and won't know you've seen it.",
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) vm.decline.execute();
  }

  @override
  Widget build(BuildContext context) {
    final leading = widget.leading;
    final drawer = widget.drawer;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final Widget body;
        if (!vm.loaded) {
          body = const LoadingView();
        } else if (vm.conversation == null) {
          body = vm.error != null
              ? ErrorView(error: vm.error)
              : const EmptyView(
                  icon: Icons.chat_bubble_outline,
                  title: 'Conversation not available',
                );
        } else {
          body = SafeArea(
            top: false,
            child: MessageThreadView(
              viewModel: vm,
              emptyMessage: 'Only the two of you can see these messages.',
              footer: vm.isRequest
                  ? _RequestBar(
                      name: vm.otherName,
                      busy: vm.accept.running || vm.decline.running,
                      onAccept: vm.accept.execute,
                      onDelete: _confirmDecline,
                    )
                  : null,
            ),
          );
        }
        return Scaffold(
          drawer: drawer,
          appBar: ChatHeaderBar(
            leading: leading,
            avatar: vm.conversation == null
                ? null
                : PersonAvatar(name: vm.otherName, radius: 18),
            title: vm.conversation == null ? null : vm.otherName,
            subtitle: vm.conversation == null
                ? null
                : vm.isRequest
                ? 'Message request'
                : vm.isPending
                ? 'Request sent'
                : switch (vm.otherUsername) {
                    final handle? => '@$handle',
                    null => 'Direct message',
                  },
            actions: [
              if (vm.conversation != null && !vm.isRequest)
                PopupMenuButton<_ChatAction>(
                  tooltip: 'Conversation options',
                  onSelected: (a) => switch (a) {
                    _ChatAction.archive => vm.toggleArchived.execute(),
                    _ChatAction.delete => _confirmClear(),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _ChatAction.archive,
                      child: ListTile(
                        leading: Icon(
                          vm.isArchived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                        ),
                        title: Text(vm.isArchived ? 'Unarchive' : 'Archive'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _ChatAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete conversation'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          body: body,
        );
      },
    );
  }
}

enum _ChatAction { archive, delete }

/// Under a message request: what accepting means, and the choice.
class _RequestBar extends StatelessWidget {
  const _RequestBar({
    required this.name,
    required this.busy,
    required this.onAccept,
    required this.onDelete,
  });

  final String name;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$name wants to message you',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            "They won't know you've seen this unless you accept. Accept to "
            'reply and move it to your inbox.',
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDelete,
                  child: const Text('Delete'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
