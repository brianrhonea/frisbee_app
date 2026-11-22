import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_page.dart';

import '../testing/fakes.dart';

// The same cases as packages/shared/test/team_page.test.ts.
void main() {
  test('More rows say what is there, as on the website', () {
    expect(teamMoreSubtitle('playbook'), 'Plays and whiteboards');
    expect(teamMoreSubtitle('manage'), 'Details, sections and visibility');
    expect(teamMoreSubtitle('chat'), '');
    expect(manageRowLabel(group: false), 'Manage team');
    expect(manageRowLabel(group: true), 'Manage group');
  });

  test('roster lines group O, D, both then unassigned, keeping order', () {
    const a = RosterPlayer(id: 'a', name: 'A', line: RosterLine.d);
    const b = RosterPlayer(id: 'b', name: 'B');
    const c = RosterPlayer(id: 'c', name: 'C', line: RosterLine.o);
    const d = RosterPlayer(id: 'd', name: 'D', line: RosterLine.d);
    final groups = groupByLine([a, b, c, d]);
    expect(
      [for (final g in groups) g.line],
      [RosterLine.o, RosterLine.d, null],
    );
    expect([for (final p in groups[1].players) p.id], ['a', 'd']);
    expect(groupByLine([b]), isEmpty);
  });

  test('a line is read and written back as stored, never added', () {
    final p = RosterPlayer.fromMap('a', {'name': 'A', 'line': 'both'});
    expect(p.line, RosterLine.both);
    expect(p.toMap()['line'], 'both');
    expect(p.copyWith(paid: true).line, RosterLine.both);
    expect(
      RosterPlayer.fromMap('b', {'name': 'B', 'line': 'x'}).toMap(),
      isNot(contains('line')),
    );
  });

  // The community page (F27).
  test(
    'organizers: the owner, then anyone who runs the community, by name',
    () {
      final team = Team(
        id: 'g1',
        name: 'Pickup',
        division: Division.mixed,
        level: CompetitionLevel.club,
        kind: TeamKind.community,
        ownerId: 'o',
        members: const {
          'mod': TeamRole.player,
          'o': TeamRole.owner,
          'cap': TeamRole.captain,
          'ev': TeamRole.player,
          'adm': TeamRole.player,
          'p': TeamRole.player,
          'mix': TeamRole.player,
        },
        memberNames: const {
          'mod': 'Mo',
          'o': 'Zed',
          'cap': 'Cy',
          'ev': 'Eve',
          'adm': 'Al',
          'p': 'Pat',
          'mix': 'Max',
        },
        memberPerms: const {
          'mod': {TeamPermission.manageChats, TeamPermission.moderate},
          'ev': {
            TeamPermission.manageChats,
            TeamPermission.manageEvents,
            TeamPermission.moderate,
          },
          'adm': {
            TeamPermission.manageTeam,
            TeamPermission.manageMembers,
            TeamPermission.manageChats,
            TeamPermission.manageEvents,
            TeamPermission.moderate,
          },
          'mix': {TeamPermission.manageMembers},
        },
      );
      expect(communityOrganizers(team), [
        (uid: 'o', name: 'Zed', label: 'Owner'),
        (uid: 'adm', name: 'Al', label: 'Admin'),
        (uid: 'cap', name: 'Cy', label: 'Organizer'),
        (uid: 'ev', name: 'Eve', label: 'Organizer'),
        (uid: 'mix', name: 'Max', label: 'Organizer'),
      ]);
      expect(communityOrganizers(teamWith({'o': TeamRole.owner})), [
        (uid: 'o', name: 'Member', label: 'Owner'),
      ]);
    },
  );

  test('chat section: unread rooms first, marked, then the rest, capped', () {
    ChatRoom room(String id) => ChatRoom(
      id: id,
      name: id,
      readRoles: const {ChatAudience.everyone},
      writeRoles: const {ChatAudience.everyone},
    );
    final rooms = [
      for (final id in [
        'general',
        'rides',
        'drills',
        'socials',
        'gear',
        'tourneys',
        'film',
      ])
        room(id),
    ];
    final s = chatSectionRooms(rooms, [rooms[6], rooms[1]]);
    expect(
      [for (final r in s.rooms) (r.room.id, r.unread)],
      [
        ('film', true),
        ('rides', true),
        ('general', false),
        ('drills', false),
        ('socials', false),
      ],
    );
    expect(s.rooms, hasLength(chatSectionMax));
    expect(s.more, 2);
    final one = chatSectionRooms([rooms.first], const []);
    expect(one.rooms.single.unread, isFalse);
    expect(one.more, 0);
  });

  test('next event card: pickups for a community, events for a school', () {
    expect(nextEventCardText(TeamKind.community), (
      title: 'Next pickup',
      empty: 'No pickup scheduled',
    ));
    expect(nextEventCardText(TeamKind.organization), (
      title: 'Next event',
      empty: 'No events scheduled',
    ));
  });
}
