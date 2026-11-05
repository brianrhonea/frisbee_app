import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show PersonAvatar;
import '../../profile/view_models/profile_viewmodel.dart';
import '../../profile/widgets/delete_account_dialog.dart';
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
                    onTap: () => context.push(Routes.following),
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
      commands: [vm.setReadReceipts],
      child: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SettingsPage(
          title: 'Privacy',
          children: [
            SettingsGroup(
              title: 'Messages',
              footer:
                  "Show people when you've read their messages. Turn it off "
                  "and you won't see theirs either.",
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.done_all),
                  title: const Text('Read receipts'),
                  value: vm.readReceipts,
                  onChanged: vm.setReadReceipts.execute,
                ),
              ],
            ),
            SettingsGroup(
              title: 'Profile',
              footer:
                  'Choose whether others see your stats, teams and games '
                  'with Edit profile on your profile.',
              children: [
                SettingsTile(
                  icon: Icons.visibility_outlined,
                  title: 'What others see',
                  onTap: () => context.go(Routes.profile),
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
