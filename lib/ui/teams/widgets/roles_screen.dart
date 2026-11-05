import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/roles_viewmodel.dart';

/// The owner's custom roles, top first, like Discord's role list.
class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key, required this.viewModel});

  final RolesViewModel viewModel;

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  RolesViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    for (final c in [vm.save, vm.delete, vm.shift]) {
      c.addListener(_onCommand);
    }
  }

  @override
  void dispose() {
    for (final c in [vm.save, vm.delete, vm.shift]) {
      c.removeListener(_onCommand);
    }
    super.dispose();
  }

  void _onCommand() {
    for (final c in [vm.save, vm.delete, vm.shift]) {
      if (c.error) {
        final result = c.result;
        c.clearResult();
        showErrorSnackBar(context, result);
      }
    }
  }

  Future<void> _edit(CustomRole? role) async {
    final edited = await showDialog<CustomRole>(
      context: context,
      builder: (_) => RoleDialog(
        role: role ?? const CustomRole(id: '', name: ''),
        permissions: vm.permissions,
      ),
    );
    if (edited != null) await vm.save.execute(edited);
  }

  Future<void> _delete(CustomRole role) async {
    final count = vm.memberCount(role.id);
    if (await confirmDialog(
      context,
      title: 'Delete ${role.name}?',
      message: count == 0
          ? 'Rooms that let this role in will no longer list it.'
          : '$count ${count == 1 ? 'member loses' : 'members lose'} it, '
                'and rooms that let it in will no longer list it.',
      confirmLabel: 'Delete role',
      destructive: true,
    )) {
      await vm.delete.execute(role.id);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final team = vm.team;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Roles'),
          actions: [
            if (vm.isOwner && team != null)
              TextButton.icon(
                onPressed: () => context.push(Routes.discordImport(team.id)),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Import from Discord'),
              ),
          ],
        ),
        floatingActionButton: vm.canAdd
            ? FloatingActionButton.extended(
                onPressed: () => _edit(null),
                icon: const Icon(Icons.add),
                label: const Text('New role'),
              )
            : null,
        body: !vm.loaded
            ? const LoadingView()
            : team == null
            ? ErrorView(error: vm.error)
            : ConstrainedContent(
                maxWidth: 720,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    Text(
                      team.isCommunity
                          ? 'Roles give members extra powers and open chat '
                                'rooms to them. The owner can do everything.'
                          : 'Roles give players extra powers and open chat '
                                'rooms to them, on top of Coach, Captain and '
                                'Player. The owner can do everything.',
                      style: TextStyle(color: AppColors.of(context).muted),
                    ),
                    const SizedBox(height: 16),
                    if (vm.roles.isEmpty)
                      const EmptyView(
                        icon: Icons.label_outline,
                        title: 'No roles yet',
                        message:
                            'Make roles like Handlers, Organizers or '
                            'Carpool, then give them to members on the '
                            'Members tab.',
                      ),
                    for (final (i, r) in vm.roles.indexed)
                      _RoleTile(
                        role: r,
                        summary: vm.summaryOf(r),
                        members: vm.memberCount(r.id),
                        menu: vm.isOwner
                            ? PopupMenuButton<String>(
                                tooltip: 'Role options',
                                onSelected: (a) => switch (a) {
                                  'edit' => _edit(r),
                                  'up' => vm.shift.execute((id: r.id, by: -1)),
                                  'down' => vm.shift.execute((id: r.id, by: 1)),
                                  _ => _delete(r),
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  if (i > 0)
                                    const PopupMenuItem(
                                      value: 'up',
                                      child: Text('Move up'),
                                    ),
                                  if (i < vm.roles.length - 1)
                                    const PopupMenuItem(
                                      value: 'down',
                                      child: Text('Move down'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              )
                            : null,
                      ),
                  ],
                ),
              ),
      );
    },
  );
}

/// A colored dot for a role; outlined when it has no color.
class RoleDot extends StatelessWidget {
  const RoleDot({super.key, required this.color, this.size = 12});

  final int color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color == 0 ? null : Color(color),
      border: color == 0
          ? Border.all(color: AppColors.of(context).muted, width: 1.5)
          : null,
    ),
  );
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.role,
    required this.summary,
    required this.members,
    this.menu,
  });

  final CustomRole role;
  final String summary;
  final int members;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: RoleDot(color: role.color, size: 16),
        title: Text(
          role.name,
          style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
        ),
        subtitle: Text(
          '$summary · $members ${members == 1 ? 'member' : 'members'}',
          style: TextStyle(color: c.muted),
        ),
        trailing: menu,
      ),
    );
  }
}

/// A role's name, color and permissions.
class RoleDialog extends StatefulWidget {
  const RoleDialog({super.key, required this.role, required this.permissions});

  final CustomRole role;
  final List<TeamPermission> permissions;

  @override
  State<RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<RoleDialog> {
  late CustomRole _draft = widget.role;
  late final _name = TextEditingController(text: widget.role.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      title: Text(widget.role.isNew ? 'New role' : 'Edit role'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: CustomRole.maxNameLength,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Role name',
                  hintText: 'e.g. Handlers, Organizers',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text('Color', style: TextStyle(color: c.muted, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in roleColors)
                    InkResponse(
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(color: color),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _draft.color == color
                                ? c.ink
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: RoleDot(color: color, size: 22),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Permissions',
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
              for (final p in widget.permissions)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _draft.permissions.contains(p),
                  title: Text(p.label),
                  subtitle: Text(p.summary),
                  onChanged: (on) => setState(
                    () => _draft = _draft.copyWith(
                      permissions: on ?? false
                          ? {..._draft.permissions, p}
                          : ({..._draft.permissions}..remove(p)),
                    ),
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
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  _draft.copyWith(name: _name.text.trim()),
                ),
          child: Text(widget.role.isNew ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
