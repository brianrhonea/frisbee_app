import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/follow.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/following_viewmodel.dart';

IconData followIcon(FollowType t) => switch (t) {
  FollowType.user => Icons.person_outline,
  FollowType.team => Icons.groups_outlined,
  FollowType.tournament => Icons.emoji_events_outlined,
  FollowType.event => Icons.event_outlined,
};

/// Where a follow's target lives in the app.
String followRoute(FollowTarget t) => switch (t.type) {
  FollowType.user => Routes.person(t.id),
  FollowType.team => Routes.team(t.id),
  FollowType.tournament => Routes.groupTournament(t.groupId ?? '', t.id),
  FollowType.event => Routes.tournament(t.id),
};

/// Opens a follow's target: tab pages with `go`, pages over the tabs with
/// `push`.
void openFollow(BuildContext context, FollowTarget t) => switch (t.type) {
  FollowType.team => context.go(followRoute(t)),
  FollowType.user ||
  FollowType.tournament ||
  FollowType.event => context.push(followRoute(t)),
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
                  'their posts on Home. Tap the bell to get notified.',
              action: FilledButton.icon(
                onPressed: () => context.go(Routes.searchTeams),
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: f.notify
                                ? 'Turn off post notifications'
                                : 'Notify me about new posts',
                            isSelected: f.notify,
                            icon: const Icon(Icons.notifications_none),
                            selectedIcon: const Icon(
                              Icons.notifications_active,
                            ),
                            onPressed: () =>
                                vm.setNotify.execute((f.key, !f.notify)),
                          ),
                          TextButton(
                            onPressed: () => vm.unfollow.execute(f.key),
                            child: const Text('Unfollow'),
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
