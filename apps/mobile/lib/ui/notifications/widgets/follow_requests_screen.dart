import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/follow.dart';
import '../../../routing/open_link.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show CountPill, PersonAvatar;
import '../../profile/view_models/profile_viewmodel.dart';
import '../../settings/widgets/settings_widgets.dart';

/// People asking to follow the user's private profile: Accept or Decline.
class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  ProfileViewModel get vm => widget.viewModel;

  /// Answered here, hidden at once while the write goes out.
  final _answered = <String>{};

  @override
  void initState() {
    super.initState();
    vm.acceptRequest.addListener(_onAnswer);
    vm.declineRequest.addListener(_onAnswer);
  }

  @override
  void dispose() {
    vm.acceptRequest.removeListener(_onAnswer);
    vm.declineRequest.removeListener(_onAnswer);
    super.dispose();
  }

  void _onAnswer() {
    for (final c in [vm.acceptRequest, vm.declineRequest]) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
        setState(_answered.clear);
      }
    }
  }

  void _answer(FollowRequest r, {required bool accept}) {
    setState(() => _answered.add(r.uid));
    (accept ? vm.acceptRequest : vm.declineRequest).execute(r);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final c = AppColors.of(context);
      final requests = [
        for (final r in vm.followRequests)
          if (!_answered.contains(r.uid)) r,
      ];
      return SettingsPage(
        title: 'Follow requests',
        actions: [
          if (requests.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: CountPill(requests.length)),
            ),
        ],
        children: [
          if (requests.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.person_add_alt, size: 40, color: c.muted),
                  const SizedBox(height: 12),
                  Text(
                    'No requests right now',
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    vm.isPrivate ?? false
                        ? 'When someone asks to follow you, they show up here.'
                        : 'Your profile is public, so people follow you '
                              'without asking.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ],
              ),
            )
          else ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 18, color: c.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${vm.isPrivate ?? false ? 'Your profile is private. ' : ''}'
                      'Accepting lets them see your posts, teams and stats. '
                      "Declining doesn't tell them.",
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: c.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SettingsGroup(
              children: [
                for (final r in requests)
                  _RequestTile(
                    key: ValueKey(r.uid),
                    request: r,
                    onOpen: () => openPage(context, Routes.player(r.uid)),
                    onAccept: () => _answer(r, accept: true),
                    onDecline: () => _answer(r, accept: false),
                  ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: c.accent),
                onPressed: () => context.push(Routes.settingsPrivacy),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right, size: 18),
                label: const Text('Privacy settings'),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    super.key,
    required this.request,
    required this.onOpen,
    required this.onAccept,
    required this.onDecline,
  });

  final FollowRequest request;
  final VoidCallback onOpen;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final name = request.name.isEmpty ? 'Someone' : request.name;
    final c = AppColors.of(context);
    return ListTile(
      onTap: onOpen,
      contentPadding: const EdgeInsets.only(left: 14, right: 4),
      minTileHeight: 68,
      leading: PersonAvatar(name: name, photoUrl: request.photoUrl, radius: 22),
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
      subtitle: switch (request.username) {
        final u? => Text(
          '@$u',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: c.muted),
        ),
        null => null,
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: onAccept,
            child: const Text('Accept'),
          ),
          IconButton(
            tooltip: 'Decline',
            onPressed: onDecline,
            icon: Icon(Icons.close, color: c.muted),
          ),
        ],
      ),
    );
  }
}
