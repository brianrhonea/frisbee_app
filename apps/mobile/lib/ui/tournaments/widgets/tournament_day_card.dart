import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/hosted_tournament/tournament_days.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/tournament_engine/generator.dart' show ordinal;
import '../../../domain/tournament_engine/tournament_day.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';

/// A team's tournament day, on Home and the team page in place of "Up
/// next": its next game (opponent, time, field), its record and pool
/// place, its last result, and Report score for its captains, which opens
/// the game on the tournament page.
class TournamentDayCard extends StatelessWidget {
  const TournamentDayCard({super.key, required this.day, this.showTeam = true});

  final TeamTournamentDay day;

  /// Say which team it's for (Home, where the user may have several).
  final bool showTeam;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final d = day.day;
    final t = day.tournament;
    final next = d.next;
    final last = d.last;
    void open({String? tab}) => context.push(
      Routes.tournament(t.id, division: day.divisionId, tab: tab),
    );

    final when = switch (d.phase) {
      TournamentDayPhase.tomorrow => 'Tomorrow',
      TournamentDayPhase.today when t.status == HostedStatus.live => 'Live',
      TournamentDayPhase.today => 'Today',
    };
    final String headline;
    final String? detail;
    if (next == null) {
      headline = d.awaiting ? 'Next game to be decided' : 'All games played';
      detail = d.awaiting ? 'Waiting on the bracket' : null;
    } else {
      final opp = next.opponent;
      headline = opp == null ? next.game.label : 'vs ${day.nameOf(opp)}';
      final at = next.game.startsAt;
      detail = [
        if (at != null) _when(at, day.now),
        'Field ${next.game.field}',
        if (opp == null) 'opponent to be decided',
      ].join(' · ');
    }
    final record = [
      if (d.wins + d.losses > 0) '${d.wins}–${d.losses}',
      if (d.poolPlace case final place?) '${ordinal(place)} in Pool ${d.pool}',
    ].join(' · ');
    final action = day.actionGame;

    return FeatureCard(
      onTap: open,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (when == 'Live') ...[
                const LiveDot(),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  [when, if (showTeam) day.team.name].join(' · ').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.onFeature,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              if (record.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  record,
                  style: TextStyle(
                    color: c.onFeatureMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.onFeature,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: c.featureHighlight,
              borderRadius: BorderRadius.circular(controlRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (next != null)
                  Text(
                    (d.phase == TournamentDayPhase.tomorrow
                            ? 'First game'
                            : 'Next game')
                        .toUpperCase(),
                    style: TextStyle(
                      color: c.onFeatureMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                Text(
                  headline,
                  style: TextStyle(
                    color: c.onFeature,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: -0.3,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: TextStyle(color: c.onFeatureMuted, fontSize: 13),
                  ),
              ],
            ),
          ),
          if (last != null) ...[
            const SizedBox(height: 10),
            Text(
              'Last: ${last.won ? 'W' : 'L'} '
              '${last.scoreFor}–${last.scoreAgainst} vs '
              '${day.nameOf(last.opponent)}',
              style: TextStyle(color: c.onFeatureMuted, fontSize: 12.5),
            ),
          ],
          if (day.isCaptain &&
              d.scoreDueKind == ScoreDueKind.awaiting &&
              d.scoreDue != null) ...[
            const SizedBox(height: 8),
            Text(
              'Waiting for the other captain to confirm your score.',
              style: TextStyle(color: c.onFeatureMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (action != null) ...[
                HighlightButton(
                  label: d.scoreDueKind == ScoreDueKind.confirm
                      ? 'Confirm score'
                      : 'Report score',
                  onPressed: () => context.push(
                    Routes.tournament(
                      t.id,
                      division: day.divisionId,
                      game: action.id,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.featureHighlight,
                  foregroundColor: c.onFeature,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                onPressed: () => open(tab: 'schedule'),
                child: const Text(
                  'Schedule & standings',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "8:30 AM" today, "Tomorrow 8:30 AM", else "Sat 8:30 AM".
String _when(DateTime at, DateTime now) {
  final time = DateFormat.jm().format(at);
  // Calendar days apart (UTC dates, so a DST change doesn't shorten one).
  final days = DateTime.utc(
    at.year,
    at.month,
    at.day,
  ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  return switch (days) {
    0 => time,
    1 => 'Tomorrow $time',
    _ => '${DateFormat.E().format(at)} $time',
  };
}
