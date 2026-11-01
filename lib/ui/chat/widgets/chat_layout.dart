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

/// The bar above an open conversation: [avatar], [title] over [subtitle],
/// and [actions], on the card color with a line below.
class ChatHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatHeaderBar({
    super.key,
    this.leading,
    this.avatar,
    this.title,
    this.subtitle,
    this.actions = const [],
  });

  final Widget? leading;
  final Widget? avatar;
  final String? title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = title;
    final canPop = Navigator.canPop(context);
    return AppBar(
      automaticallyImplyLeading: leading == null && canPop,
      leading: leading,
      toolbarHeight: 64,
      backgroundColor: c.card,
      titleSpacing: leading == null && !canPop ? 16 : 0,
      shape: Border(bottom: BorderSide(color: c.border)),
      title: t == null
          ? null
          : Row(
              children: [
                if (avatar != null) ...[avatar!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: c.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
      actions: actions,
    );
  }
}
