import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/team_community_viewmodel.dart';

/// Opens [team]'s community settings, for its admins.
Future<void> showTeamCommunity(BuildContext context, Team team) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ViewModelHost(
        create: (c) => TeamCommunityViewModel(
          teamId: team.id,
          teamRepository: c.read(),
          authRepository: c.read(),
        ),
        builder: (_, vm) => TeamCommunitySheet(viewModel: vm),
      ),
    );

/// Where a team stands with a school or club community: part of one (open
/// it or leave), waiting for an answer, or looking for one to join.
class TeamCommunitySheet extends StatefulWidget {
  const TeamCommunitySheet({super.key, required this.viewModel});

  final TeamCommunityViewModel viewModel;

  @override
  State<TeamCommunitySheet> createState() => _TeamCommunitySheetState();
}

class _TeamCommunitySheetState extends State<TeamCommunitySheet> {
  TeamCommunityViewModel get vm => widget.viewModel;
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    vm.request.addListener(_onResult);
    vm.leave.addListener(_onResult);
  }

  @override
  void dispose() {
    vm.request.removeListener(_onResult);
    vm.leave.removeListener(_onResult);
    _query.dispose();
    super.dispose();
  }

  void _onResult() {
    for (final c in [vm.request, vm.leave]) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  Future<void> _ask(TeamListing org) async {
    final ok = await confirmDialog(
      context,
      title: 'Ask to join ${org.name}?',
      message:
          "Its admins choose which of the community's roles get on "
          '${vm.team?.name ?? 'your team'}. Members with those roles join '
          'your team automatically; you keep your roster, playbook and '
          'stats.',
      confirmLabel: 'Ask to join',
    );
    if (ok) vm.request.execute(org);
  }

  Future<void> _leave() async {
    final ok = await confirmDialog(
      context,
      title: vm.inCommunity ? 'Leave ${vm.orgName}?' : 'Withdraw the request?',
      message: vm.inCommunity
          ? 'People who got on the team through a community role leave it. '
                'Members you added yourself stay.'
          : '${vm.orgName} will no longer see it.',
      confirmLabel: vm.inCommunity ? 'Leave' : 'Withdraw',
      destructive: vm.inCommunity,
    );
    if (ok) vm.leave.execute();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.search, vm.request, vm.leave]),
    builder: (context, _) {
      final theme = Theme.of(context);
      final busy = vm.request.running || vm.leave.running;
      final children = <Widget>[
        Text('School or club', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
      ];
      if (vm.inCommunity) {
        children.addAll([
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_balance_outlined),
            title: Text(vm.orgName),
            subtitle: Text(
              '${vm.team?.orgMembers.length ?? 0} on the team through its roles',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              context.push(Routes.team(vm.orgId!));
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: busy ? null : _leave,
              child: const Text('Leave community'),
            ),
          ),
        ]);
      } else if (vm.pending || vm.declined) {
        children.addAll([
          Text(
            vm.declined
                ? "${vm.orgName} didn't add the team."
                : 'Waiting for ${vm.orgName} to add the team.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: busy ? null : vm.leave.execute,
              child: Text(vm.declined ? 'OK' : 'Withdraw request'),
            ),
          ),
        ]);
      } else {
        children.addAll([
          Text(
            'Put the team in its school or club community, so members '
            'with the right role there join it automatically.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _query,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Find a school or club',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: vm.search.execute,
          ),
          const SizedBox(height: 8),
          for (final org in vm.results)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_outlined),
              title: Text(org.name),
              subtitle: org.city.isEmpty ? null : Text(org.city),
              trailing: TextButton(
                onPressed: busy ? null : () => _ask(org),
                child: const Text('Ask to join'),
              ),
            ),
          if (vm.search.completed &&
              vm.results.isEmpty &&
              _query.text.trim().length >=
                  TeamCommunityViewModel.minQueryLength)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No school or club by that name. Someone there can make '
                'one from Teams → Create.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ]);
      }
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      );
    },
  );
}
