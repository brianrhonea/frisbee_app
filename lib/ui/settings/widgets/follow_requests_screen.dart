import 'package:flutter/material.dart';

import '../../../domain/models/follow.dart';
import '../../../routing/open_link.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show PersonAvatar;
import '../../profile/view_models/profile_viewmodel.dart';
import 'settings_widgets.dart';

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
          else
            SettingsGroup(
              footer:
                  'Accepting lets them see your posts, teams and stats. '
                  "Declining doesn't tell them.",
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
    return ListTile(
      onTap: onOpen,
      leading: PersonAvatar(name: name, photoUrl: request.photoUrl),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: switch (request.username) {
        final u? => Text('@$u', maxLines: 1, overflow: TextOverflow.ellipsis),
        null => null,
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(onPressed: onAccept, child: const Text('Accept')),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Decline',
            onPressed: onDecline,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
