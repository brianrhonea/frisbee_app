import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/ranking.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/tournament.dart';

void main() {
  group('Team', () {
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
}
