import 'package:flutter/material.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/scoreboard.dart';
import 'hosted_status_badge.dart';
import 'hosted_tournament_screen.dart' show hostedDates;
import 'tournament_parts.dart';

/// A game being played, for the navy header: its teams and running
/// score, and how many others are live too.
typedef LiveHeadline = ({
  String nameA,
  String nameB,
  int scoreA,
  int scoreB,
  int more,
});

/// The top of an event's page, under its app bar: on a live (or today's)
/// event a scoreboard-navy block with its status, name, and when, where
/// and who, and the game being played ([live]); otherwise its date badge,
/// status, name and host. Then its tabs.
class EventPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const EventPageHeader._({
    required this.tournament,
    required this.board,
    required this.tabs,
    required this.height,
    this.live,
  });

  /// Sized for [context]'s width and text scale, so a long name gets its
  /// second line.
  factory EventPageHeader.of(
    BuildContext context, {
    required HostedTournament tournament,
    required bool board,
    required PreferredSizeWidget tabs,
    LiveHeadline? live,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final width = MediaQuery.sizeOf(context).width;
    double measure(String text, TextStyle style, double maxWidth, int lines) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: lines,
      )..layout(maxWidth: maxWidth);
      final h = painter.height;
      painter.dispose();
      return h;
    }

    final t = tournament;
    final double body;
    if (board) {
      final w = width - 32;
      body =
          4 +
          measure('LIVE', _statusStyle, w, 1) +
          4 +
          measure(t.name, _nameStyle(26), w, 2) +
          4 +
          measure(_meta(t, board), _metaStyle, w, 1) +
          (live == null
              ? 0
              : 6 + measure(_liveText(live), _liveMeasureStyle, w - 16, 1)) +
          8;
    } else {
      final w = width - 32 - _badge - 14;
      final column =
          22 +
          4 +
          measure(t.name, _nameStyle(22), w, 2) +
          2 +
          measure(_meta(t, board), _metaStyle, w, 1);
      body = 2 + (column > _badge ? column : _badge) + 8;
    }
    return EventPageHeader._(
      tournament: t,
      board: board,
      tabs: tabs,
      live: board ? live : null,
      height: body + tabs.preferredSize.height,
    );
  }

  final HostedTournament tournament;
  final bool board;
  final PreferredSizeWidget tabs;
  final double height;

  /// The game being played, on the board only.
  final LiveHeadline? live;

  static const _liveStyle = TextStyle(
    fontFamily: appFont,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );

  /// The line measured as if all of it were in the score's size.
  static const _liveMeasureStyle = TextStyle(
    fontFamily: scoreFont,
    fontSize: 19,
    fontWeight: FontWeight.w800,
  );

  static String _liveText(LiveHeadline l) =>
      '${l.nameA} ${l.scoreA}–${l.scoreB} ${l.nameB}'
      '${l.more > 0 ? ' · +${l.more} more live' : ''}';

  static const double _badge = 56;

  static const _statusStyle = TextStyle(
    fontFamily: appFont,
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1,
  );

  static TextStyle _nameStyle(double size) => TextStyle(
    fontFamily: appFont,
    fontSize: size,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.15,
  );

  static const _metaStyle = TextStyle(fontFamily: appFont, fontSize: 13);

  /// "Today · Aurora Sports Park · Front Range Ultimate" on the board;
  /// the host otherwise (the date is on the badge).
  static String _meta(HostedTournament t, bool board) {
    if (!board) return t.hostName;
    final today = DateUtils.isSameDay(t.startsOn, DateTime.now());
    return [
      if (t.isLeague) 'Tonight' else if (today) 'Today' else hostedDates(t),
      if (t.location.isNotEmpty) t.location,
      t.hostName,
    ].join(' · ');
  }

  /// "Live", or "Week 3 of 8" in a league's season.
  static String _status(HostedTournament t) {
    final live = t.status == HostedStatus.live ? 'Live' : 'Today';
    final season = t.season;
    if (!t.isLeague || season == null) return live;
    final days = DateUtils.dateOnly(
      DateTime.now(),
    ).difference(DateUtils.dateOnly(t.startsOn)).inDays;
    final week = (days ~/ 7 + 1).clamp(1, season.weeks);
    return '$live · Week $week of ${season.weeks}';
  }

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = tournament;
    final Widget top;
    if (board) {
      top = Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (t.status == HostedStatus.live) ...[
                  const LiveDot(),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    _status(t).toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _statusStyle.copyWith(color: c.onFeature),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _nameStyle(26).copyWith(color: c.onFeature),
            ),
            const SizedBox(height: 4),
            Text(
              _meta(t, board),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _metaStyle.copyWith(color: c.onFeatureMuted),
            ),
            if (live case final l?) ...[
              const SizedBox(height: 6),
              Row(
                key: const Key('header-live'),
                children: [
                  const LiveDot(),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        style: _liveStyle.copyWith(color: c.onFeature),
                        children: [
                          TextSpan(text: '${l.nameA} '),
                          TextSpan(
                            text: '${l.scoreA}–${l.scoreB}',
                            style: _liveMeasureStyle.copyWith(
                              color: c.onFeature,
                            ),
                          ),
                          TextSpan(text: ' ${l.nameB}'),
                          if (l.more > 0)
                            TextSpan(
                              text: ' · +${l.more} more live',
                              style: TextStyle(color: c.onFeatureMuted),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    } else {
      top = Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EventDateBadge(
              startsOn: t.startsOn,
              endsOn: t.isLeague ? null : t.endsOn,
              size: _badge,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 22,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: HostedStatusBadge(status: t.status),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _nameStyle(22).copyWith(color: c.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _meta(t, board),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _metaStyle.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(child: ClipRect(child: top)),
        tabs,
      ],
    );
  }
}
