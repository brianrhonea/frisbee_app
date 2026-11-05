import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../routing/routes.dart';
import '../../chat/widgets/chat_layout.dart';
import '../../chat/widgets/message_thread_view.dart';
import '../../core/ui/back_or.dart';
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
              detail: DirectChatView(viewModel: vm),
            ),
          ),
        );
      },
    );
  }
}

/// A conversation's header and messages. [leading] replaces the back
/// button; [drawer] is a panel it can open.
class DirectChatView extends StatelessWidget {
  const DirectChatView({
    super.key,
    required this.viewModel,
    this.leading,
    this.drawer,
  });

  final DirectChatViewModel viewModel;
  final Widget? leading;
  final Widget? drawer;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
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
            subtitle: vm.conversation == null ? null : 'Direct message',
          ),
          body: body,
        );
      },
    );
  }
}
