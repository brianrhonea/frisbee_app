import 'package:flutter/material.dart';

import '../../../domain/models/usau_schedule.dart';
import '../../core/ui/win_colors.dart';

/// One stage (tab) of a division schedule: pool standings, game tables and
/// brackets, top to bottom.
class StageView extends StatelessWidget {
  const StageView({super.key, required this.stage, required this.layoutOf});

  final UsauStage stage;
  final BracketLayout Function(UsauBracket) layoutOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stage.pools.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final p in stage.pools) PoolStandingsCard(pool: p),
              ],
            ),
          ),
        for (final list in stage.gameLists)
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: GameListCard(list: list),
            ),
          ),
        for (final b in stage.brackets) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              b.title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          BracketView(bracket: b, layout: layoutOf(b)),
        ],
      ],
    );
  }
}

class PoolStandingsCard extends StatelessWidget {
  const PoolStandingsCard({super.key, required this.pool});

  final UsauPool pool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SizedBox(
      width: 300,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(pool.name, style: theme.textTheme.titleSmall),
                    ),
                    Text('W - L', style: muted),
                  ],
                ),
              ),
              for (final (i, t) in pool.teams.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text('${i + 1}', style: muted),
                      ),
                      Expanded(
                        child: Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (t.seed != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text('(${t.seed})', style: muted),
                        ),
                      Text(t.record, style: theme.textTheme.titleSmall),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A table of games, e.g. a pool's schedule or the crossovers.
class GameListCard extends StatelessWidget {
  const GameListCard({super.key, required this.list});

  final UsauGameList list;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(list.title, style: theme.textTheme.titleSmall),
            ),
            for (final (i, g) in list.games.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              _GameRow(game: g),
            ],
          ],
        ),
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.game});

  final UsauScheduleGame game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final g = game;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.time, style: theme.textTheme.bodyMedium),
                Text(
                  [
                    g.date,
                    if (g.field.isNotEmpty) 'Field ${g.field}',
                  ].where((s) => s.isNotEmpty).join('\n'),
                  style: muted,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _SideLine(side: g.home),
                const SizedBox(height: 2),
                _SideLine(side: g.away),
              ],
            ),
          ),
          if (g.status.isNotEmpty)
            SizedBox(
              width: 72,
              child: Text(g.status, style: muted, textAlign: TextAlign.end),
            ),
        ],
      ),
    );
  }
}

/// A team's name and score; the winner is bold on a green fill.
class _SideLine extends StatelessWidget {
  const _SideLine({required this.side, this.dense = false});

  final UsauGameSide side;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final win = winColors(context);
    final style =
        (dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
            ?.copyWith(
              fontWeight: side.won ? FontWeight.bold : null,
              color: side.won ? win.onFill : null,
            );
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: side.won ? win.onFill : theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: side.won ? win.fill : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (side.seed != null)
                    TextSpan(text: '${side.seed}  ', style: muted),
                  TextSpan(text: side.name.isEmpty ? 'TBD' : side.name),
                ],
              ),
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(side.score, style: style),
        ],
      ),
    );
  }
}

/// A bracket drawn as a tree: one column per round, first round on the
/// left, with lines joining each game to the one its winner plays next.
/// Scrolls sideways when it's wider than the screen.
class BracketView extends StatelessWidget {
  const BracketView({super.key, required this.bracket, required this.layout});

  final UsauBracket bracket;
  final BracketLayout layout;

  static const cardWidth = 200.0;
  static const cardHeight = 78.0;
  static const columnGap = 36.0;
  static const slotHeight = 92.0;
  static const headerHeight = 28.0;

  static Offset _topLeft(({int column, double center}) p) => Offset(
    p.column * (cardWidth + columnGap),
    headerHeight + p.center * slotHeight - cardHeight / 2,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final columns = bracket.rounds.length;
    final width = columns * cardWidth + (columns - 1) * columnGap;
    final height = headerHeight + layout.rows * slotHeight;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ConnectorPainter(
                    layout: layout,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
              for (final (c, round) in bracket.rounds.indexed)
                Positioned(
                  left: c * (cardWidth + columnGap),
                  top: 0,
                  width: cardWidth,
                  child: Text(
                    round.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final MapEntry(key: game, value: pos)
                  in layout.positions.entries)
                Positioned(
                  left: _topLeft(pos).dx,
                  top: _topLeft(pos).dy,
                  width: cardWidth,
                  height: cardHeight,
                  child: _BracketGameCard(game: game),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BracketGameCard extends StatelessWidget {
  const _BracketGameCard({required this.game});

  final UsauBracketGame game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    final footer = [
      g.label,
      if (g.field.isNotEmpty) 'Field ${g.field}',
      g.date,
      g.time,
    ].where((s) => s.isNotEmpty).join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SideLine(side: g.home, dense: true),
            _SideLine(side: g.away, dense: true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                footer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Elbow lines from each game's right edge to the left edge of the game
/// its winner plays next.
class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter({required this.layout, required this.color});

  final BracketLayout layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final (:from, :to) in layout.links) {
      final a = BracketView._topLeft(layout.positions[from]!);
      final b = BracketView._topLeft(layout.positions[to]!);
      final start =
          a + const Offset(BracketView.cardWidth, BracketView.cardHeight / 2);
      final end = b + const Offset(0, BracketView.cardHeight / 2);
      final midX = end.dx - BracketView.columnGap / 2;
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(midX, start.dy)
          ..lineTo(midX, end.dy)
          ..lineTo(end.dx, end.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) =>
      old.layout != layout || old.color != color;
}
