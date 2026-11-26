import 'package:flutter/material.dart';

import '../themes/theme.dart';
import 'status_pill.dart';

/// Shared pieces of the "Turf & Disc" design: scores, live marks, team
/// dots, "needs you" pills and section headers. Colours follow the rules in
/// docs/redesign-plan.md: red only for live games, amber only for what is
/// the user's to do, navy for anything live or today.

/// A score or big number in the condensed sports face.
class ScoreText extends StatelessWidget {
  const ScoreText(this.text, {super.key, this.size = 22, this.color});

  final String text;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontFamily: scoreFont,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 1.05,
      color: color ?? AppColors.of(context).ink,
    ),
  );
}

/// The small red dot of a live game.
class LiveDot extends StatelessWidget {
  const LiveDot({super.key, this.size = 8});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColors.of(context).live,
      shape: BoxShape.circle,
    ),
  );
}

/// "Live" in a soft red pill with its dot: a [StatusPill].
class LivePill extends StatelessWidget {
  const LivePill({super.key, this.label = 'Live'});

  final String label;

  @override
  Widget build(BuildContext context) =>
      StatusPill(label, tone: PillTone.live, dot: true);
}

/// A "needs you" pill in soft amber, e.g. "Needs RSVP" or "Score due": a
/// [StatusPill].
class NeedsYouPill extends StatelessWidget {
  const NeedsYouPill(this.label, {super.key, this.strong = false});

  final String label;

  /// Solid, for the single most urgent thing on a screen.
  final bool strong;

  @override
  Widget build(BuildContext context) => strong
      ? StatusPill(label, tone: PillTone.accent, solid: true)
      : StatusPill(label, tone: PillTone.warning);
}

/// A small coloured dot that marks a team event, a personal event, or a
/// team's own colour, before a meta line.
class TeamDot extends StatelessWidget {
  const TeamDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A section title on the page background (not inside a card): 16/800
/// title on the left and an optional turf link (e.g. "See all") on the
/// right.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.leading,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// E.g. a [LiveDot] before "Live now".
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: c.ink,
                ),
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: c.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(44, 36),
                textStyle: const TextStyle(
                  fontFamily: appFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// One team's line on a scoreboard: name on the left, score on the right.
/// Used inside a navy [ScoreboardCard] (or on light cards with
/// [onBoard] false).
class ScoreLine extends StatelessWidget {
  const ScoreLine({
    super.key,
    required this.team,
    this.score,
    this.leading = false,
    this.onBoard = true,
    this.scoreSize = 22,
  });

  final String team;

  /// Null shows a dash (not yet scored).
  final int? score;

  /// The winning or the user's team: bold and full-strength.
  final bool leading;
  final bool onBoard;
  final double scoreSize;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final strong = onBoard ? c.onFeature : c.ink;
    final soft = onBoard ? c.onFeatureMuted : c.ink2;
    return Row(
      children: [
        Expanded(
          child: Text(
            team,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: leading ? FontWeight.w800 : FontWeight.w600,
              color: leading ? strong : soft,
            ),
          ),
        ),
        const SizedBox(width: 12),
        ScoreText(
          score == null ? '–' : '$score',
          size: scoreSize,
          color: leading ? strong : soft,
        ),
      ],
    );
  }
}

/// The small amber label line on a navy scoreboard, e.g. a live dot and
/// "Round 3 · Field 3". Not uppercased by design; pass the text as wanted.
class BoardLabel extends StatelessWidget {
  const BoardLabel(this.text, {super.key, this.live = false});

  final String text;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      children: [
        if (live) ...[const LiveDot(), const SizedBox(width: 8)],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: c.onFeatureMuted,
            ),
          ),
        ),
      ],
    );
  }
}
