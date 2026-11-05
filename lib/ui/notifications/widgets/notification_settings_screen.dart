import 'package:flutter/material.dart';

import '../../../domain/models/notification.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/notification_settings_viewmodel.dart';
import 'notifications_screen.dart';

/// Push on this device, what to be notified about, and per-team overrides.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, required this.viewModel});

  final NotificationSettingsViewModel viewModel;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  NotificationSettingsViewModel get vm => widget.viewModel;

  late final List<Command<Object?>> _commands = [
    vm.enablePush,
    vm.setCategory,
    vm.setTeamCategory,
    vm.resetTeam,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
  }

  @override
  void dispose() {
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
    super.dispose();
  }

  void _onCommand() {
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (!vm.loaded) return const LoadingView();
          final theme = Theme.of(context);
          Widget heading(String text) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(text, style: theme.textTheme.titleSmall),
          );
          final prefs = vm.prefs;
          final off = vm.pushOff;
          return ConstrainedContent(
            maxWidth: 600,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                heading('This device'),
                _PushTile(viewModel: vm),
                heading('Notify me about'),
                if (off)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Turn on notifications above to choose what you get. '
                      'Everything still shows under the bell in the app.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                for (final category in NotificationCategory.values)
                  SwitchListTile(
                    secondary: Icon(categoryIcon(category)),
                    title: Text(category.label),
                    subtitle: Text(category.description),
                    value: !off && prefs.isOn(category),
                    onChanged: off
                        ? null
                        : (on) => vm.setCategory.execute((category, on)),
                  ),
                if (vm.teams.isNotEmpty && !off) ...[
                  heading('Teams'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Change these for one team. To mute a single chat '
                      "room, use the room's ⋮ menu.",
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  for (final team in vm.teams)
                    _TeamOverrides(viewModel: vm, team: team),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PushTile extends StatelessWidget {
  const _PushTile({required this.viewModel});

  final NotificationSettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final busy = vm.enablePush.running;
    return switch (vm.pushStatus) {
      null => const ListTile(
        leading: Icon(Icons.notifications_outlined),
        title: Text('Checking push notifications…'),
      ),
      PushStatus.unsupported => const ListTile(
        leading: Icon(Icons.desktop_windows_outlined),
        title: Text("Push notifications aren't available on Windows"),
        subtitle: Text(
          'You still get everything under the bell on Home, and on your '
          'phone if Stall 10 is installed there.',
        ),
      ),
      PushStatus.enabled => ListTile(
        leading: Icon(Icons.notifications_active_outlined, color: c.accent),
        title: const Text('Push notifications are on'),
        subtitle: const Text(
          'Choose what you get below. Turn them off for Stall 10 in your '
          "device's settings.",
        ),
      ),
      PushStatus.notDetermined => _OffCard(
        title: 'Notifications are off on this phone',
        body:
            'Turn them on to hear about messages, events and your teams '
            'when Stall 10 is closed. Busy chats send one notification, '
            'not one per message.',
        action: FilledButton(
          onPressed: busy ? null : vm.enablePush.execute,
          child: const Text('Turn on notifications'),
        ),
      ),
      PushStatus.denied => _OffCard(
        title: 'Notifications are off on this phone',
        body:
            "Turn on notifications for Stall 10 in your phone's Settings "
            'app, then come back here.',
        action: OutlinedButton(
          onPressed: busy ? null : vm.enablePush.execute,
          child: const Text('Check again'),
        ),
      ),
    };
  }
}

/// The push tile when push is off: says so plainly, with the way to fix it.
class _OffCard extends StatelessWidget {
  const _OffCard({
    required this.title,
    required this.body,
    required this.action,
  });

  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card.filled(
        color: theme.colorScheme.secondaryContainer,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications_off_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(body, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              action,
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamOverrides extends StatelessWidget {
  const _TeamOverrides({required this.viewModel, required this.team});

  final NotificationSettingsViewModel viewModel;
  final Team team;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final prefs = vm.prefs;
    final custom = prefs.hasOverrides(team.id);
    return ExpansionTile(
      leading: const Icon(Icons.groups_outlined),
      title: Text(team.name),
      subtitle: Text(custom ? 'Custom for this team' : 'Using your defaults'),
      children: [
        for (final category in NotificationCategory.teamCategories)
          SwitchListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: Text(category.label),
            value: prefs.isOnFor(category, team.id),
            onChanged: (on) =>
                vm.setTeamCategory.execute((team.id, category, on)),
          ),
        if (custom)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextButton(
                onPressed: () => vm.resetTeam.execute(team.id),
                child: const Text('Use my defaults'),
              ),
            ),
          ),
      ],
    );
  }
}
