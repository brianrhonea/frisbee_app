import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/chat.dart';
import '../../../domain/models/discord_import.dart';
import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/discord_import_viewmodel.dart';
import 'roles_screen.dart';

/// Imports roles, categories and text channels from a Discord server
/// template link.
class DiscordImportScreen extends StatefulWidget {
  const DiscordImportScreen({super.key, required this.viewModel});

  final DiscordImportViewModel viewModel;

  @override
  State<DiscordImportScreen> createState() => _DiscordImportScreenState();
}

class _DiscordImportScreenState extends State<DiscordImportScreen> {
  DiscordImportViewModel get vm => widget.viewModel;
  final _link = TextEditingController();

  @override
  void initState() {
    super.initState();
    vm.apply.addListener(_onApply);
  }

  @override
  void dispose() {
    vm.apply.removeListener(_onApply);
    _link.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final moving = vm.moving;
    if (moving.isNotEmpty) {
      final ok = await confirmDialog(
        context,
        title:
            'Move ${moving.length} room${moving.length == 1 ? '' : 's'} '
            'to teams?',
        message:
            'These are in the community chat now and will be deleted there '
            'once their team has them, with any messages in them: '
            '${moving.map((r) => '#${r.name}').join(', ')}.',
        confirmLabel: 'Move and import',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    vm.apply.execute();
  }

  void _onApply() {
    if (vm.apply.completed) {
      vm.apply.clearResult();
      showSnackBar(context, 'Imported from Discord.');
    } else if (vm.apply.error) {
      final result = vm.apply.result;
      vm.apply.clearResult();
      showErrorSnackBar(context, result);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.preview, vm.apply]),
    builder: (context, _) {
      final c = AppColors.of(context);
      final import = vm.import;
      final busy = vm.preview.running || vm.apply.running;
      return Scaffold(
        appBar: AppBar(title: const Text('Import from Discord')),
        body: !vm.loaded
            ? (vm.error != null
                  ? ErrorView(error: vm.error)
                  : const LoadingView())
            : !vm.isOwner
            ? const EmptyView(
                icon: Icons.lock_outline,
                title: 'Owner only',
                message: 'Only the owner can import from Discord.',
              )
            : ConstrainedContent(
                maxWidth: 720,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (busy) const LinearProgressIndicator(),
                    Text(
                      'Copy your Discord server\'s roles, categories and text '
                      'channels. In Discord, open Server Settings → Server '
                      'Template, create a template, and paste its link '
                      'here. Members and messages aren\'t copied: give '
                      'people their roles on the Members tab.',
                      style: TextStyle(color: c.muted),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _link,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Server template link',
                        hintText: 'https://discord.new/…',
                        prefixIcon: Icon(Icons.link),
                      ),
                      onChanged: vm.setLink,
                      onSubmitted: (_) {
                        if (vm.canPreview) vm.preview.execute();
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: vm.canPreview ? vm.preview.execute : null,
                        icon: const Icon(Icons.preview_outlined),
                        label: const Text('Preview'),
                      ),
                    ),
                    if (vm.preview.error) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage(vm.preview.result),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (vm.plan case final plan? when import != null) ...[
                      if (vm.split case final split?) ...[
                        const SizedBox(height: 24),
                        _TeamSorting(viewModel: vm, plan: plan, split: split),
                      ],
                      const SizedBox(height: 24),
                      if (vm.split != null)
                        Text(
                          'Community chat',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      _Preview(
                        plan: plan,
                        import: import,
                        label: (id) => vm.audienceLabel(id, import),
                      ),
                      const SizedBox(height: 16),
                      if (vm.done)
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: c.accent),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('Imported.')),
                            TextButton(
                              onPressed: () =>
                                  context.go(Routes.teamChat(vm.teamId)),
                              child: const Text('Open chat'),
                            ),
                          ],
                        )
                      else
                        FilledButton.icon(
                          onPressed: vm.canApply ? _import : null,
                          icon: const Icon(Icons.download_done),
                          label: Text(
                            vm.canApply ? 'Import' : 'Nothing new to import',
                          ),
                        ),
                    ],
                  ],
                ),
              ),
      );
    },
  );
}

