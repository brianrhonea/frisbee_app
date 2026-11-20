import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/tournament_engine/progress.dart';
import '../../../domain/tournament_engine/standings.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/scoreboard.dart';
import '../../tournaments/widgets/tournament_parts.dart' show Pill, PillTone;

/// "Sat, Nov 7 · 9:00 AM".
String tournamentWhen(DateTime d) =>
    DateFormat('EEE, MMM d · h:mm a').format(d);

String gameTime(DateTime? d) => d == null ? '' : DateFormat.jm().format(d);

/// "Sat, Nov 7", or "Sat, Nov 7 – Sun, Nov 8" over several days.
String tournamentDates(TournamentSettings s) {
  final f = DateFormat('EEE, MMM d');
  return s.laterDays.isEmpty
      ? f.format(s.startsAt)
      : '${f.format(s.startsAt)} – ${f.format(s.days.last)} '
            '(${s.days.length} days)';
}

/// "Saturday, Nov 7", a heading for a day of games.
String gameDay(DateTime d) => DateFormat('EEEE, MMM d').format(d);

/// One game: time and field, the two sides and the score.
class GameTile extends StatelessWidget {
  const GameTile({
    super.key,
    required this.game,
    required this.nameA,
    required this.nameB,
    this.highlight = false,
    this.skipped = false,
    this.badge,
    this.onTap,
    this.number,
  });

  final GroupGame game;
  final String nameA;
  final String nameB;

  /// The user's team plays in it.
  final bool highlight;

  /// The if-needed final that wasn't needed.
  final bool skipped;

  /// E.g. "Confirm score".
  final String? badge;
  final VoidCallback? onTap;

  /// Position on the schedule, shown as "Game 5".
  final int? number;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = game;
    final winner = g.winner;
    Widget side(String name, String? team, int? score) {
      final won = winner != null && winner == team;
      final lost = winner != null && winner != team;
      final color = lost ? c.muted : c.ink;
      return Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: won ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ),
          if (g.isDone) ...[
            const SizedBox(width: 8),
            ScoreText('$score', size: 20, color: color),
          ],
        ],
      );
    }

    final status = switch (g.status) {
      _ when skipped => 'Not needed',
      GameStatus.done => 'Final',
      GameStatus.reported => 'Score reported',
      GameStatus.scheduled => null,
    };
    // Reporting or confirming is the captain's to do; waiting isn't.
    final badgeTone = badge != null && badge!.startsWith('Waiting')
        ? PillTone.neutral
        : PillTone.needsYou;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: highlight ? c.accentSoft : null,
      shape: highlight
          ? RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(cardRadius),
              side: BorderSide(color: c.accent.withValues(alpha: 0.35)),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  if (number != null) 'Game $number',
                  if (g.startsAt != null) gameTime(g.startsAt),
                  'Field ${g.field}',
                  g.label,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
              const SizedBox(height: 6),
              side(nameA, g.teamA, g.scoreA),
              const SizedBox(height: 3),
              side(nameB, g.teamB, g.scoreB),
              if (status != null || badge != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (status != null)
                      Pill(
                        status,
                        tone: g.isDone && !skipped
                            ? PillTone.turf
                            : PillTone.neutral,
                      ),
                    if (badge != null) Pill(badge!, tone: badgeTone),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a game's score. Returns (scoreA, scoreB), or null if
/// cancelled.
Future<(int, int)?> showScoreDialog(
  BuildContext context, {
  required String title,
  required String nameA,
  required String nameB,
  int? scoreA,
  int? scoreB,
  String? message,
  String submitLabel = 'Submit',
}) => showDialog<(int, int)>(
  context: context,
  builder: (_) => _ScoreDialog(
    title: title,
    nameA: nameA,
    nameB: nameB,
    scoreA: scoreA,
    scoreB: scoreB,
    message: message,
    submitLabel: submitLabel,
  ),
);

class _ScoreDialog extends StatefulWidget {
  const _ScoreDialog({
    required this.title,
    required this.nameA,
    required this.nameB,
    required this.submitLabel,
    this.scoreA,
    this.scoreB,
    this.message,
  });

  final String title;
  final String nameA;
  final String nameB;
  final int? scoreA;
  final int? scoreB;
  final String? message;
  final String submitLabel;

  @override
  State<_ScoreDialog> createState() => _ScoreDialogState();
}

class _ScoreDialogState extends State<_ScoreDialog> {
  late final _a = TextEditingController(text: widget.scoreA?.toString());
  late final _b = TextEditingController(text: widget.scoreB?.toString());
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _submit() {
    final a = int.tryParse(_a.text.trim());
    final b = int.tryParse(_b.text.trim());
    final why = scoreError(a, b);
    if (why != null) {
      setState(() => _error = why);
      return;
    }
    Navigator.pop(context, (a!, b!));
  }

  Widget _field(String label, TextEditingController c, {bool last = false}) =>
      TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        onSubmitted: last ? (_) => _submit() : null,
        decoration: InputDecoration(labelText: label),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!),
            const SizedBox(height: 12),
          ],
          _field(widget.nameA, _a),
          const SizedBox(height: 8),
          _field(widget.nameB, _b, last: true),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
    ],
  );
}

/// "Pool play + single elimination · 5v5 · to 11 · ...".
String tournamentSummary(GroupTournament t) =>
    '${t.settings.format.label} · ${t.settings.summary}';

/// Status for lists: "Setting up", "Scheduled", or the champion.
String tournamentStatusLabel(GroupTournament t) => switch (t.status) {
  TournamentStatus.setup => 'Setting up',
  TournamentStatus.scheduled => 'Scheduled',
  TournamentStatus.done => 'Finished',
};

/// Pool standings: wins, losses and point differential.
class StandingsTable extends StatelessWidget {
  const StandingsTable({super.key, required this.rows, required this.nameOf});

  final List<Standing> rows;
  final String Function(String?) nameOf;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: c.muted,
    );
    Widget cell(String text, {TextStyle? style, bool end = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Text(
        text,
        textAlign: end ? TextAlign.end : TextAlign.start,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(40),
          1: FlexColumnWidth(),
          2: FixedColumnWidth(40),
          3: FixedColumnWidth(40),
          4: FixedColumnWidth(56),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: BoxDecoration(color: c.field),
            children: [
              for (final (i, h) in ['#', 'Team', 'W', 'L', '+/-'].indexed)
                cell(h, style: head, end: i >= 2),
            ],
          ),
          for (var i = 0; i < rows.length; i++)
            TableRow(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.border)),
              ),
              children: [
                cell(
                  '${i + 1}',
                  style: TextStyle(
                    fontFamily: scoreFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: c.muted,
                  ),
                ),
                cell(
                  nameOf(rows[i].teamId),
                  style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
                ),
                cell('${rows[i].wins}', end: true),
                cell('${rows[i].losses}', end: true),
                cell(
                  '${rows[i].pointDiff > 0 ? '+' : ''}${rows[i].pointDiff}',
                  end: true,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: rows[i].pointDiff > 0 ? c.accent : c.ink,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
