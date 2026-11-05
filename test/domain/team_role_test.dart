import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';

import '../testing/fakes.dart';

void main() {
  const handlers = CustomRole(
    id: 'h',
    name: 'Handlers',
    color: 0xFF1E88E5,
    position: 1,
    permissions: {TeamPermission.manageChats},
  );
  const mods = CustomRole(
    id: 'm',
    name: 'Mods',
    position: 0,
    permissions: {TeamPermission.moderate, TeamPermission.manageMembers},
  );

  group('CustomRole', () {
    test('round-trips through toMap/fromMap', () {
      final back = CustomRole.fromMap('h', handlers.toMap());
      expect(back, handlers);
      expect(handlers.toMap()['perms'], ['manageChats']);
    });

    test('ignores unknown permissions', () {
      final r = CustomRole.fromMap('x', {
        'name': 'X',
        'perms': ['moderate', 'launchRockets'],
      });
      expect(r.permissions, {TeamPermission.moderate});
    });

    test('new ids are unique enough', () {
      final ids = {for (var i = 0; i < 100; i++) newRoleId()};
      expect(ids, hasLength(100));
      expect(ids.first, hasLength(16));
    });
  });

  group('memberPermsFor', () {
    test('unions each member\'s role permissions, dropping empty ones', () {
      final perms = memberPermsFor(
        {
          'a': {'h', 'm'},
          'b': {'gone'},
          'c': {'m'},
        },
        {'h': handlers, 'm': mods},
      );
      expect(perms, {
        'a': {
          TeamPermission.manageChats,
          TeamPermission.moderate,
          TeamPermission.manageMembers,
        },
        'c': {TeamPermission.moderate, TeamPermission.manageMembers},
      });
    });

    test('cleanMemberRoles keeps members and live roles only', () {
      expect(
        cleanMemberRoles(
          {
            'a': {'h', 'gone'},
            'left': {'h'},
            'b': {'gone'},
          },
          {'h': handlers},
          ['a', 'b'],
        ),
        {
          'a': {'h'},
        },
      );
    });

    test('rolesData is what the team doc stores', () {
      final data = rolesData(
        {'h': handlers, 'm': mods},
        {
          'a': {'m', 'h'},
        },
      );
      expect((data['roles'] as Map).keys, containsAll(['h', 'm']));
      expect(data['memberRoles'], {
        'a': ['h', 'm'],
      });
      expect(data['memberPerms'], {
        'a': ['manageMembers', 'manageChats', 'moderate'],
      });
    });
  });

  group('Team with custom roles', () {
    final team = Team.fromMap('t1', {
      'name': 'Ring',
      'ownerId': 'o',
      'members': {'o': 'owner', 'c': 'coach', 'p': 'player', 'q': 'player'},
      'roles': {'h': handlers.toMap(), 'm': mods.toMap()},
      'memberRoles': {
        'p': ['h', 'm'],
      },
      'memberPerms': {
        'p': ['manageChats', 'moderate', 'manageMembers'],
      },
    });

    test('parses roles, assignments and permissions', () {
      expect(team.sortedRoles.map((r) => r.id), ['m', 'h']);
      expect(team.rolesOf('p').map((r) => r.name), ['Mods', 'Handlers']);
      expect(team.rolesOf('q'), isEmpty);
    });

    test('has() comes from tiers, then stored permissions', () {
      expect(team.has('o', TeamPermission.keepStats), isTrue);
      expect(team.has('c', TeamPermission.manageEvents), isTrue);
      expect(team.has('p', TeamPermission.manageChats), isTrue);
      expect(team.has('p', TeamPermission.manageEvents), isFalse);
      expect(team.has('q', TeamPermission.manageChats), isFalse);
      expect(team.has('stranger', TeamPermission.manageChats), isFalse);
      expect(team.canEdit('p'), isFalse);
    });

    test('Manage members removes plain members, not other admins', () {
      expect(team.canRemove('p', 'q'), isTrue);
      expect(team.canRemove('p', 'c'), isFalse);
      expect(team.canRemove('q', 'p'), isFalse);
      expect(team.canRemove('c', 'p'), isFalse, reason: 'p has permissions');
      expect(team.canRemove('o', 'p'), isTrue);
      expect(team.canRemove('o', 'o'), isFalse);
      expect(team.canRemove('q', 'q'), isTrue, reason: 'anyone may leave');
    });

    test('coaches and captains need moving into roles', () {
      final group = Team.fromMap('g', {
        'name': 'Pickup',
        'kind': 'community',
        'ownerId': 'o',
        'members': {'o': 'owner', 'k': 'captain'},
      });
      expect(group.needsRoleMigration, isTrue);
      expect(group.legacyTierRoles()[TeamRole.captain]!.name, 'Organizer');
      expect(team.needsRoleMigration, isTrue);
      expect(teamWith({'o': TeamRole.owner}).needsRoleMigration, isFalse);

      final tiers = teamWith({
        'o': TeamRole.owner,
        'c': TeamRole.coach,
        'k': TeamRole.captain,
      }).legacyTierRoles();
      expect(tiers[TeamRole.coach]!.name, 'Coach');
      expect(tiers[TeamRole.captain]!.name, 'Captain');
      expect(tiers[TeamRole.coach]!.permissions, TeamPermission.values.toSet());
      expect(tiers[TeamRole.coach]!.id, isNot(tiers[TeamRole.captain]!.id));
      // Only tiers someone is on.
      expect(
        teamWith({'o': TeamRole.owner, 'c': TeamRole.coach}).legacyTierRoles(),
        hasLength(1),
      );
    });

    test('only owner and player are on offer', () {
      for (final kind in TeamKind.values) {
        expect(TeamRole.rolesFor(kind), [TeamRole.owner, TeamRole.player]);
      }
    });
  });
}
