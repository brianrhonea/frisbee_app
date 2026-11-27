import 'package:flutter/material.dart';

import '../../../domain/models/team.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';
import '../view_models/home_viewmodel.dart';

/// The user's teams and groups in a row under the composer, with New /
/// Join at the end (the website's team strip).
class TeamStrip extends StatelessWidget {
  const TeamStrip({
    super.key,
    required this.teams,
    required this.onOpen,
    required this.onNewOrJoin,
  });

  /// In the order shown.
  final List<Team> teams;
  final ValueChanged<Team> onOpen;
  final VoidCallback onNewOrJoin;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget tile({
      required Widget badge,
      required String label,
      required VoidCallback onTap,
      bool dashed = false,
    }) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: dashed ? Colors.transparent : c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: c.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(cardRadius),
          onTap: onTap,
          child: SizedBox(
            width: 84,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
              child: Column(
                children: [
                  badge,
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // Grows with the text scale, so the label never overflows.
    final grow = (MediaQuery.textScalerOf(context).scale(12) - 12) * 1.3;
    return SizedBox(
      height: 92 + grow,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final t in teams)
            tile(
              badge: TeamBadge(size: 40, community: t.isCommunity),
              label: t.name,
              onTap: () => onOpen(t),
            ),
          tile(
            badge: CircleAvatar(
              radius: 20,
              backgroundColor: c.accentSoft,
              child: Icon(Icons.add, color: c.accent),
            ),
            label: teams.isEmpty ? 'Join a team' : 'New / Join',
            onTap: onNewOrJoin,
            dashed: true,
          ),
        ],
      ),
    );
  }
}

/// "Get started": the new-member checklist on an empty For you feed.
class GetStartedCard extends StatelessWidget {
  const GetStartedCard({super.key, required this.steps, required this.onStep});

  final List<(OnboardingStep, bool)> steps;
  final ValueChanged<OnboardingStep> onStep;

  static String _action(OnboardingStep s) => switch (s) {
    OnboardingStep.username => 'Pick one',
    OnboardingStep.join => 'Join or create',
    OnboardingStep.find => 'Find',
    OnboardingStep.follow => 'Find people',
  };

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final done = steps.where((s) => s.$2).length;
    return SectionCard(
      title: 'Get started',
      action: Text(
        '$done of ${steps.length} done',
        style: TextStyle(fontSize: 12, color: c.muted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your feed fills up with news from your teams and the people '
            'you follow.',
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
          const SizedBox(height: 6),
          for (final (step, isDone) in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 22,
                    color: isDone ? c.positive : c.muted,
                    semanticLabel: isDone ? 'Done' : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isDone ? FontWeight.w500 : FontWeight.w600,
                        color: isDone ? c.muted : c.ink,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (!isDone)
                    TextButton(
                      onPressed: () => onStep(step),
                      child: Text(_action(step)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Needs you": people asking to join groups the user approves members
/// for (the website's card of the same name). Amber, since each is the
/// user's to do: a header on the page, then a small card per group (side
/// by side, scrolling, when there are several).
class NeedsYouCard extends StatelessWidget {
  const NeedsYouCard({super.key, required this.items, required this.onOpen});

  final List<PendingRequests> items;
  final ValueChanged<Team> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget card(PendingRequests r) => Material(
      color: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(color: c.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(cardRadius),
        onTap: () => onOpen(r.team),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TeamDot(color: c.highlight),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Eyebrow(
                            'Join requests',
                            color: c.highlightInk,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      r.team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      r.count == 1
                          ? '1 person is asking to join'
                          : '${r.count} people are asking to join',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.muted),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Needs you',
          leading: TeamDot(color: c.highlight, size: 9),
        ),
        if (items.length == 1)
          card(items.single)
        else
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) =>
                  SizedBox(width: 240, child: card(items[i])),
            ),
          ),
      ],
    );
  }
}
