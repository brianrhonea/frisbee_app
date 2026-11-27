import 'package:flutter/material.dart';

import '../themes/theme.dart';
import 'skeleton.dart';

/// One tile of [SummaryTiles]: a big [value] over a short [label], e.g.
/// "3 / Games this week". [onTap] makes it a button.
class SummaryTile {
  const SummaryTile({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;
}

/// A row of summary tiles (C6): up to four big numbers with captions, e.g.
/// the tiles at the top of Home. Tiles share the width equally; when the
/// row can't fit them (a narrow phone or big text) they wrap to a second
/// line instead of squeezing. [loading] shows placeholders of the same
/// size so nothing jumps.
///
/// Numbers are in the score face with tabular figures. Each tile reads as
/// "value, label".
///
/// Website counterpart: `SummaryTiles` (apps/web).
class SummaryTiles extends StatelessWidget {
  const SummaryTiles({super.key, required this.tiles, this.loading = false});

  final List<SummaryTile> tiles;
  final bool loading;

  /// Narrowest a tile gets before the row wraps.
  static const minTileWidth = 140.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final n = tiles.isEmpty ? 1 : tiles.length;
      const gap = AppSpace.sm;
      // How many fit on one line at the minimum width.
      final perLine = ((constraints.maxWidth + gap) / (minTileWidth + gap))
          .floor()
          .clamp(1, n);
      final width = (constraints.maxWidth - gap * (perLine - 1)) / perLine;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final t in loading ? _placeholders(n) : tiles)
            SizedBox(
              width: width,
              child: _Tile(tile: t, loading: loading),
            ),
        ],
      );
    },
  );

  static List<SummaryTile> _placeholders(int n) => [
    for (var i = 0; i < n; i++) const SummaryTile(value: '', label: ''),
  ];
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.loading});

  final SummaryTile tile;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final body = Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: loading
          ? const Skeleton(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 48, height: 28),
                  SizedBox(height: 8),
                  SkeletonBox(width: 80, height: 10),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tile.value,
                    style: TextStyle(
                      fontFamily: scoreFont,
                      fontSize: 30,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                // Eyebrow is one line; a long caption wraps here instead.
                Text(
                  tile.label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: c.muted,
                  ),
                ),
              ],
            ),
    );
    final card = Card(
      child: tile.onTap == null || loading
          ? body
          : InkWell(onTap: tile.onTap, child: body),
    );
    if (loading) return card;
    return Semantics(
      container: true,
      button: tile.onTap != null,
      label: '${tile.value}, ${tile.label}',
      excludeSemantics: true,
      onTap: tile.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: card,
      ),
    );
  }
}