/// What the import would add, with each room's access.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.plan,
    required this.import,
    required this.label,
  });

  final DiscordImportPlan plan;
  final DiscordImport import;
  final String Function(String) label;

  String _access(ChatAccessLists a) {
    final read = a.readRoles.map(label).join(', ');
    final write = a.writeRoles.map(label).join(', ');
    if (read.isEmpty) return 'Owner only';
    if (read == write) return read;
    return 'Read: $read · Write: ${write.isEmpty ? 'owner only' : write}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final folderNames = {for (final f in import.folders) f.id: f.name};
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    Widget note(String text) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text, style: TextStyle(color: c.muted, fontSize: 13)),
    );
    final newRoles = [
      for (final r in import.roles.values)
        if (import.newRoles.contains(r.name)) r,
    ]..sort((a, b) => a.position.compareTo(b.position));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(plan.serverName, style: theme.textTheme.titleLarge),
        heading('Roles (${newRoles.length} new)'),
        if (newRoles.isEmpty) note('No new roles.'),
        for (final r in newRoles)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: RoleDot(color: r.color, size: 14),
            title: Text(r.name),
            subtitle: Text(
              r.permissions.isEmpty
                  ? 'No permissions'
                  : r.permissions.map((p) => p.label).join(', '),
            ),
          ),
        if (import.tooManyRoles.isNotEmpty)
          note(
            'Left out (a team has up to ${CustomRole.maxRoles} roles): '
            '${import.tooManyRoles.join(', ')}',
          ),
        heading(
          'Folders (${import.folders.length} new) and rooms '
          '(${import.rooms.length} new)',
        ),
        for (final f in import.folders) note('📁 ${f.name}'),
        for (final r in import.rooms)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tag, size: 18),
            title: Text(
              r.folderId == null
                  ? r.name
                  : '${folderNames[r.folderId] ?? 'Existing folder'} / '
                        '${r.name}',
            ),
            subtitle: Text(_access(r)),
          ),
        if (import.alreadyHere.isNotEmpty)
          note('Already here: ${import.alreadyHere.join(', ')}'),
        if (plan.skippedChannels.isNotEmpty)
          note('Not imported: ${plan.skippedChannels.join(', ')}'),
      ],
    );
  }
}

/// In a community with teams: where each room goes, what each team gets,
/// and which community rooms move.
class _TeamSorting extends StatelessWidget {
  const _TeamSorting({
    required this.viewModel,
    required this.plan,
    required this.split,
  });

  final DiscordImportViewModel viewModel;
  final DiscordImportPlan plan;
  final DiscordTeamSplit split;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final folders = {for (final f in plan.folders) f.key: f.name};
    Widget note(String text) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text, style: TextStyle(color: c.muted, fontSize: 13)),
    );
    final moving = vm.moving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Where rooms go', style: theme.textTheme.titleMedium),
        note(
          "Rooms only one team's roles can read go to that team's chat; "
          'the rest stay in the community. Change any of them here.',
        ),
        if (vm.otherTeams.isNotEmpty)
          note(
            "Only a team's owner can add rooms to it, so rooms for "
            '${vm.otherTeams.map((t) => t.name).join(', ')} stay in the '
            'community.',
          ),
        const SizedBox(height: 8),
        for (var i = 0; i < plan.rooms.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tag, size: 18),
            title: Text(
              [
                ?folders[plan.rooms[i].folderKey],
                plan.rooms[i].name,
              ].join(' / '),
            ),
            trailing: DropdownButton<String?>(
              value: split.destinations[i],
              onChanged: (v) => vm.setDestination(i, v),
              items: [
                const DropdownMenuItem(value: null, child: Text('Community')),
                for (final t in vm.teamChoices)
                  DropdownMenuItem(value: t.id, child: Text(t.name)),
              ],
            ),
          ),
        for (final t in vm.teamImports)
          Card(
            margin: const EdgeInsets.only(top: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.team.name} chat',
                    style: theme.textTheme.titleSmall,
                  ),
                  note(
                    t.isEmpty
                        ? 'Already has everything.'
                        : '${t.import.rooms.length} new room'
                              '${t.import.rooms.length == 1 ? '' : 's'}'
                              '${t.import.folders.isEmpty ? '' : ' in ${t.import.folders.map((f) => f.name).join(', ')}'}'
                              '${t.import.alreadyHere.isEmpty ? '' : '; already there: ${t.import.alreadyHere.join(', ')}'}.',
                  ),
                  note(
                    'Team roles kept in step with the community: '
                    '${[for (final id in t.orgRoles.keys) ?t.import.roles[id]?.name].join(', ')}.',
                  ),
                  for (final r in t.import.rooms)
                    note(
                      '#${r.name}: '
                      '${r.readRoles.contains(ChatAudience.everyone) ? 'the whole team' : r.readRoles.map((id) => t.import.roles[id]?.name ?? 'owner only').join(', ')}',
                    ),
                ],
              ),
            ),
          ),
        if (moving.isNotEmpty)
          note(
            'Moving out of the community chat: '
            '${moving.map((r) => '#${r.name}').join(', ')}.',
          ),
      ],
    );
  }
}
