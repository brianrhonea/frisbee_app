import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/notification.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/disc_icon.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/notifications_viewmodel.dart';
import '../../../routing/open_link.dart';

IconData categoryIcon(NotificationCategory c) => switch (c) {
  NotificationCategory.chat => Icons.forum_outlined,
  NotificationCategory.directMessages => Icons.chat_bubble_outline,
  NotificationCategory.eventChanges => Icons.event_outlined,
  NotificationCategory.eventReminders => Icons.alarm,
  NotificationCategory.teamActivity => Icons.sports_outlined,
  NotificationCategory.meetings => Icons.videocam_outlined,
  NotificationCategory.posts => Icons.dynamic_feed_outlined,
  NotificationCategory.social => Icons.favorite_border,
};

/// The in-app feed: everything the Cloud Functions sent, including what
/// went out as push. Tapping an entry marks it read and opens it.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.viewModel});

  final NotificationsViewModel viewModel;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  NotificationsViewModel get vm => widget.viewModel;

  late final List<Command<void>> _commands = [
    vm.open,
    vm.followBack,
    vm.markAllRead,
    vm.clearAll,
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
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  void _open(AppNotification n) {
    vm.open.execute(n);
    if (n.route case final route?) GoRouter.of(context).openLink(route);
  }

  Future<void> _clearAll() async {
    if (await confirmDialog(
      context,
      title: 'Clear all notifications?',
      message: 'This removes them from this list on all your devices.',
      confirmLabel: 'Clear',
      destructive: true,
    )) {
      vm.clearAll.execute();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([vm, vm.followBack]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            if (vm.unreadCount > 0)
              TextButton(
                onPressed: vm.markAllRead.execute,
                child: const Text('Mark all read'),
              ),
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'settings' => context.push(Routes.notificationSettings),
                _ => _clearAll(),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.tune),
                    title: Text('Notification settings'),
                  ),
                ),
                PopupMenuItem(
                  value: 'clear',
                  enabled: vm.items.isNotEmpty,
                  child: const ListTile(
                    leading: Icon(Icons.clear_all),
                    title: Text('Clear all'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (!vm.loaded) return const LoadingView();
    final items = vm.items;
    if (items.isEmpty) {
      if (vm.error != null) return ErrorView(error: vm.error);
      return EmptyView(
        art: const DiscIcon(),
        title: 'No notifications',
        message:
            'Team chat, messages, event changes, reminders and playbook '
            'updates show up here.',
        action: OutlinedButton(
          onPressed: () => context.push(Routes.notificationSettings),
          child: const Text('Notification settings'),
        ),
      );
    }
    return ConstrainedContent(
      maxWidth: 720,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (_, i) => _NotificationTile(
          item: items[i],
          onTap: () => _open(items[i]),
          following: switch (items[i].followBack) {
            final f? => vm.isFollowing(f.uid),
            null => false,
          },
          onFollowBack: vm.canFollowBack(items[i])
              ? () => vm.followBack.execute(items[i])
              : null,
          followingBack: vm.followBack.running,
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.onTap,
    this.onFollowBack,
    this.following = false,
    this.followingBack = false,
  });

  final AppNotification item;
  final VoidCallback onTap;

  /// For a new follower the user doesn't follow yet.
  final VoidCallback? onFollowBack;

  /// For a new follower the user already follows.
  final bool following;

  /// A follow back is being saved.
  final bool followingBack;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final unread = !item.read;
    final at = item.createdAt;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread: a small dot, in a fixed gutter so titles line up.
            SizedBox(
              width: 14,
              height: 18,
              child: unread
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(Icons.circle, size: 8, color: c.accent),
                    )
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: c.ink,
                          ),
                        ),
                      ),
                      if (at != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _when(at),
                          style: TextStyle(
                            fontSize: 12,
                            color: unread ? c.accent : c.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.followBack != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: following
                          ? OutlinedButton.icon(
                              onPressed: null,
                              style: _compactButton,
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Following'),
                            )
                          : FilledButton.icon(
                              onPressed: followingBack ? null : onFollowBack,
                              style: _compactButton,
                              icon: const Icon(
                                Icons.person_add_alt_1,
                                size: 16,
                              ),
                              label: const Text('Follow back'),
                            ),
                    )
                  else if (item.body.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        item.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: c.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final _compactButton = ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );

  static String _when(DateTime d) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(d, now)) return DateFormat.jm().format(d);
    if (now.difference(d).inDays < 7) return DateFormat.E().format(d);
    return DateFormat.MMMd().format(d);
  }
}
