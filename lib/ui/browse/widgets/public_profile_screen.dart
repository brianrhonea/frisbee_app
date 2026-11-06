import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/player_profile.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../web/widgets/join_prompt.dart';
import '../view_models/public_profile_viewmodel.dart';
import 'browse_widgets.dart';

/// A player's profile for signed-out visitors: who they are, their teams
/// and newest posts. Following asks them to join. A private profile shows
/// only its name and photo.
class PublicProfileScreen extends StatelessWidget {
  const PublicProfileScreen({super.key, required this.viewModel});

  final PublicProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final p = vm.profile;
        return BrowsePage(
          eyebrow: 'Player',
          title: p?.name ?? 'Player profile',
          load: vm.load,
          loaded: p != null,
          children: [
            if (p != null) ...[
              _Header(profile: p),
              const SizedBox(height: 16),
              if (p.isPrivate)
                const _PrivateNotice()
              else ...[
                if (p.details.visibility.teams &&
                    p.summary.teams.isNotEmpty) ...[
                  SectionCard(
                    title: 'Teams',
                    child: Column(
                      children: [
                        for (final t in p.summary.teams)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const TeamBadge(size: 34),
                            title: Text(t.name),
                            subtitle: t.subtitle.isEmpty
                                ? null
                                : Text(t.subtitle),
                            onTap: t.id.isEmpty
                                ? null
                                : () => context.go(Routes.team(t.id)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                PublicPostList(
                  posts: vm.posts,
                  loadImage: vm.loadImage,
                  loadMore: vm.loadMore,
                  hasMore: vm.hasMore,
                  empty: '${p.name} hasn\'t posted yet.',
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});

  final PlayerProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final d = p.details;
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final facts = [
      if (d.pronouns.isNotEmpty) d.pronouns,
      if (d.hometown.isNotEmpty) d.hometown,
      if (d.school.isNotEmpty) d.school,
      if (d.playingSince != null) 'Playing since ${d.playingSince}',
    ];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonAvatar(name: p.name, photoUrl: p.photoUrl, radius: 36),
              const Spacer(),
              FilledButton(
                onPressed: () => showJoinPrompt(context, LockedAction.follow),
                child: Text(p.isPrivate ? 'Request to follow' : 'Follow'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(
                  p.name,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (p.isPrivate) ...[
                const SizedBox(width: 8),
                const Icon(Icons.lock_outline, size: 20),
              ],
            ],
          ),
          if (p.username != null)
            Text('@${p.username}', style: TextStyle(color: c.muted)),
          if (!p.isPrivate && d.bio.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(d.bio, style: text.bodyLarge),
          ],
          if (!p.isPrivate && facts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(facts.join(' · '), style: TextStyle(color: c.muted)),
          ],
        ],
      ),
    );
  }
}

class _PrivateNotice extends StatelessWidget {
  const _PrivateNotice();

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      children: [
        const Icon(Icons.lock_outline, size: 36),
        const SizedBox(height: 10),
        const Text(
          'This profile is private',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Log in and ask to follow to see their posts, teams and stats.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.of(context).muted),
        ),
      ],
    ),
  );
}
