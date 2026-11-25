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
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../view_models/notifications_viewmodel.dart';
import '../../../routing/open_link.dart';

/// The icon for what happened: a like, a repost, a message, … falling
/// back to the category's.
IconData noticeIcon(AppNotification n) => switch (n.kind) {
  'likes' || 'commentLikes' => Icons.favorite,
  'repost' => Icons.repeat,
  'comments' || 'replies' || 'videoComments' => Icons.mode_comment_outlined,
  'follower' || 'followRequests' => Icons.person_add_alt_1_outlined,
  'mention' => Icons.alternate_email,
  'chat' => Icons.forum_outlined,
  'dm' || 'dmRequests' => Icons.chat_bubble_outline,
  'meeting' || 'meetingStarted' => Icons.videocam_outlined,
  'event' || 'schedule' => Icons.event_outlined,
  'deadline' => Icons.alarm,
  'invite' ||
  'teamInvite' ||
  'joinRequest' ||
  'joinApproved' => Icons.group_add_outlined,
  'calendarInvite' => Icons.calendar_month_outlined,
  'play' => Icons.sports_outlined,
  'posts' => Icons.dynamic_feed_outlined,
  _ => categoryIcon(n.category),
};

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
/// went out as push, under a Follow requests entry. Tapping an entry
/// marks it read (it stays, in lighter type) and opens it.
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
    // Back goes to the page it belongs under, not back to this list.
    if (n.route case final route?) {
      GoRouter.of(context).openFromNotifications(route);
    }
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
    final requests = vm.showsFollowRequests
        ? _FollowRequestsTile(
            count: vm.followRequestCount,
            onTap: () => context.push(Routes.followRequests),
          )
        : null;
    if (items.isEmpty) {
      final empty = _empty();
      if (requests == null) return empty;
      return ConstrainedContent(
        maxWidth: 720,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _GroupCard(children: [requests]),
            ),
            Expanded(child: empty),
          ],
        ),
      );
    }
    Widget tile(AppNotification n) => _NotificationTile(
      item: n,
      onTap: () => _open(n),
      following: switch (n.followBack) {
        final f? => vm.isFollowing(f.uid),
        null => false,
      },
      onFollowBack: vm.canFollowBack(n) ? () => vm.followBack.execute(n) : null,
      followingBack: vm.followBack.running,
    );
    // Grouped by day: what came in today, then everything earlier.
    final now = DateTime.now();
    final today = [
      for (final n in items)
        if (n.createdAt case final at? when DateUtils.isSameDay(at, now)) n,
    ];
    final earlier = [
      for (final n in items)
        if (!today.contains(n)) n,
    ];
    final waiting = vm.followRequestCount > 0;
    return ConstrainedContent(
      maxWidth: 720,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Follow requests waiting are the user's to do: amber, on top.
          if (requests != null) ...[
            if (waiting)
              _GroupHeader(
                'Needs you · ${vm.followRequestCount}',
                needsYou: true,
              )
            else
              const SizedBox(height: 8),
            _GroupCard(children: [requests]),
          ],
          if (today.isNotEmpty) ...[
            const _GroupHeader('Today'),
            _GroupCard(children: [for (final n in today) tile(n)]),
          ],
          if (earlier.isNotEmpty) ...[
            const _GroupHeader('Earlier'),
            _GroupCard(children: [for (final n in earlier) tile(n)]),
          ],
        ],
      ),
    );
  }

  Widget _empty() {
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
}

/// A group's label above its card, e.g. "TODAY"; "Needs you" in amber
/// with a dot.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label, {this.needsYou = false});

  final String label;
  final bool needsYou;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Row(
        children: [
          if (needsYou) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: c.highlight,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: needsYou ? c.highlightInk : c.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A group's entries on one card, with hairlines between them.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) Divider(height: 1, color: c.border),
            child,
          ],
        ],
      ),
    );
  }
}

/// A category's icon in a small round disc, leading a row.
class _IconDisc extends StatelessWidget {
  const _IconDisc({
    required this.icon,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    child: Icon(icon, size: 18, color: color),
  );
}

/// The first entry: people asking to follow the user's private profile.
class _FollowRequestsTile extends StatelessWidget {
  const _FollowRequestsTile({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListTile(
      onTap: onTap,
      leading: _IconDisc(
        icon: Icons.person_add_alt,
        color: count > 0 ? c.highlightInk : c.muted,
        background: count > 0 ? c.highlightSoft : c.field,
      ),
      title: Text(
        'Follow requests',
        style: TextStyle(
          fontWeight: count > 0 ? FontWeight.w700 : FontWeight.w500,
          color: c.ink,
        ),
      ),
      subtitle: Text(
        count == 0 ? 'None waiting' : '$count waiting for an answer',
        style: TextStyle(fontSize: 13, color: c.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Waiting on the user: an amber count.
          if (count > 0) CountPill(count),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: c.muted),
        ],
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
        // Compact rows without category icons (a deliberate choice).
        padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                          // New: bold and larger. Read: lighter and
                          // smaller, but still listed.
                          style: TextStyle(
                            fontSize: unread ? 15.5 : 14,
                            height: 1.3,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: unread ? c.ink : c.muted,
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
                      // Unread: a small turf dot after the time.
                      if (unread) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.circle, size: 8, color: c.accent),
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
                          fontSize: unread ? 14 : 13,
                          height: 1.3,
                          color: unread ? c.ink : c.muted,
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
      TextStyle(fontFamily: appFont, fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );

  static String _when(DateTime d) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(d, now)) return DateFormat.jm().format(d);
    if (now.difference(d).inDays < 7) return DateFormat.E().format(d);
    return DateFormat.MMMd().format(d);
  }
}
