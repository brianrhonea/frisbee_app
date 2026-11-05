import 'package:flutter/material.dart';

import '../../../domain/models/notification.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../notifications/widgets/notification_offer.dart';
import '../view_models/follow_viewmodel.dart';

/// Follow, or once following, a "Following" menu with post notifications
/// and Unfollow. Following someone offers their post notifications.
/// Page view models own the [FollowViewModel] (see their `follow`).
class FollowControl extends StatefulWidget {
  const FollowControl({
    super.key,
    required this.viewModel,
    this.showCount = false,
    this.compact = false,
  });

  final FollowViewModel viewModel;
  final bool showCount;
  final bool compact;

  @override
  State<FollowControl> createState() => _FollowControlState();
}

class _FollowControlState extends State<FollowControl> {
  FollowViewModel get vm => widget.viewModel;

  /// Whether the running toggle is a follow (not an unfollow), so its
  /// success can offer notifications.
  bool _following = false;

  void _toggleFollow() {
    _following = !vm.following;
    vm.toggleFollow.execute();
  }

  @override
  void initState() {
    super.initState();
    vm.toggleFollow.addListener(_onFollow);
    vm.toggleNotify.addListener(_onNotify);
  }

  @override
  void dispose() {
    vm.toggleFollow.removeListener(_onFollow);
    vm.toggleNotify.removeListener(_onNotify);
    super.dispose();
  }

  void _onFollow() {
    final cmd = vm.toggleFollow;
    switch (cmd.result) {
      case Error():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case Ok() when _following:
        _following = false;
        cmd.clearResult();
        _offerNotifications();
      default:
        break;
    }
  }

  Future<void> _offerNotifications() async {
    if (vm.notifying) return;
    final yes = await showNotificationOffer(
      context,
      title: 'Get notified when ${vm.target.name} posts?',
      message: "You'll see their posts on Home either way.",
    );
    if (yes == true && mounted && !vm.notifying) vm.toggleNotify.execute();
  }

  void _onNotify() {
    final cmd = vm.toggleNotify;
    final result = cmd.result;
    if (result == null) return;
    cmd.clearResult();
    switch (result) {
      case Error():
        showErrorSnackBar(context, result);
      case Ok(:final value?):
        showSnackBar(
          context,
          value == PushStatus.denied
              ? "You'll see ${vm.target.name}'s posts in Notifications. "
                    'Push is turned off for this app in system settings.'
              : "We'll let you know when ${vm.target.name} posts.",
        );
      case Ok():
        break;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.toggleFollow, vm.toggleNotify]),
    builder: (context, _) {
      if (vm.isSelf) {
        return widget.showCount ? _count(context) : const SizedBox.shrink();
      }
      final busy = !vm.loaded || vm.toggleFollow.running;
      final density = widget.compact ? VisualDensity.compact : null;
      final Widget button;
      if (vm.following) {
        button = MenuAnchor(
          menuChildren: [
            CheckboxMenuButton(
              value: vm.notifying,
              onChanged: vm.toggleNotify.running
                  ? null
                  : (_) => vm.toggleNotify.execute(),
              child: const Text('Post notifications'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.person_remove_outlined),
              onPressed: busy ? null : _toggleFollow,
              child: const Text('Unfollow'),
            ),
          ],
          builder: (context, menu, _) => OutlinedButton.icon(
            style: OutlinedButton.styleFrom(visualDensity: density),
            onPressed: busy
                ? null
                : () => menu.isOpen ? menu.close() : menu.open(),
            icon: Icon(
              vm.notifying ? Icons.notifications_active : Icons.check,
              size: 18,
            ),
            label: const Text('Following'),
          ),
        );
      } else {
        button = FilledButton.icon(
          style: FilledButton.styleFrom(visualDensity: density),
          onPressed: busy ? null : _toggleFollow,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Follow'),
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showCount) ...[_count(context), const SizedBox(width: 12)],
          if (vm.following)
            button
          else
            Tooltip(
              message: 'Follow ${vm.target.name} to see their posts on Home',
              child: button,
            ),
        ],
      );
    },
  );

  Widget _count(BuildContext context) {
    final n = vm.followers;
    return Text(
      n == 1 ? '1 follower' : '$n followers',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
