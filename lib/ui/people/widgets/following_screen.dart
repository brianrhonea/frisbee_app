import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/follow.dart';
import '../../../routing/open_link.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/following_viewmodel.dart';

IconData followIcon(FollowType t) => switch (t) {
  FollowType.user => Icons.person_outline,
  FollowType.team => Icons.groups_outlined,
  FollowType.tournament => Icons.emoji_events_outlined,
};

/// Where a follow's target lives in the app.
String followRoute(FollowTarget t) => switch (t.type) {
  FollowType.user => Routes.player(t.id),
  FollowType.team => Routes.team(t.id),
  // Hosted and hat tournaments share the key shape; the hosted page
  // falls back to the group's hat tournament.
  FollowType.tournament => Routes.tournament(t.id, host: t.groupId),
};

/// Opens a follow's target: a team with `go` (its tab), the rest with
/// [openPage], which pushes where it can and switches tab where pushing
/// would stack the tabs twice (from Settings, which is over them).
void openFollow(BuildContext context, FollowTarget t) => switch (t.type) {
  FollowType.team => context.go(followRoute(t)),
  FollowType.user || FollowType.tournament => openPage(context, followRoute(t)),
};

class FollowingScreen extends StatefulWidget {
  const FollowingScreen({super.key, required this.viewModel});

  final FollowingViewModel viewModel;

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  FollowingViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.unfollow.addListener(_onResult);
    vm.setNotify.addListener(_onResult);
  }

  @override
  void dispose() {
    vm.unfollow.removeListener(_onResult);
    vm.setNotify.removeListener(_onResult);
    super.dispose();
  }

  void _onResult() {
    for (final cmd in [vm.unfollow, vm.setNotify]) {
      if (cmd.result case Error()) {
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Following')),
      body: !vm.loaded
          ? const LoadingView()
          : vm.error != null
          ? ErrorView(error: vm.error)
          : vm.follows.isEmpty
          ? EmptyView(
              icon: Icons.people_outline,
              title: 'Not following anyone yet',
              message:
                  'Follow people, teams, groups and tournaments to see '
                  'their posts on Home.',
              action: FilledButton.icon(
                onPressed: () => context.go(Routes.explore()),
                icon: const Icon(Icons.search),
                label: const Text('Find teams and groups'),
              ),
            )
          : ConstrainedContent(
              maxWidth: 640,
              child: ListView(
                children: [
                  for (final f in vm.follows)
                    ListTile(
                      key: ValueKey(f.key),
                      leading: Icon(followIcon(f.type)),
                      title: Text(
                        f.target.name.isEmpty ? f.type.label : f.target.name,
                      ),
                      subtitle: Text(f.type.label),
                      onTap: () => openFollow(context, f.target),
                      trailing: PopupMenuButton<_FollowAction>(
                        tooltip: 'Options for ${f.target.name}',
                        icon: Icon(
                          f.notify
                              ? Icons.notifications_active_outlined
                              : Icons.more_vert,
                        ),
                        onSelected: (a) => switch (a) {
                          _FollowAction.notify => vm.setNotify.execute((
                            f.key,
                            !f.notify,
                          )),
                          _FollowAction.unfollow => vm.unfollow.execute(f.key),
                        },
                        itemBuilder: (_) => [
                          CheckedPopupMenuItem(
                            value: _FollowAction.notify,
                            checked: f.notify,
                            child: const Text('Post notifications'),
                          ),
                          const PopupMenuItem(
                            value: _FollowAction.unfollow,
                            child: Text('Unfollow'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    ),
  );
}

enum _FollowAction { notify, unfollow }
