import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/team.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../../settings/widgets/settings_widgets.dart';
import '../view_models/team_settings_viewmodel.dart';

/// Opens [teamId]'s settings over the team page.
Future<void> showTeamSettings(BuildContext context, String teamId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ViewModelHost(
          create: (c) => TeamSettingsViewModel(
            teamId: teamId,
            teamRepository: c.read(),
            authRepository: c.read(),
          ),
          builder: (_, vm) => TeamSettingsScreen(viewModel: vm),
        ),
      ),
    );

/// What the "Public team page" switch does (the website says the same).
const publicPageDescription =
    "Anyone can see the team's public posts, upcoming public events and, "
    "for an adult team, its roster. Turned off, people outside the team "
    'see only its name and city. Chat always stays private.';

/// What the "Allow join requests" switch does (allowJoinRequestsDescription
/// in packages/shared; the website says the same).
const allowJoinRequestsDescription =
    'People who find the team can ask to join from its page. Admins who '
    'manage members approve or decline each request; club teams still '
    'need players to be 16 or over.';

/// A team's settings: the Sections card, a switch for each optional
/// section with what it's for. The owner turns them on or off; new teams
/// start with them off. Then Visibility: the "Public team page" switch,
/// for the team's admins.
class TeamSettingsScreen extends StatefulWidget {
  const TeamSettingsScreen({super.key, required this.viewModel});

  final TeamSettingsViewModel viewModel;

  @override
  State<TeamSettingsScreen> createState() => _TeamSettingsScreenState();
}

class _TeamSettingsScreenState extends State<TeamSettingsScreen> {
  TeamSettingsViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.setSection.addListener(_onCommand);
    vm.setPublicPage.addListener(_onCommand);
    vm.setAllowJoinRequests.addListener(_onCommand);
  }

  @override
  void dispose() {
    vm.setSection.removeListener(_onCommand);
    vm.setPublicPage.removeListener(_onCommand);
    vm.setAllowJoinRequests.removeListener(_onCommand);
    super.dispose();
  }

  void _onCommand() {
    for (final c in [
      vm.setSection,
      vm.setPublicPage,
      vm.setAllowJoinRequests,
    ]) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  /// Off declines the requests waiting, so it asks first.
  Future<void> _setJoinRequests(bool on) async {
    if (!on &&
        !await confirmDialog(
          context,
          title: 'Stop taking join requests?',
          message:
              'Anyone still waiting is declined. People can still join '
              'with an invite.',
          confirmLabel: 'Turn off',
        )) {
      return;
    }
    vm.setAllowJoinRequests.execute(on);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: settingsAppBar(context, title: const Text('Team settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          vm,
          vm.setSection,
          vm.setPublicPage,
          vm.setAllowJoinRequests,
        ]),
        builder: (context, _) {
          if (!vm.loaded) return const LoadingView();
          final team = vm.team;
          if (team == null) {
            return vm.error != null
                ? ErrorView(error: vm.error)
                : const EmptyView(
                    icon: Icons.group_off_outlined,
                    title: 'Team not available',
                    message: 'It may have been deleted or you were removed.',
                  );
          }
          final busy = vm.setSection.running;
          return ConstrainedContent(
            maxWidth: 600,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                SettingsGroup(
                  title: 'Sections',
                  footer: vm.isOwner
                      ? 'Feed, Schedule, Chat and Roster are always on. '
                            'Turned-off sections are hidden from everyone '
                            'on the team; turning one back on brings back '
                            'what it had.'
                      : 'Only the owner can turn sections on or off.',
                  children: [
                    for (final s in OptionalSection.values)
                      SwitchListTile(
                        key: ValueKey('section-${s.name}'),
                        title: Text(s.label),
                        subtitle: Text(s.description),
                        value: vm.isOn(s),
                        onChanged: vm.isOwner && !busy
                            ? (on) => vm.setSection.execute((s, on))
                            : null,
                      ),
                  ],
                ),
                if (vm.hasPublicPage)
                  SettingsGroup(
                    title: 'Visibility',
                    footer: vm.canManage
                        ? null
                        : "Only the team's admins can change this.",
                    children: [
                      SwitchListTile(
                        key: const ValueKey('public-page'),
                        title: const Text('Public team page'),
                        subtitle: const Text(publicPageDescription),
                        value: vm.publicPage,
                        onChanged: vm.canManage && !vm.setPublicPage.running
                            ? vm.setPublicPage.execute
                            : null,
                      ),
                      if (vm.hasJoinRequests)
                        SwitchListTile(
                          key: const ValueKey('allow-join-requests'),
                          title: const Text('Allow join requests'),
                          subtitle: const Text(allowJoinRequestsDescription),
                          value: vm.allowJoinRequests,
                          onChanged:
                              vm.canManage && !vm.setAllowJoinRequests.running
                              ? _setJoinRequests
                              : null,
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
