import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';
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
                const SectionHeader('What are you hosting?'),
                _TypePicker(
                  selected: viewModel.type,
                  onSelect: viewModel.setType,
                ),
                const SizedBox(height: 20),
                if (sections.isEmpty)
                  const _NoHost()
                else ...[
                  const SectionHeader('Host as'),
                  Text(
                    "Pick who runs it: you can host where you're the owner "
                    'or can manage events.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.of(context).muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final (i, s) in sections.indexed) ...[
                    if (i > 0) const SizedBox(height: 14),
                    _HostSectionView(
                      section: s,
                      onPick: (t) => context.push(
                        Routes.newTournament(t.id, type: viewModel.type.name),
                      ),
                    ),
                  ],
                ],
                if (sections.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const _StartHost(title: 'Or start a new host'),
                ],
                const SizedBox(height: 16),
                const _WhoCanHost(),
              ],
            ),
          );
        },
      ),
    );
  }

  /// What each kind of event is, under its name.
  static String typeBlurb(HostedType t) => switch (t) {
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

/// The kinds of event, as cards to pick from: icon, name and what it is.
class _TypePicker extends StatelessWidget {
  const _TypePicker({required this.selected, required this.onSelect});

  final HostedType selected;
  final ValueChanged<HostedType> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget card(HostedType t) {
      final on = t == selected;
      return Semantics(
        selected: on,
        button: true,
        child: Material(
          color: on ? c.accentSoft : c.card,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(cardRadius),
            side: BorderSide(
              color: on ? c.accent : c.border,
              width: on ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelect(t),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: on ? c.card : c.field,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          switch (t) {
                            HostedType.tournament =>
                              Icons.emoji_events_outlined,
                            HostedType.league => Icons.calendar_month_outlined,
                            HostedType.hat => Icons.shuffle,
                          },
                          size: 22,
                          color: on ? c.accentInk : c.ink2,
                        ),
                      ),
                      const Spacer(),
                      if (on)
                        Icon(Icons.check_circle, size: 22, color: c.accent),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.label,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: on ? c.accentInk : c.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    HostEventScreen.typeBlurb(t),
                    style: TextStyle(fontSize: 12.5, color: c.ink2),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    const types = [HostedType.tournament, HostedType.league, HostedType.hat];
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= 560 ? 3 : 2;
        final width = (box.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in types) SizedBox(width: width, child: card(t)),
          ],
        );
      },
    );
  }
}

/// The rules: who may host, and what an official host is.
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
          line(Icons.diversity_3_outlined, 'A pickup community'),
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
        const SizedBox(height: 8),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, t) in section.teams.indexed) ...[
                if (i > 0) const Divider(height: 1),
                InkWell(
                  onTap: () => onPick(t),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: switch (t.kind) {
                              TeamKind.organization => c.feature,
                              TeamKind.community => c.accentSoft,
                              TeamKind.team => c.team,
                            },
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            initialsOf(t.name),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: switch (t.kind) {
                                TeamKind.organization => c.onFeature,
                                TeamKind.community => c.accentInk,
                                TeamKind.team => c.card,
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      t.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: c.ink,
                                      ),
                                    ),
                                  ),
                                  if (t.official) ...[
                                    const SizedBox(width: 6),
                                    const OfficialBadge(label: null),
                                  ],
                                ],
                              ),
                              Text(
                                t.kind.label,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: c.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: c.muted),
                      ],
                    ),
                  ),
                ),
              ],
            ],
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
    title: 'Host as',
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
            label: const Text('Start a pickup community'),
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
