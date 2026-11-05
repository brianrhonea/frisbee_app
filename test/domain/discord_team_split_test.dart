import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/discord_import.dart';
import 'package:frisbee_app/domain/models/team.dart';

/// A Discord server like the user's: Admin, Woof and Whiplash roles.
const _plan = DiscordImportPlan(
  serverName: 'Tech Ultimate',
  roles: [
    PlannedRole(key: 'r1', name: 'Admin'),
    PlannedRole(key: 'r2', name: 'Woof Captain'),
    PlannedRole(key: 'r3', name: 'Woof Player'),
    PlannedRole(key: 'r4', name: 'Whiplash Coach'),
  ],
  folders: [
    PlannedFolder(key: 'f1', name: 'Woof', readRoles: ['r1', 'r2', 'r3']),
  ],
  rooms: [
    PlannedRoom(name: 'general', readRoles: ['everyone']),
    PlannedRoom(
      name: 'woof-chat',
      folderKey: 'f1',
      readRoles: ['r1', 'r2', 'r3'],
      writeRoles: ['r2', 'r3'],
    ),
    PlannedRoom(
      name: 'woof-captains',
      folderKey: 'f1',
      readRoles: ['r1', 'r2'],
      writeRoles: ['r2'],
    ),
    PlannedRoom(name: 'admin', readRoles: ['r1']),
    PlannedRoom(name: 'captains', readRoles: ['r2', 'r4']),
  ],
);

const _roleIds = {
  'r1': 'admin',
  'r2': 'woofCap',
  'r3': 'woofP',
  'r4': 'whipC',
};

final _org = Team(
  id: 'org',
  name: 'Tech Ultimate',
  division: Division.mixed,
  level: CompetitionLevel.college,
  ownerId: 'o',
  kind: TeamKind.organization,
  members: const {'o': TeamRole.owner},
  roles: const {
    'admin': CustomRole(id: 'admin', name: 'Admin', position: 0),
    'woofCap': CustomRole(
      id: 'woofCap',
      name: 'Woof Captain',
      position: 1,
      permissions: {TeamPermission.manageEvents},
    ),
    'woofP': CustomRole(id: 'woofP', name: 'Woof Player', position: 2),
    'whipC': CustomRole(id: 'whipC', name: 'Whiplash Coach', position: 3),
  },
  linkedTeams: const {
    'woof': LinkedTeam(id: 'woof', name: 'Woof', roles: {'woofCap', 'woofP'}),
    'whip': LinkedTeam(id: 'whip', name: 'Whiplash', roles: {'whipC'}),
  },
);

const _woof = Team(
  id: 'woof',
  name: 'Woof',
  division: Division.open,
  level: CompetitionLevel.college,
  ownerId: 'o',
  members: {'o': TeamRole.owner},
  orgId: 'org',
  orgLinked: true,
);

void main() {
  test('rooms only one team reads go to it; the rest stay', () {
    final split = DiscordTeamSplit.of(_plan, org: _org, roleIds: _roleIds);
    expect(split.destinations, [null, 'woof', 'woof', null, null]);
    expect(split.teams, {'woof'});
    expect(split.planFor('woof').rooms.map((r) => r.name), [
      'woof-chat',
      'woof-captains',
    ]);
    expect(split.planFor('woof').folders.map((f) => f.name), ['Woof']);
    expect(split.planFor(null).rooms.map((r) => r.name), [
      'general',
      'admin',
      'captains',
    ]);
    expect(split.planFor(null).folders, isEmpty);
  });

  test('the owner can send a room somewhere else', () {
    final split = DiscordTeamSplit.of(
      _plan,
      org: _org,
      roleIds: _roleIds,
      overrides: {1: null, 4: 'whip', 3: 'nowhere'},
    );
    expect(split.destinations, [null, null, 'woof', null, 'whip']);
    expect(split.suggested[1], 'woof');
  });

  test('a team gets copies of its roles, and rooms open to the team', () {
    final split = DiscordTeamSplit.of(_plan, org: _org, roleIds: _roleIds);
    var n = 0;
    final t = TeamChatImport.of(
      split.planFor('woof'),
      org: _org,
      team: _woof,
      roleIds: _roleIds,
      folders: const [],
      rooms: const [],
      newId: () => 'id${n++}',
    );
    final roles = t.import.roles;
    expect(roles.values.map((r) => r.name), ['Woof Captain', 'Woof Player']);
    final cap = roles.values.firstWhere((r) => r.name == 'Woof Captain');
    expect(cap.permissions, {TeamPermission.manageEvents});
    expect(t.orgRoles.values.toSet(), {'woofCap', 'woofP'});
    expect(t.orgRoles[cap.id], 'woofCap');

    final chat = t.import.rooms.firstWhere((r) => r.name == 'woof-chat');
    expect(chat.readRoles, {ChatAudience.everyone});
    final captains = t.import.rooms.firstWhere(
      (r) => r.name == 'woof-captains',
    );
    expect(captains.readRoles, {cap.id});
    expect(captains.writeRoles, {cap.id});
    expect(t.import.folders.single.name, 'Woof');

    // Running it again reuses the copies and adds nothing.
    final again = TeamChatImport.of(
      split.planFor('woof'),
      org: _org,
      team: _woof.copyWith(roles: roles, orgRoles: t.orgRoles),
      roleIds: _roleIds,
      folders: t.import.folders,
      rooms: [
        for (final r in t.import.rooms)
          ChatRoom(
            id: r.name,
            name: r.name,
            folderId: r.folderId,
            readRoles: r.readRoles,
            writeRoles: r.writeRoles,
          ),
      ],
    );
    expect(again.isEmpty, isTrue);
  });
}
