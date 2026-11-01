import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/domain/models/tournament.dart';

void main() {
  group('Team', () {
    test('stats access sits on top of player; old "stats" role maps to it', () {
      final team = Team.fromMap('t1', {
        'name': 'Ring',
        'ownerId': 'a',
        'members': {
          'a': 'owner',
          'k': 'captain',
          'p': 'player',
          's': 'player',
          'old': 'stats',
        },
        'statKeepers': ['s'],
      });
      expect(team.canKeepStats('k'), isTrue);
      expect(team.canKeepStats('p'), isFalse);
      expect(team.canKeepStats('s'), isTrue);
      expect(team.roleOf('old'), TeamRole.player);
      expect(team.isStatKeeper('old'), isTrue);
      expect(team.canEdit('s'), isFalse);
    });

    test('fromMap parses roles and falls back on unknown values', () {
      final team = Team.fromMap('t1', {
        'name': 'Ring',
        'division': 'open',
        'level': 'nope',
        'ownerId': 'a',
        'members': {'a': 'owner', 'b': 'coach', 'c': 'weird'},
        'memberNames': {'a': 'Alex'},
        'createdAt': DateTime(2026),
      });
      expect(team.division, Division.open);
      expect(team.level, CompetitionLevel.club);
      expect(team.roleOf('b'), TeamRole.coach);
      expect(team.roleOf('c'), TeamRole.player);
      expect(team.canEdit('a'), isTrue);
      expect(team.canEdit('c'), isFalse);
      expect(team.nameOf('a'), 'Alex');
      expect(team.nameOf('b'), 'Member');
      expect(team.createdAt, DateTime(2026));
    });
  });

  group('Play', () {
    test('round-trips through toMap/fromMap', () {
      const play = Play(
        id: 'p1',
        name: 'Ho stack',
        category: PlayCategory.endzone,
        notes: 'Iso the 3',
        elements: [
          PlayElement(
            id: 'e1',
            kind: ElementKind.offense,
            position: FieldPoint(0.25, 0.5),
            label: '3',
          ),
        ],
        arrows: [
          PlayArrow(
            id: 'a1',
            kind: ArrowKind.throw_,
            points: [FieldPoint(0, 0), FieldPoint(1, 1)],
          ),
        ],
      );
      final back = Play.fromMap('p1', play.toMap());
      expect(back.name, play.name);
      expect(back.category, PlayCategory.endzone);
      expect(back.notes, 'Iso the 3');
      expect(back.elements.single.position, const FieldPoint(0.25, 0.5));
      expect(back.elements.single.label, '3');
      expect(back.arrows.single.kind, ArrowKind.throw_);
      expect(back.arrows.single.points.last, const FieldPoint(1, 1));
    });
  });

  group('Tournament', () {
    test('isUpcoming uses end date and includes today', () {
      final t = Tournament(
        id: 'x',
        name: 'X',
        url: '',
        startDate: DateTime(2026, 10, 25, 12),
        endDate: DateTime(2026, 10, 26, 12),
      );
      expect(t.isUpcoming(DateTime(2026, 10, 26, 20)), isTrue);
      expect(t.isUpcoming(DateTime(2026, 10, 27)), isFalse);
    });

    test('location joins city and state', () {
      expect(
        const Tournament(id: 'x', name: 'X', url: '', state: 'CO').location,
        'CO',
      );
    });
  });

  group('RankingEntry', () {
    test('record shows dash when unknown', () {
      expect(const RankingEntry(rank: 1, teamName: 'A').record, '—');
      expect(
        const RankingEntry(rank: 1, teamName: 'A', wins: 3, losses: 1).record,
        '3-1',
      );
    });
  });

  group('RosterPlayer', () {
    const sam = RosterPlayer(
      id: 'r1',
      name: 'Sam',
      number: 7,
      onUsau: true,
      paid: true,
    );

    test('shared entry leaves out admin-only status', () {
      expect(
        sam.toMap().keys,
        unorderedEquals(['name', 'number', 'position', 'userId']),
      );
      expect(sam.toStatusMap(), {'onUsau': true, 'paid': true});
    });

    test('reads status only from the status record', () {
      final shared = RosterPlayer.fromMap('r1', {...sam.toMap(), 'paid': true});
      expect(shared.paid, isFalse);
      expect(shared.onUsau, isNull);
      final admin = RosterPlayer.fromMap(
        'r1',
        sam.toMap(),
        status: sam.toStatusMap(),
      );
      expect(admin.paid, isTrue);
      expect(admin.onUsau, isTrue);
    });
  });

  group('TeamListing', () {
    test('searchable by name and city word prefixes', () {
      const listing = TeamListing(
        id: 't1',
        name: 'Ring of Fire',
        division: Division.open,
        level: CompetitionLevel.club,
        city: 'Raleigh',
      );
      final keywords = listing.toMap()['keywords'] as List<String>;
      expect(keywords, containsAll(['r', 'ri', 'ring', 'fire', 'ral']));
      expect(listing.matches('ring ral'), isTrue);
      expect(listing.matches('ring denver'), isFalse);
      expect(listing.subtitle, 'Open · Club · Raleigh');
      expect(listing.toMap().keys, isNot(contains('members')));
    });

    test('round-trips and compares with its team', () {
      final team = Team.fromMap('t1', {
        'name': 'Ring',
        'division': 'open',
        'level': 'college',
        'city': 'Raleigh',
        'members': {'a': 'owner'},
      });
      final listing = TeamListing.fromMap('t1', TeamListing.of(team).toMap());
      expect(listing.sameAs(team), isTrue);
      expect(listing.sameAs(team.copyWith(city: 'Durham')), isFalse);
    });

    test("a private group's listing leaves out its location", () {
      final group = Team.fromMap('g1', {
        'name': 'Friends',
        'division': 'mixed',
        'level': 'pickup',
        'kind': 'community',
        'requiresApproval': true,
        'location': {'address': 'City Park', 'lat': 39.75, 'lng': -104.95},
        'members': {'a': 'owner'},
      });
      expect(group.isPrivateGroup, isTrue);
      final map = TeamListing.of(group).toMap();
      expect(map['location'], isNull);
      final listing = TeamListing.fromMap('g1', map);
      expect(listing.location, isNull);
      expect(listing.sameAs(group), isTrue);
      // An open group shows it.
      final open = group.copyWith(requiresApproval: false);
      expect(TeamListing.of(open).toMap()['location'], isNotNull);
    });
  });

  group('public events and posts', () {
    test('public copy of an event has details only', () {
      final event = TeamEvent.fromMap('e1', {
        'title': 'Tryouts',
        'type': 'other',
        'startsAt': DateTime(2026, 11, 7, 10),
        'public': true,
        'rsvps': {'a': 'going'},
      });
      expect(event.isPublic, isTrue);
      expect(event.toPublicMap().keys, [
        'title',
        'type',
        'startsAt',
        'endsAt',
        'location',
        'notes',
      ]);
      // Personal events share toEditableMap, whose rules don't allow it.
      expect(event.toEditableMap().keys, isNot(contains('public')));
      expect(TeamEvent.fromMap('e2', const {}).isPublic, isFalse);
    });

    test('post round-trips and sorts newest first', () {
      final a = TeamPost.fromMap('a', {
        'title': 'Hi',
        'body': 'Welcome',
        'public': true,
        'createdAt': DateTime(2026, 10, 1),
        'updatedAt': DateTime(2026, 10, 2),
      });
      final b = TeamPost.fromMap('b', {
        'body': 'Later',
        'createdAt': DateTime(2026, 10, 5),
      });
      expect(a.isPublic, isTrue);
      expect(a.edited, isTrue);
      expect(b.isPublic, isFalse);
      expect(a.toEditableMap(), {
        'title': 'Hi',
        'body': 'Welcome',
        'location': '',
        'links': <String>[],
        'images': <Map<String, dynamic>>[],
        'public': true,
      });
      final full = TeamPost.fromMap('c', {
        'location': 'Wash Park',
        'links': ['https://example.com'],
        'images': [
          {
            'path': 'p/0-a.png',
            'name': 'a.png',
            'contentType': 'image/png',
            'size': 3,
          },
        ],
      });
      expect(full.location, 'Wash Park');
      expect(full.links, ['https://example.com']);
      expect(full.images.single.isImage, isTrue);
      expect(full.hasContent, isTrue);
      expect(const TeamPost(id: 'd').hasContent, isFalse);
      expect(([a, b]..sort(TeamPost.newestFirst)).map((p) => p.id), ['b', 'a']);
    });
  });
}
