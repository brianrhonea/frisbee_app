import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../view_models/event_guide.dart';
import 'hosted_status_badge.dart';
import 'hosted_tournament_screen.dart' show hostedDates;

/// The top of an event page: what it is, when and where, who runs it, and
/// its key numbers.
class EventHeader extends StatelessWidget {
  const EventHeader({super.key, required this.tournament});

  final HostedTournament tournament;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final c = AppColors.of(context);
    final fee = t.entryFee;
    final season = t.season;
    Widget fact(IconData icon, String text, {VoidCallback? onTap}) {
      final row = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: c.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: TextStyle(color: c.ink, fontSize: 14)),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 18, color: c.muted),
          ],
        ),
      );
      return onTap == null
          ? row
          : InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              child: row,
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            HostedStatusBadge(status: t.status),
            if (t.hostOfficial) const OfficialBadge(),
            Tag(t.type.label),
            if (t.mixedEntry) const Tag('Teams can reserve a spot'),
            if (t.takesPlayers)
              Tag(
                t.draftMode == DraftMode.captains
                    ? "Players sign up · captains' draft"
                    : 'Players sign up · balanced teams',
              ),
            if (t.visibility == TournamentVisibility.inviteOnly)
              const Tag('Invite only'),
          ],
        ),
        const SizedBox(height: 10),
        fact(Icons.event_outlined, hostedDates(t)),
        if (t.location.isNotEmpty) fact(Icons.place_outlined, t.location),
        fact(
          Icons.groups_outlined,
          'Hosted by ${t.hostName}',
          onTap: () => context.push(Routes.teamOver(t.hostId)),
        ),
        if (season != null)
          fact(
            Icons.calendar_month_outlined,
            '${season.weeks} weeks'
            '${season.gamesPerNight > 1 ? ' · ${season.gamesPerNight} games a night' : ''}'
            '${season.hasPlayoffs ? ' · top ${season.playoffTeams} make the playoffs' : ''}',
          ),
        if (fee != null)
          fact(
            Icons.payments_outlined,
            '${fee.label} per ${t.takesPlayers ? 'player' : 'team'}'
            '${fee.instructions.isEmpty ? '' : ' · ${fee.instructions}'}',
          ),
        if (t.mixedEntry)
          if (t.teamFee case final f?)
            fact(Icons.groups_2_outlined, '${f.label} per team spot'),
        if (t.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(t.description, style: TextStyle(color: c.ink, fontSize: 14)),
        ],
      ],
    );
  }
}

/// Where things stand for this user and the one thing to do next.
class GuideCard extends StatelessWidget {
  const GuideCard({super.key, required this.guide, required this.onAction});

  final EventGuide guide;
  final void Function(GuideButton) onAction;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = guide;
    final button = g.button;
    final secondary = g.secondary;
    // The highlighted card is dark, so its text is light.
    final ink = g.needsYou ? c.onFeature : c.ink;
    final muted = g.needsYou ? c.onFeatureMuted : c.muted;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Eyebrow(g.eyebrow, color: muted),
        const SizedBox(height: 6),
        Text(
          g.title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(g.body, style: TextStyle(color: muted, fontSize: 14)),
        if (button != null) ...[
          const SizedBox(height: 14),
          HighlightButton(
            label: button.label,
            icon: _icon(button.action),
            onPressed: () => onAction(button),
          ),
        ],
        if (secondary != null) ...[
          const SizedBox(height: 6),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ink),
            onPressed: () => onAction(secondary),
            child: Text(secondary.label),
          ),
        ],
      ],
    );
    return g.needsYou ? FeatureCard(child: body) : SectionCard(child: body);
  }
}

/// The host's way from setup to final, one step at a time; the current
/// step has its button.
class HostChecklist extends StatelessWidget {
  const HostChecklist({super.key, required this.steps, required this.onAction});

  final List<GuideStep> steps;
  final void Function(GuideButton) onAction;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SectionCard(
      title: 'Setup',
      child: Column(
        children: [
          for (final (i, s) in steps.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (s.state) {
                      GuideStepState.done => Icons.check_circle,
                      GuideStepState.current => Icons.radio_button_checked,
                      GuideStepState.todo => Icons.radio_button_unchecked,
                    },
                    size: 20,
                    color: s.state == GuideStepState.todo ? c.muted : c.ink,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          style: TextStyle(
                            fontWeight: s.state == GuideStepState.current
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: s.state == GuideStepState.todo
                                ? c.muted
                                : c.ink,
                          ),
                        ),
                        Text(
                          s.detail,
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                        if (s.state != GuideStepState.current &&
                            s.secondary != null)
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => onAction(s.secondary!),
                            child: Text(s.secondary!.label),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

IconData _icon(GuideAction a) => switch (a) {
  GuideAction.addDivision => Icons.add,
  GuideAction.openRegistration => Icons.campaign_outlined,
  GuideAction.closeRegistration => Icons.lock_outline,
  GuideAction.reviewPlayers ||
  GuideAction.reviewTeams => Icons.fact_check_outlined,
  GuideAction.draftTeams ||
  GuideAction.captainsDraft ||
  GuideAction.watchDraft => Icons.how_to_reg_outlined,
  GuideAction.createTeams => Icons.group_add_outlined,
  GuideAction.publishSchedule ||
  GuideAction.schedule => Icons.calendar_month_outlined,
  GuideAction.reserveTeam => Icons.group_add_outlined,
  GuideAction.signUp ||
  GuideAction.apply ||
  GuideAction.acceptInvite => Icons.how_to_reg_outlined,
  GuideAction.results => Icons.emoji_events_outlined,
};
