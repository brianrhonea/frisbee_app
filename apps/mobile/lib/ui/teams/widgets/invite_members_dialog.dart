import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../domain/models/invite_code.dart';
import '../../../domain/models/team.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show PersonAvatar;
import '../../core/ui/view_model_host.dart';
import '../view_models/invite_members_viewmodel.dart';
import '../../core/ui/app_search_field.dart';
import '../../core/ui/skeleton.dart';

/// Opens the people search for inviting members to [team]; without
/// [withLink], just the search (a community admin inviting to its team).
Future<void> showInviteMembers(
  BuildContext context,
  Team team, {
  bool withLink = true,
}) => showDialog<void>(
  context: context,
  builder: (_) => ViewModelHost(
    create: (c) => InviteMembersViewModel(
      team: team,
      teamRepository: c.read(),
      directMessageRepository: c.read(),
      authRepository: c.read(),
      withLink: withLink,
    ),
    builder: (_, vm) => InviteMembersDialog(viewModel: vm),
  ),
);

/// The team's invite link (made on opening) to copy or share to any app,
/// a group's join requests, and people search: each person invited gets
/// an in-app invite and the link in a message.
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
    vm.approveJoinRequest.addListener(_onRequest);
    vm.declineJoinRequest.addListener(_onRequest);
    vm.start();
  }

  @override
  void dispose() {
    vm.invite.removeListener(_onInvite);
    vm.approveJoinRequest.removeListener(_onRequest);
    vm.declineJoinRequest.removeListener(_onRequest);
    super.dispose();
  }

  void _onInvite() {
    if (vm.invite.result case Error(:final error)) {
      showErrorSnackBar(context, error);
      vm.invite.clearResult();
    }
  }

  void _onRequest() {
    for (final c in [vm.approveJoinRequest, vm.declineJoinRequest]) {
      if (c.result case Error(:final error)) {
        showErrorSnackBar(context, error);
        c.clearResult();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final group = vm.team.isCommunity;
    return AlertDialog(
      title: Text(
        group
            ? 'Invite members'
            : vm.withLink
            ? 'Invite players'
            : 'Invite to ${vm.team.name}',
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 420,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (vm.withLink) ...[
              _LinkCard(viewModel: vm),
              _JoinRequestsCard(viewModel: vm),
              const SizedBox(height: 16),
              Text(
                'Or invite someone on Stall 10',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
            ],
            AppSearchField(hint: 'Search people by name', onChanged: vm.search),
            const SizedBox(height: 8),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([vm, vm.invite]),
                builder: (context, _) {
                  if (vm.searching) {
                    return const SkeletonList(count: 4);
                  }
                  if (vm.error != null) {
                    return Center(child: Text(errorMessage(vm.error)));
                  }
                  String? note;
                  final invited = vm.invitedPeople;
                  if (vm.query.length < InviteMembersViewModel.minQueryLength &&
                      invited.isNotEmpty) {
                    // Who was invited while this was open, until the next
                    // search.
                    return ListView(
                      children: [
                        Text(
                          'Invited just now',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        for (final p in invited)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: PersonAvatar(
                              name: p.name,
                              photoUrl: p.photoUrl,
                            ),
                            title: Text(p.name),
                            trailing: Text(
                              'Pending',
                              style: TextStyle(color: c.muted),
                            ),
                          ),
                      ],
                    );
                  }
                  if (vm.query.length < InviteMembersViewModel.minQueryLength) {
                    note = vm.withLink
                        ? 'Find people by name. They get an invite to accept '
                              'and the link in a message.'
                        : 'Find people by name. They get an invite to accept '
                              'in their Teams tab, and a message.';
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
                          subtitle: p.username == null
                              ? null
                              : Text('@${p.username}'),
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

/// The invite link, with Copy and Share (to Messages, WhatsApp, email...).
/// A team picks how long its link works; the link is made on first copy
/// or share.
class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.viewModel});

  final InviteMembersViewModel viewModel;

  /// The link, made first if need be; null (after a snackbar) on failure.
  Future<Uri?> _link(BuildContext context) async {
    await viewModel.createLink.execute();
    final result = viewModel.createLink.result;
    viewModel.createLink.clearResult();
    if (result case Ok(:final value)) return value;
    if (result case Error(:final error) when context.mounted) {
      showErrorSnackBar(context, error);
    }
    return null;
  }

  Future<void> _copy(BuildContext context) async {
    final link = await _link(context);
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link.toString()));
    if (context.mounted) showSnackBar(context, 'Link copied');
  }

  /// The link as a QR code, big enough to scan from across a huddle.
  Future<void> _qr(BuildContext context) async {
    final link = await _link(context);
    if (link == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => InviteQrDialog(
        link: link,
        teamName: viewModel.team.name,
        expiresAt: viewModel.linkExpiresAt,
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    final link = await _link(context);
    if (link == null || !context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: viewModel.shareTextFor(link),
        subject: 'Join ${viewModel.team.name}',
        // iPad anchors the sheet here.
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([viewModel, viewModel.createLink]),
      builder: (context, _) {
        final link = viewModel.link;
        final busy = viewModel.createLink.running;
        final expires = viewModel.linkExpiresAt;
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: c.accentSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Invite link',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
              ),
              const SizedBox(height: 2),
              Text(
                viewModel.linkExpires
                    ? 'Anyone with it can join as a player until it expires.'
                    : 'Anyone with it can find and join the community.',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
              if (viewModel.linkExpires) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Works for',
                      style: TextStyle(fontSize: 12.5, color: c.ink),
                    ),
                    for (final e in InviteLinkExpiry.values)
                      ChoiceChip(
                        label: Text(e.label),
                        selected: viewModel.expiry == e,
                        visualDensity: VisualDensity.compact,
                        onSelected: busy ? null : (_) => viewModel.setExpiry(e),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: link == null
                        ? Text(
                            busy
                                ? 'Making a link…'
                                : viewModel.createLink.error
                                ? "Couldn't make a link. Copy or share to "
                                      'try again.'
                                : 'Copy or share to make a link.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: viewModel.createLink.error
                                  ? Theme.of(context).colorScheme.error
                                  : c.muted,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                link.toString(),
                                maxLines: 1,
                                style: TextStyle(fontSize: 12.5, color: c.ink),
                              ),
                              if (expires != null)
                                Text(
                                  'Works until '
                                  '${DateFormat('MMM d, h:mm a').format(expires)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.muted,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  IconButton(
                    tooltip: 'Copy link',
                    onPressed: busy ? null : () => _copy(context),
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                  IconButton(
                    tooltip: 'QR code',
                    onPressed: busy ? null : () => _qr(context),
                    icon: const Icon(Icons.qr_code_2, size: 20),
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : () => _share(context),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Share'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// [link] as a QR code to scan with a phone's camera, which opens the
/// invite like tapping the link. Always dark on white, in either theme, so
/// cameras read it.
class InviteQrDialog extends StatelessWidget {
  const InviteQrDialog({
    super.key,
    required this.link,
    required this.teamName,
    this.expiresAt,
  });

  final Uri link;
  final String teamName;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      title: Text('Scan to join $teamName'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            // A fixed size: the dialog measures its content, and the QR
            // view's LayoutBuilder can't be measured.
            child: SizedBox.square(
              dimension: 240,
              child: QrImageView(
                data: link.toString(),
                size: 240,
                backgroundColor: Colors.white,
                semanticsLabel: 'QR code for the invite link',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            expiresAt == null
                ? 'Point a phone camera at the code.'
                : 'Point a phone camera at the code. Works until '
                      '${DateFormat('MMM d, h:mm a').format(expiresAt!)}.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
        ],
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

/// People asking to join a group that approves members, to approve or
/// decline right from the invite dialog (also on the Members tab).
class _JoinRequestsCard extends StatelessWidget {
  const _JoinRequestsCard({required this.viewModel});

  final InviteMembersViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: Listenable.merge([
        vm,
        vm.approveJoinRequest,
        vm.declineJoinRequest,
      ]),
      builder: (context, _) {
        final requests = vm.joinRequests;
        if (!vm.hasJoinRequests || requests.isEmpty) {
          return const SizedBox.shrink();
        }
        final busy =
            vm.approveJoinRequest.running || vm.declineJoinRequest.running;
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Requests (${requests.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 132),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in requests)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: PersonAvatar(
                          name: r.name.isEmpty ? '?' : r.name,
                        ),
                        title: Text(r.name.isEmpty ? 'Someone' : r.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Decline',
                              icon: const Icon(Icons.close),
                              onPressed: busy
                                  ? null
                                  : () => vm.declineJoinRequest.execute(r.uid),
                            ),
                            FilledButton.tonal(
                              onPressed: busy
                                  ? null
                                  : () => vm.approveJoinRequest.execute(r),
                              child: const Text('Approve'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
