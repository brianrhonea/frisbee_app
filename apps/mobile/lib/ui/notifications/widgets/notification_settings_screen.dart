import 'package:flutter/material.dart';

import '../../../domain/models/notification.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/notification_settings_viewmodel.dart';
import '../../settings/widgets/settings_widgets.dart';

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

  /// The heading each category sits under.
  static String _section(NotificationCategory c) => switch (c) {
    NotificationCategory.directMessages ||
    NotificationCategory.chat => 'Messages',
    NotificationCategory.eventChanges ||
    NotificationCategory.eventReminders ||
    NotificationCategory.teamActivity ||
    NotificationCategory.meetings => 'Teams and events',
    NotificationCategory.posts || NotificationCategory.social => 'Social',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: settingsAppBar(
        context,
        title: const Text('Notification settings'),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (!vm.loaded) return const LoadingView();
          final prefs = vm.prefs;
          final off = vm.pushOff;
          // Messages first, as in the mockups; each heading once, in order.
          final sections = <String, List<NotificationCategory>>{};
          for (final category in [
            NotificationCategory.directMessages,
            ...NotificationCategory.values.where(
              (c) => c != NotificationCategory.directMessages,
            ),
          ]) {
            (sections[_section(category)] ??= []).add(category);
          }
          return ConstrainedContent(
            maxWidth: 600,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _PushTile(viewModel: vm),
                if (off)
                  const SettingsFooter(
                    'Turn on notifications above to choose what you get. '
                    'Everything still shows under the bell in the app.',
                  ),
                for (final MapEntry(key: title, value: categories)
                    in sections.entries)
                  SettingsGroup(
                    title: title,
                    children: [
                      for (final category in categories)
                        SwitchListTile(
                          title: Text(category.label, style: _rowTitle),
                          subtitle: Text(
                            category.description,
                            style: const TextStyle(fontSize: 12),
                          ),
                          value: !off && prefs.isOn(category),
                          onChanged: off
                              ? null
                              : (on) => vm.setCategory.execute((category, on)),
                        ),
                    ],
                  ),
                if (vm.teams.isNotEmpty && !off)
                  SettingsGroup(
                    title: 'Per team',
                    footer:
                        'Change these for one team. To mute a single chat '
                        "room, use the room's ⋮ menu.",
                    children: [
                      for (final team in vm.teams)
                        _TeamOverrides(viewModel: vm, team: team),
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

const _rowTitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

class _PushTile extends StatelessWidget {
  const _PushTile({required this.viewModel});

  final NotificationSettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final busy = vm.enablePush.running;
    return switch (vm.pushStatus) {
      null => const Card(
        child: ListTile(
          leading: SettingsIcon(Icons.notifications_outlined),
          title: Text('Checking push notifications…'),
        ),
      ),
      PushStatus.unsupported => const Card(
        child: ListTile(
          leading: SettingsIcon(Icons.desktop_windows_outlined),
          title: Text("Push notifications aren't available on Windows"),
          subtitle: Text(
            'You still get everything under the bell on Home, and on your '
            'phone if Stall 10 is installed there.',
          ),
        ),
      ),
      PushStatus.enabled when vm.deviceError != null => _OffCard(
        title: "Notifications can't reach this phone yet",
        body:
            "Notifications are allowed, but this phone couldn't be "
            'registered to receive them:\n${vm.deviceError}',
        action: OutlinedButton(
          onPressed: vm.registerDevice.running
              ? null
              : vm.registerDevice.execute,
          child: const Text('Try again'),
        ),
      ),
      PushStatus.enabled => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: vm.deviceRegistered ? c.positiveSoft : c.accentSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
              child: Icon(
                Icons.notifications_active_outlined,
                size: 20,
                color: vm.deviceRegistered ? c.positive : c.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vm.deviceRegistered
                        ? 'Push notifications are on'
                        : 'Connecting this phone for notifications…',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: vm.deviceRegistered ? c.positive : c.accentInk,
                    ),
                  ),
                  Text(
                    'Choose what you get below. Turn them off for Stall 10 '
                    "in your device's settings.",
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: vm.deviceRegistered ? c.positive : c.accentInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
    final c = AppColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SettingsIcon(Icons.notifications_off_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(fontSize: 14, height: 1.4, color: c.ink2),
            ),
            const SizedBox(height: 12),
            action,
          ],
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
    final c = AppColors.of(context);
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      leading: const SettingsIcon(Icons.groups_outlined),
      title: Text(team.name, style: _rowTitle),
      subtitle: Text(
        custom ? 'Custom for this team' : 'Using your defaults',
        style: TextStyle(
          fontSize: 12,
          fontWeight: custom ? FontWeight.w600 : FontWeight.w400,
          color: custom ? c.accent : c.muted,
        ),
      ),
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
