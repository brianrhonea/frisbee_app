import 'package:flutter/material.dart';

import '../../../domain/models/notification.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../view_models/follow_viewmodel.dart';

/// Follow / Following, plus a bell for post notifications once following.
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
    if (cmd.result case Error()) {
      showErrorSnackBar(context, cmd.result);
      cmd.clearResult();
    }
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
      final button = vm.following
          ? OutlinedButton.icon(
              style: OutlinedButton.styleFrom(visualDensity: density),
              onPressed: busy ? null : vm.toggleFollow.execute,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Following'),
            )
          : FilledButton.icon(
              style: FilledButton.styleFrom(visualDensity: density),
              onPressed: busy ? null : vm.toggleFollow.execute,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Follow'),
            );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showCount) ...[_count(context), const SizedBox(width: 12)],
          Tooltip(
            message: vm.following
                ? 'Unfollow ${vm.target.name}'
                : 'Follow ${vm.target.name} to see their posts on Home',
            child: button,
          ),
          if (vm.following)
            IconButton(
              visualDensity: density,
              tooltip: vm.notifying
                  ? 'Turn off post notifications'
                  : 'Notify me when ${vm.target.name} posts',
              isSelected: vm.notifying,
              onPressed: vm.toggleNotify.running
                  ? null
                  : vm.toggleNotify.execute,
              icon: const Icon(Icons.notifications_none),
              selectedIcon: const Icon(Icons.notifications_active),
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
