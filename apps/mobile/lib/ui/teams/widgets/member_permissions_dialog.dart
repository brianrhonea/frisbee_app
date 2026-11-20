import 'package:flutter/material.dart';

import '../../../domain/models/team.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';

/// The owner's per-person permission switches for [uid]: a preset in one
/// tap (Member, Captain, Coach, ...), then a switch per permission with
/// its one-line description. Changing a switch so no preset matches shows
/// "Custom". Permissions a custom role already gives are on and locked,
/// naming the role. Returns the member's own permissions, or null when
/// cancelled.
Future<Set<TeamPermission>?> showMemberPermissions(
  BuildContext context, {
  required Team team,
  required String uid,
}) => showDialog<Set<TeamPermission>>(
  context: context,
  builder: (_) => MemberPermissionsDialog(team: team, uid: uid),
);

class MemberPermissionsDialog extends StatefulWidget {
  const MemberPermissionsDialog({
    super.key,
    required this.team,
    required this.uid,
  });

  final Team team;
  final String uid;

  @override
  State<MemberPermissionsDialog> createState() =>
      _MemberPermissionsDialogState();
}

class _MemberPermissionsDialogState extends State<MemberPermissionsDialog> {
  late Set<TeamPermission> _own = widget.team.ownPermissionsOf(widget.uid);

  bool get _isGroup => widget.team.isCommunity;

  /// Which of the member's roles give [p], by name.
  List<String> _rolesGiving(TeamPermission p) => [
    for (final r in widget.team.rolesOf(widget.uid))
      if (r.permissions.contains(p)) r.name,
  ];

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final team = widget.team;
    final name = team.nameOf(widget.uid);
    final preset = RolePreset.matching(_own, _isGroup);
    final fromRoles = team.rolePermissionsOf(widget.uid);
    return AlertDialog(
      title: Text('Permissions for $name'),
      content: SizedBox(
        width: 440,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Eyebrow('Start from a preset'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in RolePreset.forGroup(_isGroup))
                  ChoiceChip(
                    label: Text(p.name),
                    selected: preset?.id == p.id,
                    tooltip: p.summary,
                    onSelected: (_) =>
                        setState(() => _own = {...p.permissions}),
                  ),
                if (preset == null)
                  const ChoiceChip(
                    label: Text('Custom'),
                    selected: true,
                    onSelected: null,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              preset?.summary ?? 'Your own mix of the permissions below.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
            const SizedBox(height: 14),
            const Eyebrow('Permissions'),
            for (final p in TeamPermission.forGroup(_isGroup))
              if (_rolesGiving(p) case final roles when roles.isNotEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: true,
                  onChanged: null,
                  title: Text(p.label),
                  subtitle: Text(
                    '${p.summary}. From the ${roles.join(', ')} '
                    '${roles.length == 1 ? 'role' : 'roles'}.',
                  ),
                )
              else
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _own.contains(p),
                  onChanged: (on) => setState(
                    () => _own = on ? {..._own, p} : ({..._own}..remove(p)),
                  ),
                  title: Text(p.label),
                  subtitle: Text(p.summary),
                ),
            if (fromRoles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Locked switches come from their roles; change those '
                  'under Assign roles.',
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Role-given permissions stay with the role, not the person.
          onPressed: () => Navigator.pop(context, {
            for (final p in TeamPermission.forGroup(_isGroup))
              if (_own.contains(p)) p,
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
