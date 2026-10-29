import 'package:flutter/material.dart';

import '../../../domain/models/stats.dart';
import '../../core/ui/status_views.dart';
import 'stats_glossary.dart';

typedef _Column = ({
  String label,
  String tooltip,
  num? Function(PlayerStats) value,
  bool pct,
});

/// Sortable per-player stats table. The player column stays pinned while
/// the numbers scroll sideways on narrow screens.
class StatSheetTable extends StatefulWidget {
  const StatSheetTable({
    super.key,
    required this.sheet,
    required this.nameOf,
    this.shrinkWrap = false,
  });

  final StatSheet sheet;
  final String Function(String playerId) nameOf;

  /// Lay out at full height inside another scroll view.
  final bool shrinkWrap;

  @override
  State<StatSheetTable> createState() => _StatSheetTableState();
}

class _StatSheetTableState extends State<StatSheetTable> {
  static final List<_Column> _columns = [
    (label: '+/-', tooltip: 'Score', value: (p) => p.plusMinus, pct: false),
    (
      label: 'O%',
      tooltip: 'O efficiency: share of their O points we scored',
      value: (p) => p.oEfficiency,
      pct: true,
    ),
    (
      label: 'ORTG',
      tooltip:
          'O rating: O efficiency scaled for involvement in scores, '
          'minus turnovers (100 = held every point)',
      value: (p) => _rating(p.oRating),
      pct: false,
    ),
    (
      label: 'BRK%',
      tooltip: 'D efficiency: share of their D points we broke',
      value: (p) => p.dEfficiency,
      pct: true,
    ),
    (
      label: 'DRTG',
      tooltip:
          'D rating: break rate scaled for involvement in breaks, '
          'minus turnovers (100 = broke every point)',
      value: (p) => _rating(p.dRating),
      pct: false,
    ),
    (
      label: 'PTS',
      tooltip: 'Points played',
      value: (p) => p.pointsPlayed,
      pct: false,
    ),
    (label: 'O', tooltip: 'O points', value: (p) => p.pointsO, pct: false),
    (label: 'D', tooltip: 'D points', value: (p) => p.pointsD, pct: false),
    (label: 'TCH', tooltip: 'Touches', value: (p) => p.touches, pct: false),
    (label: 'G', tooltip: 'Goals', value: (p) => p.goals, pct: false),
    (label: 'A', tooltip: 'Assists', value: (p) => p.assists, pct: false),
    (
      label: 'CMP%',
      tooltip: 'Completion %',
      value: (p) => p.completionPct,
      pct: true,
    ),
    (label: 'CTH%', tooltip: 'Catch %', value: (p) => p.catchPct, pct: true),
    (
      label: 'TA',
      tooltip: 'Throwaways',
      value: (p) => p.throwaways,
      pct: false,
    ),
    (label: 'DRP', tooltip: 'Drops', value: (p) => p.drops, pct: false),
    (
      label: 'HB',
      tooltip: 'Hand blocks',
      value: (p) => p.handBlocks,
      pct: false,
    ),
    (
      label: 'BU',
      tooltip: 'Pass breakups',
      value: (p) => p.breakups,
      pct: false,
    ),
    (label: 'BEAT', tooltip: 'Got beat', value: (p) => p.beats, pct: false),
    (label: 'PUL', tooltip: 'Pulls', value: (p) => p.pulls, pct: false),
    (
      label: 'OB',
      tooltip: 'Pulls out of bounds',
      value: (p) => p.pullsOutOfBounds,
      pct: false,
    ),
    (
      label: 'HANG',
      tooltip: 'Average pull hang time (s)',
      value: (p) => p.avgHangTime,
      pct: false,
    ),
  ];

  static int? _rating(double? r) => r == null ? null : (r * 100).round();

  // Ephemeral view state.
  int _sortColumn = 0;
  bool _ascending = false;

  static const _rowHeight = 44.0;
  static const _headingHeight = 48.0;

  List<PlayerStats> get _rows {
    final col = _columns[_sortColumn];
    final rows = widget.sheet.players.values.toList()
      ..sort((a, b) {
        final va = col.value(a) ?? -1, vb = col.value(b) ?? -1;
        return _ascending ? va.compareTo(vb) : vb.compareTo(va);
      });
    return rows;
  }

  void _sort(int i, bool ascending) => setState(() {
    _sortColumn = i;
    _ascending = ascending;
  });

  static String _fmt(_Column c, PlayerStats p) {
    final v = c.value(p);
    if (v == null) return '–';
    if (c.pct) return '${(v * 100).round()}%';
    return v is double ? v.toStringAsFixed(1) : '$v';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sheet.players.isEmpty) {
      return const EmptyView(
        icon: Icons.bar_chart_outlined,
        title: 'No stats yet',
        message: 'Stats appear once points are tracked.',
      );
    }
    final theme = Theme.of(context);
    final rows = _rows;
    final names = DataTable(
      headingRowHeight: _headingHeight,
      dataRowMinHeight: _rowHeight,
      dataRowMaxHeight: _rowHeight,
      horizontalMargin: 12,
      columns: const [DataColumn(label: Text('Player'))],
      rows: [
        for (final p in rows)
          DataRow(
            cells: [
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    widget.nameOf(p.playerId),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
    final numbers = DataTable(
      headingRowHeight: _headingHeight,
      dataRowMinHeight: _rowHeight,
      dataRowMaxHeight: _rowHeight,
      columnSpacing: 20,
      horizontalMargin: 12,
      sortColumnIndex: _sortColumn,
      sortAscending: _ascending,
      columns: [
        for (final c in _columns)
          DataColumn(
            numeric: true,
            label: Text(c.label),
            tooltip: c.tooltip,
            onSort: _sort,
          ),
      ],
      rows: [
        for (final p in rows)
          DataRow(
            cells: [
              for (final (i, c) in _columns.indexed)
                DataCell(
                  Text(
                    _fmt(c, p),
                    style: i == 0
                        ? theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: p.plusMinus < 0
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                          )
                        : null,
                  ),
                ),
            ],
          ),
      ],
    );
    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TeamEfficiencyBar(team: widget.sheet.team),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              elevation: 1,
              color: theme.colorScheme.surface,
              child: names,
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: numbers,
              ),
            ),
          ],
        ),
      ],
    );
    if (widget.shrinkWrap) return table;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: table,
    );
  }
}

/// Team O efficiency (holds) and break rate, with a link to how every
/// stat is calculated.
class _TeamEfficiencyBar extends StatelessWidget {
  const _TeamEfficiencyBar({required this.team});

  final TeamEfficiency team;

  static String _pct(double? v) => v == null ? '–' : '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String label, String value, String detail) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(detail, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              stat(
                'O efficiency',
                _pct(team.oEfficiency),
                '${team.holds} of ${team.oPoints} O points scored',
              ),
              stat(
                'Break rate',
                _pct(team.breakRate),
                '${team.breaks} of ${team.dPoints} D points broken',
              ),
            ],
          ),
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => showStatsGlossary(context),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Stat key: what each column means'),
          ),
        ],
      ),
    );
  }
}
