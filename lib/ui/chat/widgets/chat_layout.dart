import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/themes/theme.dart';

/// Width at which chats show their list beside the open conversation.
const chatSplitBreakpoint = 840.0;

/// Width of the chat list beside an open conversation.
const chatListWidth = 340.0;

bool isChatSplit(BoxConstraints c) => c.maxWidth >= chatSplitBreakpoint;

/// The chat list on the left, the open conversation (or [placeholder]) on
/// the right. For wide layouts only.
class ChatSplit extends StatelessWidget {
  const ChatSplit({
    super.key,
    required this.list,
    required this.detail,
    this.placeholder = const ChatPlaceholder(),
  });

  final Widget list;
  final Widget? detail;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: chatListWidth,
          child: Material(color: c.card, child: list),
        ),
        VerticalDivider(width: 1, color: c.border),
        Expanded(child: detail ?? placeholder),
      ],
    );
  }
}

class ChatPlaceholder extends StatelessWidget {
  const ChatPlaceholder({super.key, this.text = 'Pick a chat to open it.'});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 56, color: c.muted),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: c.muted)),
        ],
      ),
    );
  }
}

/// Opens the chat panel (the Scaffold's drawer) on phones.
class ChatListButton extends StatelessWidget {
  const ChatListButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Chats',
    icon: const Icon(Icons.forum_outlined),
    onPressed: () => Scaffold.of(context).openDrawer(),
  );
}

/// The chat panel on phones: [list] under a header that leaves chat.
class ChatDrawer extends StatelessWidget {
  const ChatDrawer({
    super.key,
    required this.title,
    required this.list,
    this.onExit,
  });

  final String title;
  final Widget list;

  /// Leaves chat (e.g. back to the team). Defaults to popping the page.
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Drawer(
      width: chatListWidth,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const BackButtonIcon(),
              title: Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
              ),
              onTap: () {
                Navigator.pop(context); // close the drawer
                (onExit ?? () => context.pop())();
              },
            ),
            Divider(height: 1, color: c.border),
            Expanded(child: list),
          ],
        ),
      ),
    );
  }
}

/// Slides a chat in from the right, the way a phone opens a conversation.
CustomTransitionPage<void> chatPage(LocalKey key, Widget child) =>
    CustomTransitionPage(
      key: key,
      child: child,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        ),
        child: child,
      ),
    );
