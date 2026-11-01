import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/team.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show PersonAvatar;
import '../../core/ui/view_model_host.dart';
import '../view_models/invite_members_viewmodel.dart';

/// Opens the people search for inviting members to [team].
Future<void> showInviteMembers(BuildContext context, Team team) =>
    showDialog<void>(
      context: context,
      builder: (_) => ViewModelHost(
        create: (c) => InviteMembersViewModel(
          team: team,
          teamRepository: c.read(),
          directMessageRepository: c.read(),
          authRepository: c.read(),
        ),
        builder: (_, vm) => InviteMembersDialog(viewModel: vm),
      ),
    );

/// Search people by name and send each an invite they can accept.
class InviteMembersDialog extends StatefulWidget {
  const InviteMembersDialog({super.key, required this.viewModel});

  final InviteMembersViewModel viewModel;

  @override
  State<InviteMembersDialog> createState() => _InviteMembersDialogState();
}

class _InviteMembersDialogState extends State<InviteMembersDialog> {
  InviteMembersViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.invite.addListener(_onInvite);
  }

  @override
  void dispose() {
    vm.invite.removeListener(_onInvite);
    super.dispose();
  }

  void _onInvite() {
    if (vm.invite.result case Error(:final error)) {
      showErrorSnackBar(context, error);
      vm.invite.clearResult();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final group = vm.team.isCommunity;
    return AlertDialog(
      title: Text(group ? 'Invite members' : 'Invite players'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search people by name',
              ),
              onChanged: vm.search,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([vm, vm.invite]),
                builder: (context, _) {
                  if (vm.searching) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (vm.error != null) {
                    return Center(child: Text(errorMessage(vm.error)));
                  }
                  String? note;
                  if (vm.query.length < InviteMembersViewModel.minQueryLength) {
                    note =
                        'Find people by name and send them an invite. They '
                        'join as soon as they accept.';
                  } else if (vm.results.isEmpty) {
                    note = 'No one by that name.';
                  }
                  if (note != null) {
                    return Center(
                      child: Text(
                        note,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted),
                      ),
                    );
                  }
                  return ListView(
                    children: [
                      for (final p in vm.results)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: PersonAvatar(
                            name: p.name,
                            photoUrl: p.photoUrl,
                          ),
                          title: Text(p.name),
                          trailing: vm.isMember(p.uid)
                              ? Text('Member', style: TextStyle(color: c.muted))
                              : vm.wasInvited(p.uid)
                              ? const Chip(
                                  avatar: Icon(Icons.check, size: 16),
                                  label: Text('Invited'),
                                )
                              : FilledButton.tonal(
                                  onPressed: vm.invite.running
                                      ? null
                                      : () => vm.invite.execute(p),
                                  child: const Text('Invite'),
                                ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
