// The entry deadline and an entry's checklist (HostedTournament
// .effectiveDeadline and .deadlineProblem, EntryChecklist.of), checked by
// packages/shared/test/entry_checklist_fixtures.test.ts against
// effectiveDeadline, entryDeadlineProblem and entryChecklist in
// tournaments.ts. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';

import 'fixture_file.dart';

void main() {
  final start = DateTime.utc(2026, 12, 5, 9);
  final now = DateTime.utc(2026, 11, 20, 12);
  String? iso(DateTime? d) => d?.toUtc().toIso8601String().replaceFirst(
    RegExp(r'\.\d+Z$|Z$'),
    '.000Z',
  );

  test('entry deadline and checklist (entry_checklist/cases.json)', () {
    final set = DateTime.utc(2026, 11, 28, 23, 59);
    final due = DateTime.utc(2026, 11, 25);
    final teamDue = DateTime.utc(2026, 11, 26);
    HostedTournament event({
      DateTime? entryDeadline,
      DateTime? bidDue,
      DateTime? teamFeeDue,
      bool players = false,
      bool teamEntry = false,
    }) => HostedTournament(
      id: 'x',
      hostId: 'h',
      hostName: 'H',
      name: 'X',
      startsOn: start,
      entryDeadline: entryDeadline,
      entryType: players
          ? TournamentEntryType.players
          : TournamentEntryType.teams,
      teamEntry: teamEntry,
      bidFee: BidFee(amountCents: 2000, dueAt: bidDue),
      teamFee: teamFeeDue == null
          ? null
          : BidFee(amountCents: 30000, dueAt: teamFeeDue),
    );
    final deadlines = [
      for (final t in [
        event(),
        event(entryDeadline: set, bidDue: due),
        event(bidDue: due),
        event(players: true, bidDue: due),
        event(players: true, teamEntry: true, bidDue: due, teamFeeDue: teamDue),
        event(players: true, teamEntry: true, bidDue: due),
      ])
        {
          'event': {
            'startsOn': iso(t.startsOn),
            'entryDeadline': iso(t.entryDeadline),
            'entryType': t.entryType.name,
            'teamEntry': t.teamEntry,
            'bidFee': {'dueAt': iso(t.bidFee?.dueAt)},
            'teamFee': t.teamFee == null
                ? null
                : {'dueAt': iso(t.teamFee!.dueAt)},
          },
          'deadline': iso(t.effectiveDeadline),
        },
    ];
    final problems = [
      for (final d in [null, set, start, start.add(const Duration(hours: 1))])
        {
          'check': iso(d),
          'startsOn': iso(start),
          'problem': HostedTournament.deadlineProblem(d, start),
        },
    ];
    final checklists = [
      for (final (status, size, min, paid, owes, deadline) in [
        ('accepted', 7, 7, true, true, set),
        ('accepted', 6, 7, true, true, set),
        ('accepted', 7, 7, false, true, set),
        ('accepted', 7, 7, false, false, set),
        ('applied', 0, 7, false, true, set),
        ('accepted', 0, 7, false, true, DateTime.utc(2026, 11, 19)),
        ('accepted', 7, 7, true, true, DateTime.utc(2026, 11, 19)),
        ('waitlisted', null, 7, false, true, null),
        ('accepted', null, 7, true, true, DateTime.utc(2026, 11, 19)),
      ])
        {
          'status': status,
          'rosterSize': size,
          'minRoster': min,
          'paid': paid,
          'owes': owes,
          'deadline': iso(deadline),
          'now': iso(now),
          'checklist': EntryChecklist.of(
            status: status,
            rosterSize: size,
            minRoster: min,
            paid: paid,
            owes: owes,
            deadline: deadline,
            now: now,
          ).toJson(),
        },
    ];
    checkFixture(
      'entry_checklist/cases.json',
      "When rosters and fees are due (the entry deadline, else the fee's "
          'due date, else the day before the start), when a deadline is '
          "allowed, and where an entry stands: roster set, paid, overdue.",
      [...deadlines, ...problems, ...checklists],
    );
  });
}
