import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/follow.dart';
import '../../../routing/open_link.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show PersonAvatar, TeamBadge;
import '../../core/ui/status_views.dart';
import '../../settings/widgets/settings_widgets.dart';
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

  /// The heading a follow sits under.
  static String _section(FollowType t) => switch (t) {
    FollowType.user => 'People',
    FollowType.team => 'Teams and communities',
    FollowType.tournament => 'Tournaments',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final c = AppColors.of(context);
      // One card per kind, in the order the list gives them.
      final sections = <String, List<Follow>>{};
      for (final f in vm.follows) {
        (sections[_section(f.type)] ??= []).add(f);
      }
      return Scaffold(
        appBar: settingsAppBar(
          context,
          title: const Text('Following'),
          actions: [
            if (vm.loaded && vm.follows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '${vm.follows.length}',
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
              ),
          ],
        ),
        body: !vm.loaded
            ? const LoadingView()
            : vm.error != null
            ? ErrorView(error: vm.error)
            : vm.follows.isEmpty
            ? EmptyView(
                icon: Icons.people_outline,
                title: 'Not following anyone yet',
                message:
                    'Follow people, teams, communities and tournaments to see '
                    'their posts on Home.',
                action: FilledButton.icon(
                  onPressed: () => context.go(Routes.explore()),
                  icon: const Icon(Icons.search),
                  label: const Text('Find teams and communities'),
                ),
              )
            : ConstrainedContent(
                maxWidth: 640,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Their posts show on Home. The bell means you get a '
                        'notification for each new post.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: c.muted,
                        ),
                      ),
                    ),
                    for (final MapEntry(key: title, value: follows)
                        in sections.entries)
                      SettingsGroup(
                        title: title,
                        children: [
                          for (final f in follows)
                            _FollowRow(
                              key: ValueKey(f.key),
                              follow: f,
                              onOpen: () => openFollow(context, f.target),
                              onAction: (a) => switch (a) {
                                _FollowAction.notify => vm.setNotify.execute((
                                  f.key,
                                  !f.notify,
                                )),
                                _FollowAction.unfollow => vm.unfollow.execute(
                                  f.key,
                                ),
                              },
                            ),
                        ],
                      ),
                  ],
                ),
              ),
      );
    },
  );
}

/// One follow: its mark, name and kind, a bell when its posts notify, and
/// the menu for notifications and Unfollow.
class _FollowRow extends StatelessWidget {
  const _FollowRow({
    super.key,
    required this.follow,
    required this.onOpen,
    required this.onAction,
  });

  final Follow follow;
  final VoidCallback onOpen;
  final ValueChanged<_FollowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final f = follow;
    final name = f.target.name.isEmpty ? f.type.label : f.target.name;
    return ListTile(
      minTileHeight: 64,
      contentPadding: const EdgeInsets.only(left: 14, right: 4),
      leading: switch (f.type) {
        FollowType.user => PersonAvatar(
          name: name,
          photoUrl: f.target.photoUrl,
        ),
        FollowType.team => const TeamBadge(),
        FollowType.tournament => Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.accentSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(followIcon(f.type), size: 20, color: c.accentInk),
        ),
      },
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: c.ink,
        ),
      ),
      subtitle: Text(
        f.type.label,
        style: TextStyle(fontSize: 12, color: c.muted),
      ),
      onTap: onOpen,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (f.notify)
            Icon(
              Icons.notifications_active_outlined,
              size: 20,
              color: c.accent,
              semanticLabel: 'Post notifications on',
            ),
          PopupMenuButton<_FollowAction>(
            tooltip: 'Options for ${f.target.name}',
            icon: Icon(Icons.more_vert, color: c.muted),
            onSelected: onAction,
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
        ],
      ),
    );
  }
}

enum _FollowAction { notify, unfollow }
