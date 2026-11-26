// Invites' reply-by time and expiry (HostedTournament.inviteReplyBy,
// TournamentEntry.isExpired), checked by
// packages/shared/test/invite_reply_fixtures.test.ts against inviteReplyBy
// and inviteExpired in tournaments.ts. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';

import 'fixture_file.dart';

void main() {
  final start = DateTime.utc(2026, 12, 5, 9);
  final now = DateTime.utc(2026, 11, 14, 12);
  String? iso(DateTime? d) =>
      d?.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$|Z$'), '.000Z');

  test('invite reply-by (invite_reply/cases.json)', () {
    final replyCases = [
      for (final (startsOn, days, at) in [
        (start, null, now),
        (start, 14, now),
        (start, 30, now),
        (start, 3, now),
        // Late: two days to answer.
        (start, 21, now),
        (DateTime.utc(2026, 11, 20, 9), 14, now),
        // Sooner than two days: by the start.
        (DateTime.utc(2026, 11, 15, 9), 7, now),
      ])
        {
          'startsOn': iso(startsOn),
          'days': days,
          'now': iso(at),
          'replyBy': iso(HostedTournament.replyByFor(startsOn, days, at)),
        },
    ];
    final by = DateTime.utc(2026, 11, 21, 9);
    final expiryCases = [
      for (final (status, replyBy, at) in [
        (EntryStatus.invited, by, DateTime.utc(2026, 11, 21, 8)),
        (EntryStatus.invited, by, DateTime.utc(2026, 11, 21, 9)),
        (EntryStatus.invited, by, DateTime.utc(2026, 11, 21, 10)),
        (EntryStatus.invited, null, DateTime.utc(2027, 1, 1)),
        (EntryStatus.applied, by, DateTime.utc(2027, 1, 1)),
        (EntryStatus.withdrawn, by, DateTime.utc(2027, 1, 1)),
      ])
        {
          'status': status.name,
          'replyBy': iso(replyBy),
          'now': iso(at),
          'expired': TournamentEntry(
            teamId: 't',
            teamName: 'T',
            divisionId: 'd',
            status: status,
            replyBy: replyBy,
          ).isExpired(at),
        },
    ];
    checkFixture(
      'invite_reply/cases.json',
      "Invites' reply-by time from the event's start and inviteReplyDays "
          '(at least two days after the invite, never after the start), '
          'when an invite counts as expired, and the reply-by choices.',
      [
        ...replyCases,
        ...expiryCases,
        {
          'choices': HostedTournament.inviteReplyChoices,
          'defaultDays': HostedTournament.defaultInviteReplyDays,
          'labels': [
            for (final d in [null, ...HostedTournament.inviteReplyChoices])
              HostedTournament.inviteReplyLabel(d),
          ],
        },
      ],
    );
  });

  test('an answered invite never expires', () {
    final e = TournamentEntry(
      teamId: 't',
      teamName: 'T',
      divisionId: 'd',
      status: EntryStatus.accepted,
      replyBy: DateTime(2020),
    );
    expect(e.isExpired(DateTime(2030)), isFalse);
  });
}
