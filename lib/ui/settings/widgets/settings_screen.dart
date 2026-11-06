import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../view_models/device_access_viewmodel.dart';
import 'device_access_group.dart';
import '../../core/ui/view_model_host.dart';
import '../../../data/services/device_permissions.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/player_profile.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show PersonAvatar;
import '../../profile/view_models/profile_viewmodel.dart';
import '../../profile/widgets/delete_account_dialog.dart';
import 'change_password_dialog.dart';
import 'settings_widgets.dart';

/// Names for the appearance choices.
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};

/// Settings, opened from the gear on the user's profile: who they're
/// signed in as, then General, Notifications, Privacy, People and Account,
/// and signing out.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return _CommandErrors(
      commands: [vm.signOut],
      child: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.signOut]),
        builder: (context, _) {
          final user = vm.user;
          return SettingsPage(
            title: 'Settings',
            children: [
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: PersonAvatar(
                    name: user?.label ?? '',
                    photoUrl: user?.photoUrl,
                    radius: 24,
                  ),
                  title: Text(
                    user?.label ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (user?.username case final u?) '@$u',
                      ?user?.email,
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.settingsAccount),
                ),
              ),
              SettingsGroup(
                children: [
                  SettingsTile(
                    icon: Icons.tune,
                    title: 'General',
                    value: themeModeLabel(vm.themeMode),
                    onTap: () => context.push(Routes.settingsGeneral),
                  ),
                  SettingsTile(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    onTap: () => context.push(Routes.notificationSettings),
                  ),
                  SettingsTile(
                    icon: Icons.lock_outline,
                    title: 'Privacy',
                    onTap: () => context.push(Routes.settingsPrivacy),
                  ),
                ],
              ),
              SettingsGroup(
                children: [
                  SettingsTile(
                    icon: Icons.people_outline,
                    title: 'People you follow',
                    onTap: () => context.push(Routes.settingsFollowing),
                  ),
                  SettingsTile(
                    icon: Icons.person_outline,
                    title: 'Account',
                    onTap: () => context.push(Routes.settingsAccount),
                  ),
                ],
              ),
              SettingsGroup(
                children: [
                  SettingsTile(
                    icon: Icons.logout,
                    title: 'Sign out',
                    opensPage: false,
                    onTap: vm.signOut.running
                        ? null
                        : () async {
                            if (await confirmDialog(
                              context,
                              title: 'Sign out?',
                              message: 'Are you sure you want to sign out?',
                              confirmLabel: 'Sign out',
                            )) {
                              vm.signOut.execute();
                            }
                          },
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  '$appName v$appVersion',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.of(context).muted,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// General: how the app looks.
class GeneralSettingsScreen extends StatelessWidget {
  const GeneralSettingsScreen({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return _CommandErrors(
      commands: [vm.setThemeMode],
      child: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SettingsPage(
          title: 'General',
          children: [
            RadioGroup<ThemeMode>(
              groupValue: vm.themeMode,
              onChanged: (m) => vm.setThemeMode.execute(m!),
              child: SettingsGroup(
                title: 'Appearance',
                footer: 'System follows your device’s light or dark mode.',
                children: [
                  for (final mode in ThemeMode.values)
                    RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(themeModeLabel(mode)),
                      secondary: Icon(switch (mode) {
                        ThemeMode.system => Icons.brightness_auto_outlined,
                        ThemeMode.light => Icons.light_mode_outlined,
                        ThemeMode.dark => Icons.dark_mode_outlined,
                      }),
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Privacy: what others see of the user.
class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return _CommandErrors(
      commands: [
        vm.setReadReceipts,
        vm.setMessagePolicy,
        vm.setPrivate,
        vm.setVisibility,
      ],
      child: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.setPrivate]),
        builder: (context, _) => SettingsPage(
          title: 'Privacy',
          children: [
            SettingsGroup(
              title: 'Account privacy',
              footer:
                  'Off: anyone on Stall 10 can see your profile. On: people '
                  'ask to follow you, and only those you accept see your '
                  'posts, bio and what you show below. Everyone still sees '
                  'your name, @username and photo. People who already '
                  'follow you stay.',
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.lock_outline),
                  title: const Text('Private profile'),
                  value: vm.isPrivate ?? false,
                  onChanged: vm.isPrivate == null || vm.setPrivate.running
                      ? null
                      : vm.setPrivate.execute,
                ),
                if ((vm.isPrivate ?? false) || vm.followRequests.isNotEmpty)
                  SettingsTile(
                    icon: Icons.person_add_alt,
                    title: 'Follow requests',
                    value: switch (vm.followRequests.length) {
                      0 => 'None',
                      final n => '$n',
                    },
                    onTap: () => context.push(Routes.followRequests),
                  ),
              ],
            ),
            SettingsGroup(
              title: 'Messages',
              footer:
                  "Read receipts show people when you've read their "
                  "messages. Turn them off and you won't see theirs either. "
                  "Message requests are never marked as read until you "
                  'accept them.',
              children: [
                ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: const Text('Who can message you'),
                  subtitle: Text(vm.messagePolicy.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked = await showDialog<MessagePolicy>(
                      context: context,
                      builder: (_) =>
                          MessagePolicyDialog(selected: vm.messagePolicy),
                    );
                    if (picked != null && picked != vm.messagePolicy) {
                      vm.setMessagePolicy.execute(picked);
                    }
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.done_all),
                  title: const Text('Read receipts'),
                  value: vm.readReceipts,
                  onChanged: vm.setReadReceipts.execute,
                ),
              ],
            ),
            ViewModelHost(
              create: (c) => DeviceAccessViewModel(
                permissions:
                    c.read<DevicePermissions?>() ?? const DevicePermissions(),
              ),
              builder: (_, access) => DeviceAccessGroup(viewModel: access),
            ),
            SettingsGroup(
              title: 'Show on my profile',
              footer:
                  "Turn a section off and it's hidden from everyone, "
                  'followers included. Sections that are on are seen by '
                  '${(vm.isPrivate ?? false) ? 'the followers you accept' : 'anyone on Stall 10'}.',
              children: [
                for (final (icon, label, on, update)
                    in <
                      (
                        IconData,
                        String,
                        bool?,
                        ProfileVisibility Function(ProfileVisibility, bool),
                      )
                    >[
                      (
                        Icons.bar_chart,
                        'Stats',
                        vm.visibility?.stats,
                        (v, x) => v.copyWith(stats: x),
                      ),
                      (
                        Icons.scoreboard_outlined,
                        'Recent games',
                        vm.visibility?.games,
                        (v, x) => v.copyWith(games: x),
                      ),
                      (
                        Icons.groups_outlined,
                        'Teams',
                        vm.visibility?.teams,
                        (v, x) => v.copyWith(teams: x),
                      ),
                    ])
                  SwitchListTile(
                    secondary: Icon(icon),
                    title: Text(label),
                    value: on ?? true,
                    onChanged: switch (vm.visibility) {
                      final v? => (x) => vm.setVisibility.execute(update(v, x)),
                      null => null,
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Account: name, username, email, and deleting the account.
class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  Future<void> _editName(BuildContext context) async {
    final controller = TextEditingController(text: viewModel.user?.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      viewModel.updateDisplayName.execute(name);
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangePasswordDialog(viewModel: viewModel),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password changed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final error = Theme.of(context).colorScheme.error;
    return _CommandErrors(
      commands: [vm.updateDisplayName],
      onDone: {vm.updateDisplayName: 'Name updated'},
      child: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.updateDisplayName]),
        builder: (context, _) {
          final user = vm.user;
          return SettingsPage(
            title: 'Account',
            children: [
              SettingsGroup(
                children: [
                  SettingsTile(
                    icon: Icons.badge_outlined,
                    title: 'Display name',
                    value: user?.displayName ?? '',
                    onTap: vm.updateDisplayName.running
                        ? null
                        : () => _editName(context),
                  ),
                  SettingsTile(
                    icon: Icons.alternate_email,
                    title: 'Username',
                    value: switch (user?.username) {
                      final u? => '@$u',
                      null => 'Not set',
                    },
                    opensPage: false,
                  ),
                  if (user?.email case final email?)
                    SettingsTile(
                      icon: Icons.mail_outline,
                      title: 'Email',
                      value: email,
                      opensPage: false,
                    ),
                  if (vm.hasPassword)
                    SettingsTile(
                      icon: Icons.password,
                      title: 'Change password',
                      onTap: () => _changePassword(context),
                    )
                  else if (vm.reauthMethod case final method?)
                    SettingsTile(
                      icon: Icons.password,
                      title: 'Password',
                      value: switch (method) {
                        SignInMethod.google => 'You sign in with Google',
                        SignInMethod.apple => 'You sign in with Apple',
                        SignInMethod.password => '',
                      },
                      opensPage: false,
                    ),
                ],
              ),
              SettingsGroup(
                footer:
                    'Deletes your profile, posts and messages for good. Teams '
                    'you own pass to another member.',
                children: [
                  SettingsTile(
                    icon: Icons.delete_forever_outlined,
                    title: 'Delete account',
                    color: error,
                    opensPage: false,
                    onTap: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => DeleteAccountDialog(viewModel: vm),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shows [commands]' errors in a snack bar, and [onDone]'s message when
/// one finishes.
class _CommandErrors extends StatefulWidget {
  const _CommandErrors({
    required this.commands,
    this.onDone = const {},
    required this.child,
  });

  final List<Command<void>> commands;
  final Map<Command<void>, String> onDone;
  final Widget child;

  @override
  State<_CommandErrors> createState() => _CommandErrorsState();
}

class _CommandErrorsState extends State<_CommandErrors> {
  @override
  void initState() {
    super.initState();
    for (final c in widget.commands) {
      c.addListener(_onCommand);
    }
  }

  @override
  void dispose() {
    for (final c in widget.commands) {
      c.removeListener(_onCommand);
    }
    super.dispose();
  }

  void _onCommand() {
    for (final c in widget.commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      } else if (c.completed && widget.onDone.containsKey(c)) {
        c.clearResult();
        showSnackBar(context, widget.onDone[c]!);
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Picks who may start a conversation with the user.
class MessagePolicyDialog extends StatefulWidget {
  const MessagePolicyDialog({super.key, required this.selected});

  final MessagePolicy selected;

  @override
  State<MessagePolicyDialog> createState() => _MessagePolicyDialogState();
}

class _MessagePolicyDialogState extends State<MessagePolicyDialog> {
  late MessagePolicy _picked = widget.selected;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Who can message you'),
    contentPadding: const EdgeInsets.only(top: 12),
    content: SingleChildScrollView(
      child: RadioGroup<MessagePolicy>(
        groupValue: _picked,
        onChanged: (p) => setState(() => _picked = p ?? _picked),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in MessagePolicy.values)
              RadioListTile<MessagePolicy>(
                value: p,
                title: Text(p.label),
                subtitle: Text(p.description),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                'People you follow can always message you, unless you '
                'pick No one.',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _picked),
        child: const Text('Save'),
      ),
    ],
  );
}
