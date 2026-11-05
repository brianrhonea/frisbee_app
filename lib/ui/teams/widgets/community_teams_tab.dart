import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/community_teams_viewmodel.dart';

/// A school or club community's teams. Members see which ones their roles
/// put them on; admins add teams, answer teams asking to join, and choose
/// which roles get on each.
class CommunityTeamsTab extends StatefulWidget {
  const CommunityTeamsTab({super.key, required this.viewModel});

  final CommunityTeamsViewModel viewModel;

  @override
  State<CommunityTeamsTab> createState() => _CommunityTeamsTabState();
}

class _CommunityTeamsTabState extends State<CommunityTeamsTab> {
  CommunityTeamsViewModel get vm => widget.viewModel;

  late final List<Command<void>> _commands = [
    vm.accept,
    vm.decline,
    vm.saveAccess,
    vm.unlink,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
    vm.createTeam.addListener(_onCreated);
  }

  @override
  void dispose() {
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
    vm.createTeam.removeListener(_onCreated);
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

  void _onCreated() {
    final cmd = vm.createTeam;
    switch (cmd.result) {
      case Ok<String>(:final value):
        cmd.clearResult();
        context.push(Routes.team(value));
      case Error<String>():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  Future<void> _newTeam() async {
    final made = await showDialog<NewCommunityTeam>(
      context: context,
      builder: (_) => _NewTeamDialog(viewModel: vm),
    );
    if (made != null) vm.createTeam.execute(made);
  }

  Future<void> _accept(TeamLinkRequest r) async {
    final access = await pickTeamAccess(
      context,
      viewModel: vm,
      teamName: r.teamName,
      title: 'Add ${r.teamName}',
      confirmLabel: 'Add team',
    );
    if (access != null) vm.accept.execute((request: r, access: access));
  }

  Future<void> _editAccess(LinkedTeam t) async {
    final access = await pickTeamAccess(
      context,
      viewModel: vm,
      teamName: t.name,
      initial: t.roles,
      title: 'Who gets on ${t.name}',
      confirmLabel: 'Save',
    );
    if (access != null) vm.saveAccess.execute((t, access));
  }

  Future<void> _unlink(LinkedTeam t) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove ${t.name}?',
      message:
          "It stays a team, but it's no longer part of "
          '${vm.org?.name ?? 'the community'}. People who got on it '
          'through a role here leave it; people its own admins added stay.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (ok) vm.unlink.execute(t.id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.createTeam]),
    builder: (context, _) {
      if (!vm.loaded) return const LoadingView();
      final org = vm.org;
      if (org == null) return ErrorView(error: vm.error);
      final theme = Theme.of(context);
      final teams = vm.teams;
      return ConstrainedContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              vm.canManage
                  ? 'Each team here is a full team with its own roster, '
                        'playbook, stats, events and chat. Members with a '
                        "team's roles join it automatically, and leave it "
                        'when they lose them.'
                  : 'Your roles here decide which teams you are on. Ask an '
                        "admin for a team's role to join it.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (vm.canManage) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: vm.full || vm.createTeam.running ? null : _newTeam,
                  icon: const Icon(Icons.add),
                  label: const Text('New team'),
                ),
              ),
            ],
            if (vm.requests.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Requests(
                requests: vm.requests,
                onAccept: _accept,
                onDecline: (r) => vm.decline.execute(r.teamId),
              ),
            ],
            const SizedBox(height: 16),
            if (teams.isEmpty)
              EmptyView(
                icon: Icons.shield_outlined,
                title: 'No teams yet',
                message: vm.canManage
                    ? 'Make a team here, or have an existing team ask to '
                          'join from its own menu (Community).'
                    : "When the community's admins add teams, they show "
                          'up here.',
              )
            else ...[
              Text(
                '${teams.length} team${teams.length == 1 ? '' : 's'}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final t in teams)
                _TeamTile(
                  team: t,
                  on: vm.isOn(t),
                  joining: vm.isJoining(t),
                  roleNames: vm.roleNames(t),
                  onOpen: () => context.push(Routes.team(t.id)),
                  onEditAccess: vm.canManage ? () => _editAccess(t) : null,
                  onUnlink: vm.canManage ? () => _unlink(t) : null,
                ),
            ],
          ],
        ),
      );
    },
  );
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({
    required this.team,
    required this.on,
    required this.joining,
    required this.roleNames,
    required this.onOpen,
    this.onEditAccess,
    this.onUnlink,
  });

  final LinkedTeam team;
  final bool on;
  final bool joining;
  final List<String> roleNames;
  final VoidCallback onOpen;
  final VoidCallback? onEditAccess;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = roleNames.isEmpty
        ? 'No role gets on it yet'
        : 'For ${roleNames.join(', ')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onOpen,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.shield_outlined,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(team.name),
        subtitle: Text('${team.division.label} · $who'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (on || joining)
              Chip(
                label: Text(on ? "You're on it" : 'Joining…'),
                visualDensity: VisualDensity.compact,
                side: BorderSide.none,
                backgroundColor: theme.colorScheme.secondaryContainer,
              ),
            if (onEditAccess != null)
              PopupMenuButton<String>(
                tooltip: 'Team options',
                onSelected: (v) =>
                    (v == 'access' ? onEditAccess : onUnlink)?.call(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'access', child: Text('Who gets on it')),
                  PopupMenuItem(
                    value: 'unlink',
                    child: Text('Remove from community'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Requests extends StatelessWidget {
  const _Requests({
    required this.requests,
    required this.onAccept,
    required this.onDecline,
  });

  final List<TeamLinkRequest> requests;
  final ValueChanged<TeamLinkRequest> onAccept;
  final ValueChanged<TeamLinkRequest> onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              requests.length == 1
                  ? '1 team wants to join'
                  : '${requests.length} teams want to join',
              style: theme.textTheme.titleSmall,
            ),
            for (final r in requests)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.teamName),
                subtitle: Text(
                  [
                    r.division.label,
                    if (r.requestedByName.isNotEmpty)
                      'asked by ${r.requestedByName}',
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => onDecline(r),
                      child: const Text('Decline'),
                    ),
                    FilledButton(
                      onPressed: () => onAccept(r),
                      child: const Text('Add'),
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

/// Asks which community roles get on [teamName]; null if cancelled.
Future<TeamAccess?> pickTeamAccess(
  BuildContext context, {
  required CommunityTeamsViewModel viewModel,
  required String teamName,
  required String title,
  required String confirmLabel,
  Set<String> initial = const {},
}) => showDialog<TeamAccess>(
  context: context,
  builder: (_) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 420,
      child: _AccessPicker(
        viewModel: viewModel,
        teamName: teamName,
        initial: initial,
        confirmLabel: confirmLabel,
      ),
    ),
  ),
);

/// Role checkboxes, and for the owner a new role (named after the team
/// when no role is), then Cancel and [confirmLabel], which pop the choice.
class _AccessPicker extends StatefulWidget {
  const _AccessPicker({
    required this.viewModel,
    required this.teamName,
    required this.initial,
    required this.confirmLabel,
    this.onDone,
  });

  final CommunityTeamsViewModel viewModel;
  final String teamName;
  final Set<String> initial;
  final String confirmLabel;

  /// Instead of popping, e.g. inside the new team dialog.
  final ValueChanged<TeamAccess>? onDone;

  @override
  State<_AccessPicker> createState() => _AccessPickerState();
}

class _AccessPickerState extends State<_AccessPicker> {
  late final Set<String> _picked = {...widget.initial};
  late final bool _named = widget.viewModel.roles.any(
    (r) => r.name.toLowerCase() == widget.teamName.trim().toLowerCase(),
  );
  late bool _makeRole =
      widget.viewModel.canMakeRoles && !_named && widget.initial.isEmpty;
  late final _newRole = TextEditingController(text: widget.teamName.trim());

  @override
  void dispose() {
    _newRole.dispose();
    super.dispose();
  }

  TeamAccess get _access => (
    roles: _picked,
    newRole: _makeRole && _newRole.text.trim().isNotEmpty
        ? _newRole.text.trim()
        : null,
  );

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Members with any of these roles join the team. Give out roles '
          'from Members.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final r in vm.roles)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.name),
                  value: _picked.contains(r.id),
                  onChanged: (v) => setState(
                    () => v! ? _picked.add(r.id) : _picked.remove(r.id),
                  ),
                ),
              if (vm.canMakeRoles) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('A new role'),
                  value: _makeRole,
                  onChanged: (v) => setState(() => _makeRole = v!),
                ),
                if (_makeRole)
                  TextField(
                    controller: _newRole,
                    maxLength: CustomRole.maxNameLength,
                    decoration: const InputDecoration(labelText: 'Role name'),
                  ),
              ] else if (vm.roles.isEmpty)
                Text(
                  'There are no roles yet. The owner makes them in Members '
                  '→ Roles.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final done = widget.onDone;
                if (done != null) {
                  done(_access);
                } else {
                  Navigator.pop(context, _access);
                }
              },
              child: Text(widget.confirmLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _NewTeamDialog extends StatefulWidget {
  const _NewTeamDialog({required this.viewModel});

  final CommunityTeamsViewModel viewModel;

  @override
  State<_NewTeamDialog> createState() => _NewTeamDialogState();
}

class _NewTeamDialogState extends State<_NewTeamDialog> {
  final _name = TextEditingController();
  Division _division = Division.open;
  String? _nameError;

  /// Past the name, to pick who gets on it.
  bool _naming = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _next() {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Enter a team name');
      return;
    }
    setState(() => _naming = false);
  }

  @override
  Widget build(BuildContext context) {
    final org = widget.viewModel.org;
    return AlertDialog(
      title: Text(_naming ? 'New team' : 'Who gets on ${_name.text.trim()}'),
      content: SizedBox(
        width: 420,
        child: _naming
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _name,
                    autofocus: true,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Team name',
                      hintText: 'e.g. Woof',
                      errorText: _nameError,
                    ),
                    onSubmitted: (_) => _next(),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Division>(
                    initialValue: _division,
                    decoration: const InputDecoration(labelText: 'Division'),
                    items: [
                      for (final d in Division.values)
                        DropdownMenuItem(value: d, child: Text(d.label)),
                    ],
                    onChanged: (v) => setState(() => _division = v!),
                  ),
                ],
              )
            : _AccessPicker(
                viewModel: widget.viewModel,
                teamName: _name.text,
                initial: const {},
                confirmLabel: 'Create team',
                onDone: (access) => Navigator.pop(context, (
                  team: NewTeam(
                    name: _name.text.trim(),
                    division: _division,
                    level: org?.level ?? CompetitionLevel.college,
                    city: org?.city ?? '',
                  ),
                  access: access,
                )),
              ),
      ),
      actions: _naming
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: _next, child: const Text('Next')),
            ]
          : null,
    );
  }
}
