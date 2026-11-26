import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/tournament_engine/standings.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';

/// Shared pieces of the tournament and league pages in the "Turf & Disc"
/// design: date badges, team marks, game rows, standings, stat tiles and
/// small status pills.

/// An event's month over its day(s), e.g. "APR / 18–19", in turf.
class EventDateBadge extends StatelessWidget {
  const EventDateBadge({
    super.key,
    required this.startsOn,
    this.endsOn,
    this.size = 56,
  });

  final DateTime startsOn;
  final DateTime? endsOn;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final end = endsOn;
    final days =
        end == null ||
            DateUtils.isSameDay(end, startsOn) ||
            end.month != startsOn.month
        ? '${startsOn.day}'
        : '${startsOn.day}–${end.day}';
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: FittedBox(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateFormat.MMM().format(startsOn).toUpperCase(),
              style: TextStyle(
                fontFamily: scoreFont,
                fontSize: 13,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: c.accentInk,
              ),
            ),
            Text(
              days,
              style: TextStyle(
                fontFamily: scoreFont,
                fontSize: 24,
                height: 1.0,
                fontWeight: FontWeight.w800,
                color: c.accentInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A team's initials in a rounded square: team blue for the user's own
/// team, neutral otherwise.
class TeamMark extends StatelessWidget {
  const TeamMark({
    super.key,
    required this.name,
    this.mine = false,
    this.size = 30,
  });

  final String name;
  final bool mine;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: mine ? c.team : c.field,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w800,
          color: mine ? c.card : c.ink2,
        ),
      ),
    );
  }
}

/// How a [Pill] is coloured.
enum PillTone {
  /// Grey: a plain fact, e.g. "Draft" or "Final".
  neutral,

  /// Turf: something good or settled, e.g. "Accepted" or "Bid paid".
  turf,

  /// Amber: the user's to do, e.g. "Bid fee due".
  needsYou,
}

/// A small rounded status, e.g. "Accepted · seed 4".
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.tone = PillTone.neutral});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (bg, fg) = switch (tone) {
      PillTone.neutral => (c.field, c.ink2),
      PillTone.turf => (c.positiveSoft, c.positive),
      PillTone.needsYou => (c.highlightSoft, c.highlightInk),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// A white card holding rows split by hairlines.
class RowsCard extends StatelessWidget {
  const RowsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const Divider(height: 1),
          child,
        ],
      ],
    ),
  );
}

/// A number over a caption on a tinted tile, e.g. "12/16 Accepted".
/// [highlight] marks the user's to do (amber), e.g. applications to decide.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.of,
    this.highlight = false,
  });

  final String value;
  final String label;

  /// Shown small after [value], e.g. "/16".
  final String? of;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ink = highlight ? c.highlightInk : c.ink;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: highlight ? c.highlightSoft : c.card,
        borderRadius: BorderRadius.circular(controlRadius),
        border: Border.all(color: highlight ? c.highlightSoft : c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: value),
                if (of != null)
                  TextSpan(
                    text: of,
                    style: TextStyle(
                      fontSize: 15,
                      color: highlight ? c.highlightInk : c.muted,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            style: TextStyle(
              fontFamily: scoreFont,
              fontWeight: FontWeight.w800,
              fontSize: 24,
              height: 1.05,
              color: ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              color: highlight ? c.highlightInk : c.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// One game as a row of a [RowsCard]: when and where on the left, the two
/// teams in the middle (the winner bold), and the scores, or [action],
/// on the right.
class HostedGameRow extends StatelessWidget {
  const HostedGameRow({
    super.key,
    required this.game,
    required this.nameA,
    required this.nameB,
    this.number,
    this.mine = false,
    this.skipped = false,
    this.action,
    this.waiting = false,
    this.live,
    this.onTap,
  });

  final GroupGame game;
  final String nameA;
  final String nameB;

  /// The running score while it's played: a red Live pill and the score
  /// (in place of the action pill; the row still opens the game).
  final LiveScore? live;

  /// Position on the schedule, shown as "Game 5".
  final int? number;

  /// The user's team plays in it: a turf wash.
  final bool mine;

  /// The if-needed final that wasn't needed.
  final bool skipped;

  /// What the user has to do, e.g. "Report score" (an amber pill).
  final String? action;

  /// The user reported and the other captain hasn't confirmed yet.
  final bool waiting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = game;
    final winner = g.winner;
    final status = switch (g.status) {
      _ when skipped => 'Not needed',
      GameStatus.done => 'Final',
      GameStatus.reported => 'Score reported',
      GameStatus.scheduled => null,
    };
    final at = g.startsAt;
    Widget name(String text, String? team) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        fontWeight: winner == null || winner == team
            ? FontWeight.w700
            : FontWeight.w500,
        color: winner != null && winner != team ? c.ink2 : c.ink,
      ),
    );
    Widget score(int? value, String? team) =>
        ScoreText('$value', size: 20, color: winner == team ? c.ink : c.muted);
    final meta = [
      if (number != null) 'Game $number',
      g.label,
      ?status,
      if (waiting) 'Waiting for the other captain',
    ].join(' · ');
    return Material(
      color: mine ? c.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (at != null)
                      Text(
                        DateFormat.jm().format(at),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    Text(
                      'Field ${g.field}',
                      maxLines: 1,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    name(nameA, g.teamA),
                    const SizedBox(height: 2),
                    name(nameB, g.teamB),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (live case final l?) ...[
                const LivePill(),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ScoreText('${l.scoreA}', size: 20),
                    ScoreText('${l.scoreB}', size: 20),
                  ],
                ),
              ] else if (action != null)
                NeedsYouPill(action!)
              else if (g.isDone)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    score(g.scoreA, g.teamA),
                    score(g.scoreB, g.teamB),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pool or league standings: place, team, W–L and point differential.
/// The user's teams ([mine]) are washed in turf.
class HostedStandingsTable extends StatelessWidget {
  const HostedStandingsTable({
    super.key,
    required this.rows,
    required this.nameOf,
    this.mine = const {},
  });

  final List<Standing> rows;
  final String Function(String?) nameOf;
  final Set<String> mine;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: c.muted,
    );
    Widget line({
      required Widget rank,
      required Widget team,
      required Widget record,
      required Widget diff,
      Color? color,
      double vertical = 11,
    }) => Container(
      color: color,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: vertical),
      child: Row(
        children: [
          SizedBox(width: 30, child: rank),
          Expanded(child: team),
          SizedBox(
            width: 52,
            child: Align(alignment: Alignment.centerRight, child: record),
          ),
          SizedBox(
            width: 48,
            child: Align(alignment: Alignment.centerRight, child: diff),
          ),
        ],
      ),
    );
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(
            rank: Text('#', style: head),
            team: Text('TEAM', style: head),
            record: Text('W–L', style: head),
            diff: Text('+/−', style: head),
            vertical: 9,
          ),
          for (final (i, r) in rows.indexed) ...[
            const Divider(height: 1),
            Builder(
              builder: (context) {
                final me = mine.contains(r.teamId);
                final ink = me ? c.accentInk : c.ink;
                return line(
                  color: me ? c.accentSoft : null,
                  rank: ScoreText('${i + 1}', size: 17, color: ink),
                  team: Text(
                    nameOf(r.teamId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  record: ScoreText(
                    '${r.wins}–${r.losses}',
                    size: 17,
                    color: ink,
                  ),
                  diff: Text(
                    '${r.pointDiff > 0 ? '+' : ''}${r.pointDiff}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: me ? FontWeight.w700 : FontWeight.w500,
                      color: me ? c.accentInk : c.ink2,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
