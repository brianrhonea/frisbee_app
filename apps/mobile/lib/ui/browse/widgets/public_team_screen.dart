import 'package:flutter/material.dart';

import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../schedule/widgets/event_style.dart';
import '../../teams/widgets/team_post_widgets.dart';
import '../../web/widgets/join_prompt.dart';
import '../view_models/public_team_viewmodel.dart';
import 'browse_search_screen.dart' show teamSubtitle;
import 'browse_widgets.dart';

/// A team or group's page for signed-out visitors: what it is, its
/// upcoming public events and public posts. Joining and following ask them
/// to sign up. A private group shows only what it is.
class PublicTeamScreen extends StatelessWidget {
  const PublicTeamScreen({super.key, required this.viewModel});

  final PublicTeamViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final page = vm.page;
        final team = page?.listing;
        final private =
            team != null && team.kind != TeamKind.team && team.requiresApproval;
        return BrowsePage(
          eyebrow: team?.kind.label ?? 'Team',
          title: team?.name ?? 'Team',
          load: vm.load,
          loaded: page != null,
          children: [
            if (page != null && team != null) ...[
              _Header(team: team, private: private),
              const SizedBox(height: 16),
              if (private)
                const EmptyView(
                  icon: Icons.lock_outline,
                  title: 'This group is private',
                  message: 'Ask to join to see its posts and events.',
                )
              else ...[
                SectionCard(
                  title: 'Coming up',
                  child: page.events.isEmpty
                      ? Text(
                          'No public events scheduled.',
                          style: TextStyle(color: AppColors.of(context).muted),
                        )
                      : Column(
                          children: [for (final e in page.events) _EventRow(e)],
                        ),
                ),
                const SizedBox(height: 16),
                if (page.posts.isEmpty)
                  const EmptyView(
                    icon: Icons.campaign_outlined,
                    title: 'No public posts yet',
                  )
                else
                  for (final p in page.posts) ...[
                    TeamPostCard(post: p, loadImage: vm.loadImage),
                    const SizedBox(height: 12),
                  ],
              ],
            ],
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.team, required this.private});

  final TeamListing team;
  final bool private;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final group = team.kind != TeamKind.team;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TeamBadge(size: 64, community: group),
              const Spacer(),
              OutlinedButton(
                onPressed: () => showJoinPrompt(context, LockedAction.follow),
                child: const Text('Follow'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => showJoinPrompt(context, LockedAction.join),
                child: Text(private ? 'Ask to join' : 'Join'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            team.name,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(teamSubtitle(team), style: TextStyle(color: c.muted)),
          if (team.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(team.description, style: text.bodyLarge),
          ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.e);

  final TeamEvent e;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: DateBadge(date: e.startsAt),
      title: Row(
        children: [
          Icon(e.type.icon, size: 16, color: e.type.color(scheme)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              e.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      subtitle: Text(
        [
          eventWhen(e.startsAt),
          if (e.location.isNotEmpty) e.location,
        ].join(' · '),
      ),
    );
  }
}
