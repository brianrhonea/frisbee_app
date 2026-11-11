import 'package:flutter/material.dart';

import '../../../domain/models/stats.dart';

/// How a stat is calculated: a fraction or a list of terms.
sealed class _Formula {
  const _Formula();
}

/// [top] over [bottom], optionally multiplied: "[times] × top / bottom".
class _Fraction extends _Formula {
  const _Fraction(this.top, this.bottom, {this.times});

  final String top;
  final String bottom;
  final String? times;
}

/// Terms on their own lines, e.g. "Goals", "+ Assists".
class _Terms extends _Formula {
  const _Terms(this.lines);

  final List<String> lines;
}

/// One stat on the guide. [abbr] is its column in the stat tables, if
/// it has one.
typedef _Entry = ({
  String title,
  String? abbr,
  String description,
  _Formula formula,
  String? footnote,
});

String _n(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

const _finishedOnly = 'Only finished points count.';

/// Every stat the app shows, grouped as on the guide.
final List<(String, List<_Entry>)> _sections = [
  (
    'Team',
    [
      (
        title: 'Team O Efficiency',
        abbr: null,
        description:
            'How often we score when we start the point on offense '
            '(receiving the pull). Also known as hold percentage.',
        formula: const _Fraction('O points we scored', 'O points played'),
        footnote: _finishedOnly,
      ),
      (
        title: 'Team Break Rate',
        abbr: null,
        description:
            'How often we score when we start the point on defense (after '
            'we pull). Scoring on defense is called a break.',
        formula: const _Fraction('D points we scored', 'D points played'),
        footnote: _finishedOnly,
      ),
    ],
  ),
  (
    'Overall',
    [
      (
        title: 'Plus/Minus',
        abbr: '+/-',
        description:
            'One number for a player\'s overall impact. Good plays add '
            'points and mistakes take them away.',
        formula: const _Terms([
          'Goals',
          '+ Assists',
          '+ 2 × Hand blocks',
          '+ Breakups',
          '− Throwaways',
          '− Drops',
          '− Times beat',
        ]),
        footnote: 'Pulls don\'t count.',
      ),
      (
        title: 'Points Played',
        abbr: 'PTS',
        description: 'How many points the player was on the field for.',
        formula: const _Terms(['O points played', '+ D points played']),
        footnote:
            'A player who subs in or out during a point gets credit for it.',
      ),
      (
        title: 'O Points',
        abbr: 'O',
        description:
            'Points the player started on offense, when we received the '
            'pull.',
        formula: const _Terms(['Number of O points played']),
        footnote: null,
      ),
      (
        title: 'D Points',
        abbr: 'D',
        description: 'Points the player started on defense, when we pulled.',
        formula: const _Terms(['Number of D points played']),
        footnote: null,
      ),
    ],
  ),
  (
    'Efficiency and Ratings',
    [
      (
        title: 'Player O Efficiency',
        abbr: 'O%',
        description:
            'How often we scored on the O points this player was on the '
            'field for.',
        formula: const _Fraction(
          'O points we scored while they played',
          'Their O points played',
        ),
        footnote: _finishedOnly,
      ),
      (
        title: 'Player Break Rate',
        abbr: 'BRK%',
        description:
            'How often we broke on the D points this player was on the '
            'field for.',
        formula: const _Fraction(
          'D points we scored while they played',
          'Their D points played',
        ),
        footnote: _finishedOnly,
      ),
      (
        title: 'O Rating',
        abbr: 'ORTG',
        description:
            'Player O efficiency with extra credit for being involved in '
            'the scores (goals, assists, touches, blocks) and a penalty for '
            'throwaways and drops. 100 means they were on the field for a '
            'score every O point. Higher means they drove the scoring.',
        formula: const _Fraction(
          'Their total point credit on O points',
          'Their O points played',
          times: '100',
        ),
        footnote: 'Point credit is explained below. $_finishedOnly',
      ),
      (
        title: 'D Rating',
        abbr: 'DRTG',
        description:
            'Player break rate with extra credit for being involved in the '
            'breaks (blocks, goals, assists, touches) and a penalty for '
            'throwaways and drops. 100 means they were on the field for a '
            'break every D point.',
        formula: const _Fraction(
          'Their total point credit on D points',
          'Their D points played',
          times: '100',
        ),
        footnote: 'Point credit is explained below. $_finishedOnly',
      ),
      (
        title: 'Point Credit',
        abbr: null,
        description:
            'What one player earns in one finished point. Used by O Rating '
            'and D Rating.',
        formula: _Terms([
          'If we scored:',
          '   ${_n(Involvement.scoredCredit)}',
          '   + ${_n(Involvement.goalBonus)} per goal',
          '   + ${_n(Involvement.assistBonus)} per assist',
          '   + ${_n(Involvement.touchBonus)} per touch',
          '   + ${_n(Involvement.handBlockBonus)} per hand block',
          '   + ${_n(Involvement.breakupBonus)} per breakup',
          "If we didn't score:",
          '   0',
          'Every point:',
          '   − ${_n(Involvement.turnoverPenalty)} per throwaway',
          '   − ${_n(Involvement.turnoverPenalty)} per drop',
        ]),
        footnote:
            "A point we don't score earns nothing, because the point wasn't "
            'won. Throwaways and drops cost a little more than a goal or '
            'assist earns, so a turnover on a point we lose goes negative.',
      ),
    ],
  ),
  (
    'Offense',
    [
      (
        title: 'Touches',
        abbr: 'TCH',
        description: 'Every time the player had the disc.',
        formula: const _Terms(['Pickups', '+ Catches', '+ Goals']),
        footnote: null,
      ),
      (
        title: 'Goals',
        abbr: 'G',
        description: 'Catches in the endzone.',
        formula: const _Terms(['Number of goals caught']),
        footnote: null,
      ),
      (
        title: 'Assists',
        abbr: 'A',
        description: 'Throws that were caught for a goal.',
        formula: const _Terms(['Number of goal throws']),
        footnote: null,
      ),
      (
        title: 'Completion Percentage',
        abbr: 'CMP%',
        description: 'How often the player\'s throws were caught.',
        formula: const _Fraction(
          'Completed throws',
          'Completed throws + Throwaways',
        ),
        footnote:
            'A dropped pass counts as completed for the thrower. It was '
            'catchable, so the drop goes on the receiver.',
      ),
      (
        title: 'Catch Percentage',
        abbr: 'CTH%',
        description: 'How often the player caught catchable passes.',
        formula: const _Fraction('Catches + Goals', 'Catches + Goals + Drops'),
        footnote: null,
      ),
      (
        title: 'Throwaways',
        abbr: 'TA',
        description: 'Throws that turned the disc over.',
        formula: const _Terms(['Number of throwaways']),
        footnote: 'Each one is −1 on plus/minus.',
      ),
      (
        title: 'Drops',
        abbr: 'DRP',
        description: 'Catchable passes the player dropped.',
        formula: const _Terms(['Number of drops']),
        footnote: 'Each one is −1 on plus/minus.',
      ),
    ],
  ),
  (
    'Defense',
    [
      (
        title: 'Hand Blocks',
        abbr: 'HB',
        description:
            'The defender guarding the thrower (the marker) blocks the '
            'throw right as it leaves the thrower\'s hand.',
        formula: const _Terms(['Number of hand blocks']),
        footnote: 'Each one is +2 on plus/minus.',
      ),
      (
        title: 'Breakups',
        abbr: 'BU',
        description:
            'Knocking down or intercepting a pass downfield. Also known as '
            'getting a D.',
        formula: const _Terms(['Number of breakups']),
        footnote: 'Each one is +1 on plus/minus.',
      ),
      (
        title: 'Times Beat',
        abbr: 'BEAT',
        description:
            'The person this player was guarding got open for a catch or a '
            'goal.',
        formula: const _Terms(['Number of times beat']),
        footnote: 'Each one is −1 on plus/minus.',
      ),
    ],
  ),
  (
    'Pulls',
    [
      (
        title: 'Pulls',
        abbr: 'PUL',
        description: 'The throw that starts the point when we\'re on defense.',
        formula: const _Terms(['Number of pulls thrown']),
        footnote: null,
      ),
      (
        title: 'Pulls Out of Bounds',
        abbr: 'OB',
        description: 'Pulls that landed out of bounds.',
        formula: const _Terms(['Number of out-of-bounds pulls']),
        footnote: null,
      ),
      (
        title: 'Average Hang Time',
        abbr: 'HANG',
        description:
            'How long pulls stay in the air, from release until caught or '
            'landed.',
        formula: const _Fraction(
          'Total hang time of timed pulls (seconds)',
          'Number of timed pulls',
        ),
        footnote: null,
      ),
    ],
  ),
];

/// Full-screen guide to every stat and how it's calculated.
Future<void> showStatsGlossary(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const Dialog.fullscreen(child: _Glossary()),
);

class _Glossary extends StatelessWidget {
  const _Glossary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final legend = [
      for (final (_, entries) in _sections)
        for (final e in entries)
          if (e.abbr != null) e,
    ];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('How stats work'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card.filled(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  initiallyExpanded: true,
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(
                    'Legend',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text('What each column in the tables means'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    for (final e in legend)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 72,
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: _AbbrBadge(e.abbr!),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                e.title,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              for (final (title, entries) in _sections) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 10),
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EntryTile(entry: e),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A column label such as "HB".
class _AbbrBadge extends StatelessWidget {
  const _AbbrBadge(this.abbr);

  final String abbr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        abbr,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Title and description; expands to how it's calculated.
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        title: Row(
          children: [
            Flexible(
              child: Text(
                e.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (e.abbr case final abbr?) ...[
              const SizedBox(width: 10),
              _AbbrBadge(abbr),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(e.description, style: theme.textTheme.bodyLarge),
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            'How it\'s calculated',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _FormulaBox(formula: e.formula),
          if (e.footnote case final note?) ...[
            const SizedBox(height: 8),
            Text('* $note', style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _FormulaBox extends StatelessWidget {
  const _FormulaBox({required this.formula});

  final _Formula formula;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.titleMedium;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: switch (formula) {
        _Fraction(:final top, :final bottom, :final times) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (times != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text('$times  ×', style: style),
              ),
            Flexible(
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(top, style: style, textAlign: TextAlign.center),
                    Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: scheme.onSurface,
                    ),
                    Text(bottom, style: style, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ],
        ),
        _Terms(:final lines) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(l, style: style),
              ),
          ],
        ),
      },
    );
  }
}

/// Opens [showStatsGlossary].
class StatsHelpButton extends StatelessWidget {
  const StatsHelpButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => showStatsGlossary(context),
    icon: const Icon(Icons.help_outline),
    label: const Text('How stats work'),
  );
}
