import 'package:flutter/material.dart';

import '../../../domain/models/team.dart';
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
                if (vm.canViewAs) ...[
                  const Divider(),
                  _ViewAsRolePicker(viewModel: vm),
                ],
                const Divider(),
                const _BrandPreview(),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Developer option: preview the app as each team role.
class _ViewAsRolePicker extends StatelessWidget {
  const _ViewAsRolePicker({required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = viewModel.viewAsRole;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Developer · View as role', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Shows the app as if you had this role on every team. Display '
            'only: the server still checks your real role.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('My roles'),
                selected: selected == null,
                onSelected: (_) => viewModel.setViewAsRole(null),
              ),
              for (final role in TeamRole.values)
                ChoiceChip(
                  label: Text(role.label),
                  selected: selected == role,
                  onSelected: (_) => viewModel.setViewAsRole(role),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Every logo variant side by side, to compare them on a real device.
class _BrandPreview extends StatelessWidget {
  const _BrandPreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Brand preview', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final icon in brandIcons)
                SizedBox(
                  width: 88,
                  child: Column(
                    children: [
                      UltiUpLogo(size: 72, asset: icon.path),
                      const SizedBox(height: 6),
                      Text(
                        icon.label,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
