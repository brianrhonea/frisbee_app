import 'package:flutter/material.dart';

import '../../../domain/models/roster_player.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/usau_attribution.dart';
import '../view_models/usau_roster_viewmodel.dart';

/// Link the team to USA Ultimate, then preview and apply a roster sync.
class UsauRosterScreen extends StatefulWidget {
  const UsauRosterScreen({super.key, required this.viewModel});

  final UsauRosterViewModel viewModel;

  @override
  State<UsauRosterScreen> createState() => _UsauRosterScreenState();
}

class _UsauRosterScreenState extends State<UsauRosterScreen> {
  UsauRosterViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    for (final c in [vm.link, vm.unlink, vm.apply]) {
      c.addListener(_onCommand);
    }
  }

  @override
  void dispose() {
    for (final c in [vm.link, vm.unlink, vm.apply]) {
      c.removeListener(_onCommand);
    }
    super.dispose();
  }

  void _onCommand() {
    if (vm.apply.completed) {
      vm.apply.clearResult();
      showSnackBar(context, 'Roster synced with USA Ultimate');
      Navigator.of(context).maybePop();
      return;
    }
    for (final c in [vm.link, vm.unlink, vm.apply]) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final Widget body;
        if (!vm.loaded) {
          body = const LoadingView();
        } else if (vm.team == null) {
          body = ErrorView(error: vm.error);
        } else if (!vm.canEdit) {
          body = const EmptyView(
            icon: Icons.lock_outline,
            title: 'Admins only',
            message: 'Coaches, captains and the owner can sync the roster.',
          );
        } else if (!vm.linked) {
          body = _FindTeam(viewModel: vm);
        } else {
          body = _SyncPreview(viewModel: vm);
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('USA Ultimate roster'),
            actions: [
              if (vm.linked && vm.canEdit)
                IconButton(
                  tooltip: 'Change team',
                  icon: const Icon(Icons.link_off),
                  onPressed: () async {
                    if (await confirmDialog(
                      context,
                      title: 'Unlink USA Ultimate team?',
                      message:
                          'Roster statuses stay as they are until you '
                          'link and sync again.',
                      confirmLabel: 'Unlink',
                    )) {
                      vm.unlink.execute();
                    }
                  },
                ),
            ],
          ),
          body: body,
        );
      },
    );
  }
}

class _FindTeam extends StatefulWidget {
  const _FindTeam({required this.viewModel});

  final UsauRosterViewModel viewModel;

  @override
  State<_FindTeam> createState() => _FindTeamState();
}

class _FindTeamState extends State<_FindTeam> {
  late final _search = TextEditingController(text: widget.viewModel.query);
  final _link = TextEditingController();
  String? _linkError;

  @override
  void dispose() {
    _search.dispose();
    _link.dispose();
    super.dispose();
  }

  void _useLink() {
    final url = UsauRosterViewModel.parseLink(_link.text);
    setState(
      () => _linkError = url == null
          ? 'Paste a play.usaultimate.org team page link'
          : null,
    );
    if (url != null) {
      widget.viewModel.link.execute((url: url, name: ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final theme = Theme.of(context);
    final results = vm.candidates;
    return ConstrainedContent(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Find your team', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Pick your team from the USA Ultimate rankings to import its '
            'roster and track who has accepted a spot.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Team name',
            ),
            onChanged: vm.setQuery,
          ),
          if (vm.searching)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          if (vm.searchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                errorMessage(vm.searchError),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          for (final c in results)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.groups_outlined),
              title: Text(c.entry.teamName),
              subtitle: Text(
                [
                  c.division,
                  '#${c.entry.rank}',
                  if (c.entry.region.isNotEmpty) c.entry.region,
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: vm.link.running
                  ? null
                  : () => vm.link.execute((
                      url: c.entry.teamUrl,
                      name: c.entry.teamName,
                    )),
            ),
          if (results.isEmpty && vm.query.isNotEmpty && !vm.searching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No ranked teams match. Paste your team link below.'),
            ),
          const SizedBox(height: 24),
          Text(
            'Or paste your team page link',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _link,
            decoration: InputDecoration(
              hintText:
                  'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=…',
              errorText: _linkError,
            ),
            onSubmitted: (_) => _useLink(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: vm.link.running ? null : _useLink,
              child: const Text('Use link'),
            ),
          ),
          const SizedBox(height: 16),
          const UsauAttribution(),
        ],
      ),
    );
  }
}

class _SyncPreview extends StatelessWidget {
  const _SyncPreview({required this.viewModel});

  final UsauRosterViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final team = vm.team!;
    if (vm.load.running && vm.usauTeam == null) return const LoadingView();
    if (vm.loadError != null) {
      return ErrorView(error: vm.loadError, onRetry: vm.load.execute);
    }
    final plan = vm.plan;
    if (plan == null) return const LoadingView();
    final updated = plan.updated.toList();
    return Column(
      children: [
        Expanded(
          child: ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card.outlined(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.verified_outlined),
                    title: Text(vm.usauTeam?.name ?? team.usauName ?? ''),
                    subtitle: Text(
                      '${vm.usauTeam?.roster.length ?? 0} players on the '
                      'USA Ultimate roster',
                    ),
                    trailing: IconButton(
                      tooltip: 'Reload',
                      icon: const Icon(Icons.refresh),
                      onPressed: vm.load.running ? null : vm.load.execute,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Players are matched by name. Nobody is removed; anyone '
                  'missing from USA Ultimate is marked not on the roster.',
                  style: theme.textTheme.bodySmall,
                ),
                _Section(
                  title: 'New players (${plan.added.length})',
                  subtitle: 'Untick anyone you don’t want added.',
                  children: [
                    for (final p in plan.added)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: !vm.isSkipped(p),
                        onChanged: (_) => vm.toggleSkip(p),
                        title: Text(p.name),
                        subtitle: Text(_describe(p)),
                      ),
                  ],
                ),
                _Section(
                  title: 'Updated from USA Ultimate (${updated.length})',
                  children: [
                    for (final m in updated)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(m.after.name),
                        subtitle: Text(
                          '${_describe(m.before)}  →  ${_describe(m.after)}',
                        ),
                      ),
                  ],
                ),
                _Section(
                  title: 'Not on USA Ultimate roster (${plan.missing.length})',
                  subtitle:
                      'They haven’t accepted a spot yet, or their name is '
                      'spelled differently. Fix the name to match.',
                  children: [
                    for (final p in plan.missing)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(p.name),
                      ),
                  ],
                ),
                _Section(
                  title: 'On both rosters (${plan.matched.length})',
                  initiallyExpanded: false,
                  children: [
                    for (final m in plan.matched)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(m.after.name),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const UsauAttribution(),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: vm.apply.running ? null : vm.apply.execute,
                icon: const Icon(Icons.sync),
                label: Text(
                  vm.pendingWrites == 0
                      ? 'Mark as synced'
                      : 'Apply ${vm.pendingWrites} change'
                            '${vm.pendingWrites == 1 ? '' : 's'}',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _describe(RosterPlayer p) =>
      ['#${p.number ?? '–'}', p.position.label].join(' · ');
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    this.subtitle,
    required this.children,
    this.initiallyExpanded = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: initiallyExpanded,
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: subtitle == null ? null : Text(subtitle!),
      children: children,
    );
  }
}
