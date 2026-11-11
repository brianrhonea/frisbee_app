import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../view_models/host_event_viewmodel.dart';

/// Pick what to host (a league, tournament or hat tournament) and who hosts
/// it: an official organizer like Stall 10, a school or club, a community
/// group or a team the user runs. Someone who runs none yet is shown how
/// to start one.
class HostEventScreen extends StatelessWidget {
  const HostEventScreen({super.key, required this.viewModel});

  final HostEventViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Host an event')),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          if (!viewModel.loaded) return const LoadingView();
          if (viewModel.error != null) return ErrorView(error: viewModel.error);
          final sections = viewModel.sections;
          return ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _WhoCanHost(),
                const SizedBox(height: 16),
                SectionCard(
                  title: '1. What are you hosting?',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<HostedType>(
                        segments: [
                          for (final t in [
                            HostedType.league,
                            HostedType.tournament,
                            HostedType.hat,
                          ])
                            ButtonSegment(value: t, label: Text(t.label)),
                        ],
                        selected: {viewModel.type},
                        onSelectionChanged: (s) => viewModel.setType(s.first),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _typeBlurb(viewModel.type),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.of(context).muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (sections.isEmpty)
                  const _NoHost()
                else
                  SectionCard(
                    title: '2. Who is hosting it?',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, s) in sections.indexed) ...[
                          if (i > 0) const SizedBox(height: 16),
                          _HostSectionView(
                            section: s,
                            onPick: (t) => context.push(
                              Routes.newTournament(
                                t.id,
                                type: viewModel.type.name,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (sections.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const _StartHost(title: 'Or start a new host'),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  static String _typeBlurb(HostedType t) => switch (t) {
    HostedType.league =>
      'A weekly season with standings and optional playoffs. Teams enter, '
          'or players sign up and you draft teams.',
    HostedType.tournament =>
      'A one or two day event. Teams apply, you seed them and publish '
          'pools and brackets.',
    HostedType.hat =>
      'Players sign up on their own and you draft balanced teams for '
          'the day.',
  };
}

/// The rules, up front: who may host, and what an official host is.
class _WhoCanHost extends StatelessWidget {
  const _WhoCanHost();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: c.ink, fontSize: 13.5)),
          ),
        ],
      ),
    );
    return SectionCard(
      title: 'Who can host',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "You can host if you're the owner, or have the Manage events "
            'permission, on one of these:',
            style: TextStyle(color: c.muted, fontSize: 13.5),
          ),
          line(
            Icons.verified_outlined,
            'An official organizer, like Stall 10. Its events get a '
            'verified badge.',
          ),
          line(Icons.apartment_outlined, 'A school or club'),
          line(Icons.diversity_3_outlined, 'A community group'),
          line(Icons.groups_outlined, 'A team'),
        ],
      ),
    );
  }
}

class _HostSectionView extends StatelessWidget {
  const _HostSectionView({required this.section, required this.onPick});

  final HostSection section;
  final void Function(Team) onPick;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final official = section.kind == HostSectionKind.official;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(child: Eyebrow(section.kind.title)),
            if (official) ...[
              const SizedBox(width: 6),
              const OfficialBadge(label: null),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          section.kind.blurb,
          style: TextStyle(fontSize: 12.5, color: c.muted),
        ),
        const SizedBox(height: 6),
        for (final t in section.teams)
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(switch (t.kind) {
                  TeamKind.organization => Icons.apartment_outlined,
                  TeamKind.community => Icons.diversity_3_outlined,
                  TeamKind.team => Icons.groups_outlined,
                }),
              ),
              title: Row(
                children: [
                  Flexible(child: Text(t.name)),
                  if (t.official) ...[
                    const SizedBox(width: 6),
                    const OfficialBadge(label: null),
                  ],
                ],
              ),
              subtitle: Text(t.kind.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onPick(t),
            ),
          ),
      ],
    );
  }
}

/// The user runs nothing they can host from yet.
class _NoHost extends StatelessWidget {
  const _NoHost();

  @override
  Widget build(BuildContext context) => const _StartHost(
    title: '2. Who is hosting it?',
    intro:
        "You don't run a team, school or club, or group yet. Start one to "
        "host from, for example your league's name. Joining one isn't "
        'enough: its owner can give you the Manage events permission.',
  );
}

class _StartHost extends StatelessWidget {
  const _StartHost({required this.title, this.intro});

  final String title;
  final String? intro;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (intro case final text?) ...[
            Text(text, style: TextStyle(color: c.ink, fontSize: 13.5)),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: () => context.go(Routes.createCommunity),
            icon: const Icon(Icons.apartment_outlined),
            label: const Text('Start a school or club'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go(Routes.createGroup),
            icon: const Icon(Icons.diversity_3_outlined),
            label: const Text('Start a community group'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go(Routes.createTeam),
            icon: const Icon(Icons.groups_outlined),
            label: const Text('Start a team'),
          ),
        ],
      ),
    );
  }
}
