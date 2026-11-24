import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../view_models/event_guide.dart';
import 'hosted_tournament_screen.dart' show hostedDates;
import 'tournament_parts.dart';

/// The facts of an event page: what it is, when and where, who runs it,
/// its fees and its About. (Its status and name are in the page header.)
class EventHeader extends StatelessWidget {
  const EventHeader({super.key, required this.tournament});

  final HostedTournament tournament;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final c = AppColors.of(context);
    final fee = t.entryFee;
    final season = t.season;
    Widget fact(
      IconData icon,
      String text, {
      String? detail,
      VoidCallback? onTap,
    }) {
      final row = Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (detail != null && detail.isNotEmpty)
                    Text(
                      detail,
                      style: TextStyle(color: c.muted, fontSize: 12.5),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 20, color: c.muted),
          ],
        ),
      );
      return onTap == null ? row : InkWell(onTap: onTap, child: row);
    }

    final dueAt = fee?.dueAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
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
        RowsCard(
          children: [
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
                '${fee.label} per ${t.takesPlayers ? 'player' : 'team'}',
                detail: [
                  if (fee.instructions.isNotEmpty) fee.instructions,
                  if (dueAt != null)
                    'due ${MaterialLocalizations.of(context).formatShortMonthDay(dueAt)}',
                ].join(' · '),
              ),
            if (t.mixedEntry)
              if (t.teamFee case final f?)
                fact(Icons.groups_2_outlined, '${f.label} per team spot'),
          ],
        ),
        if (t.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            padding: const EdgeInsets.all(14),
            child: Text(
              t.description,
              style: TextStyle(color: c.ink, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }
}

/// Where things stand for this user and the one thing to do next: an
/// amber-edged card with an amber button when it's theirs to do.
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
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: g.needsYou
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: c.highlightSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Eyebrow(g.eyebrow, color: c.highlightInk),
                  )
                : Eyebrow(g.eyebrow),
          ),
          const SizedBox(height: 6),
          Text(
            g.title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(g.body, style: TextStyle(color: c.ink2, fontSize: 14)),
          if (button != null) ...[
            const SizedBox(height: 12),
            if (g.needsYou)
              HighlightButton(
                label: button.label,
                icon: _icon(button.action),
                onPressed: () => onAction(button),
              )
            else
              FilledButton.icon(
                onPressed: () => onAction(button),
                icon: Icon(_icon(button.action), size: 18),
                label: Text(button.label),
              ),
          ],
          if (secondary != null) ...[
            const SizedBox(height: 2),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: c.accent,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => onAction(secondary),
              child: Text(secondary.label),
            ),
          ],
        ],
      ),
    );
    if (!g.needsYou) return Card(child: body);
    return Card(
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(color: c.highlight, width: 2),
      ),
      child: body,
    );
  }
}

/// The host's way from setup to final, one step at a time: done steps
/// ticked, the current one (the host's to do) in amber with its number.
class HostChecklist extends StatelessWidget {
  const HostChecklist({super.key, required this.steps, required this.onAction});

  final List<GuideStep> steps;
  final void Function(GuideButton) onAction;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final done = steps.where((s) => s.state == GuideStepState.done).length;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Next steps',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                    ),
                  ),
                ),
                Text(
                  '$done of ${steps.length} done',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: [
                    if (done > 0)
                      Expanded(
                        flex: done,
                        child: ColoredBox(color: c.accent),
                      ),
                    if (steps.length > done)
                      Expanded(
                        flex: steps.length - done,
                        child: ColoredBox(color: c.field),
                      ),
                  ],
                ),
              ),
            ),
          ),
          for (final (i, s) in steps.indexed) _step(c, i, s),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _step(AppColors c, int i, GuideStep s) {
    final current = s.state == GuideStepState.current;
    final todo = s.state == GuideStepState.todo;
    final mark = Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (s.state) {
          GuideStepState.done => c.accentSoft,
          GuideStepState.current => c.highlight,
          GuideStepState.todo => null,
        },
        border: todo ? Border.all(color: c.border2, width: 1.5) : null,
      ),
      child: s.state == GuideStepState.done
          ? Icon(Icons.check, size: 16, color: c.accentInk)
          : Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: current ? c.onHighlight : c.muted,
              ),
            ),
    );
    return Container(
      color: current ? c.highlightSoft : null,
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          mark,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                    color: s.state == GuideStepState.done || todo
                        ? c.ink2
                        : c.ink,
                  ),
                ),
                Text(
                  s.detail,
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
                if (!current && s.secondary != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: c.accent,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => onAction(s.secondary!),
                    child: Text(s.secondary!.label),
                  ),
              ],
            ),
          ),
          if (current) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'NEEDS YOU',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: c.highlightInk,
                ),
              ),
            ),
          ],
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
  GuideAction.confirmSeeds => Icons.format_list_numbered,
  GuideAction.publishSchedule ||
  GuideAction.publishAll ||
  GuideAction.schedule => Icons.calendar_month_outlined,
  GuideAction.reserveTeam => Icons.group_add_outlined,
  GuideAction.signUp ||
  GuideAction.apply ||
  GuideAction.acceptInvite => Icons.how_to_reg_outlined,
  GuideAction.results => Icons.emoji_events_outlined,
};
