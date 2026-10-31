import 'package:flutter/material.dart';

import '../../../utils/command.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/profile_viewmodel.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ProfileViewModel get vm => widget.viewModel;

  late final List<Command<void>> _commands = [
    vm.updateDisplayName,
    vm.signOut,
    vm.deleteAccount,
    vm.setThemeMode,
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
    if (vm.updateDisplayName.completed) {
      vm.updateDisplayName.clearResult();
      showSnackBar(context, 'Name updated');
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: vm.user?.displayName);
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
      vm.updateDisplayName.execute(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          final user = vm.user;
          final theme = Theme.of(context);
          return ConstrainedContent(
            maxWidth: 600,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    child: Text(
                      (user?.label ?? '?')[0].toUpperCase(),
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    user?.label ?? '',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (user?.email != null) Center(child: Text(user!.email!)),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text('Appearance', style: theme.textTheme.titleSmall),
                ),
                _ThemePicker(viewModel: vm),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Change display name'),
                  onTap: _editName,
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  onTap: vm.signOut.execute,
                ),
                const Divider(),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'Delete account',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () async {
                    if (await confirmDialog(
                      context,
                      title: 'Delete your account?',
                      message:
                          'This permanently deletes your account. Teams you '
                          'own are not deleted automatically.',
                      confirmLabel: 'Delete',
                      destructive: true,
                    )) {
                      vm.deleteAccount.execute();
                    }
                  },
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    '$appName v$appVersion',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Light / dark / system theme picker.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_outlined),
            label: Text('System'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined),
            label: Text('Light'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined),
            label: Text('Dark'),
          ),
        ],
        selected: {viewModel.themeMode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => viewModel.setThemeMode.execute(s.first),
      ),
    );
  }
}
