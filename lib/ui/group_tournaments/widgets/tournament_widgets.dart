import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/group_tournament.dart';
import '../../../domain/tournament_engine/progress.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final g = game;
    final winner = g.winner;
    TextStyle? side(String? team) => theme.textTheme.bodyLarge?.copyWith(
      fontWeight: winner != null && winner == team ? FontWeight.w700 : null,
      color: winner != null && winner != team ? scheme.onSurfaceVariant : null,
    );
    final status = switch (g.status) {
      _ when skipped => 'Not needed',
      GameStatus.done => 'Final',
      GameStatus.reported => 'Score reported',
      GameStatus.scheduled => null,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: highlight ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: Text(nameA, style: side(g.teamA))),
                  if (g.isDone) Text('${g.scoreA}', style: side(g.teamA)),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(child: Text(nameB, style: side(g.teamB))),
                  if (g.isDone) Text('${g.scoreB}', style: side(g.teamB)),
                ],
              ),
              if (status != null || badge != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    if (status != null)
                      Text(status, style: theme.textTheme.bodySmall),
                    if (badge != null)
                      Text(
                        badge!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
