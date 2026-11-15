// Shared vectors for mapping a Discord template onto a team
// (lib/domain/models/discord_import.dart), checked by
// packages/shared/test/discord_fixtures.test.ts against discord.ts. The
// plan they start from is fixtures/discord/template_plan.json, what both
// server parsers give for the shared made-up template. See
// fixture_file.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/discord_import.dart';
import 'package:frisbee_app/domain/models/team.dart';

import 'fixture_file.dart';

Map<String, dynamic> _templatePlan() =>
    (jsonDecode(
              File(
                '../../packages/shared/fixtures/discord/template_plan.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>)['plan']
        as Map<String, dynamic>;

/// A team as the TypeScript side takes it (ImportTeam): roles as stored,
/// orgRoles and linkedTeams.
Team _team(String id, Map<String, Object?> m) => Team(
  id: id,
  name: id,
  division: Division.mixed,
  level: CompetitionLevel.club,
  ownerId: 'o',
  members: const {'o': TeamRole.owner},
  roles: {
    for (final e in ((m['roles'] as Map?) ?? const {}).entries)
      '${e.key}': CustomRole.fromMap(
        '${e.key}',
        Map<String, dynamic>.from(e.value as Map),
      ),
  },
  orgRoles: {
    for (final e in ((m['orgRoles'] as Map?) ?? const {}).entries)
      '${e.key}': '${e.value}',
  },
  linkedTeams: {
    for (final e in ((m['linkedTeams'] as Map?) ?? const {}).entries)
      '${e.key}': LinkedTeam(
        id: '${e.key}',
        name: '${(e.value as Map)['name']}',
        roles: {for (final r in (e.value as Map)['roles'] as List) '$r'},
      ),
  },
);

List<ChatFolder> _folders(List<Map<String, Object?>> raw) => [
  for (final f in raw)
    ChatFolder(
      id: f['id']! as String,
      name: f['name']! as String,
      position: f['position']! as int,
    ),
];

List<ChatRoom> _rooms(List<Map<String, Object?>> raw) => [
  for (final r in raw)
    ChatRoom(
      id: r['id']! as String,
      name: r['name']! as String,
      folderId: r['folderId'] as String?,
      position: r['position']! as int,
    ),
];

/// Ids n1, n2, ... for new roles and folders.
String Function() _ids() {
  var n = 0;
  return () => 'n${++n}';
}

Map<String, Object?> _import(DiscordImport i) => {
  'roleIdsByKey': i.roleIdsByKey,
  'roles': {for (final e in i.roles.entries) e.key: e.value.toMap()},
  'newRoles': i.newRoles,
  'folders': [
    for (final f in i.folders)
      {
        'id': f.id,
        'name': f.name,
        'position': f.position,
        'readRoles': f.readRoles.toList(),
        'writeRoles': f.writeRoles.toList(),
      },
  ],
  'rooms': [
    for (final r in i.rooms)
      {
        'name': r.name,
        'folderId': r.folderId,
        'position': r.position,
        'readRoles': r.readRoles.toList(),
        'writeRoles': r.writeRoles.toList(),
      },
  ],
  'alreadyHere': i.alreadyHere,
  'tooManyRoles': i.tooManyRoles,
  'isEmpty': i.isEmpty,
};

/// The parts of a plan [DiscordTeamSplit.planFor] chooses.
Map<String, Object?> _planPart(DiscordImportPlan p) => {
  'roles': [for (final r in p.roles) r.key],
  'folders': [for (final f in p.folders) f.key],
  'rooms': [for (final r in p.rooms) r.name],
  'skipped': p.skippedChannels.length,
  'skippedRoles': p.skippedRoles,
};

Map<String, Object?> _role(
  String name,
  int position, [
  List<String> perms = const [],
]) => {'name': name, 'color': 0, 'position': position, 'perms': perms};

/// A community like discord_team_split_test.dart's: Admin, Woof and
/// Whiplash roles, two linked teams.
final _splitPlan = <String, Object?>{
  'serverName': 'Tech Ultimate',
  'roles': [
    for (final (i, (key, name)) in [
      ('r1', 'Admin'),
      ('r2', 'Woof Captain'),
      ('r3', 'Woof Player'),
      ('r4', 'Whiplash Coach'),
    ].indexed)
      {
        'key': key,
        'name': name,
        'color': 0,
        'position': i,
        'perms': <String>[],
      },
  ],
  'folders': [
    {
      'key': 'f1',
      'name': 'Woof',
      'position': 0,
      'readRoles': ['r1', 'r2', 'r3'],
      'writeRoles': <String>[],
    },
    {
      'key': 'f2',
      'name': 'Empty',
      'position': 1,
      'readRoles': ['everyone'],
      'writeRoles': ['everyone'],
    },
  ],
  'rooms': [
    for (final (i, (name, folder, read, write)) in [
      ('general', null, ['everyone'], ['everyone']),
      ('woof-chat', 'f1', ['r1', 'r2', 'r3'], ['r2', 'r3']),
      ('woof-captains', 'f1', ['r1', 'r2'], ['r2']),
      ('admin', null, ['r1'], ['r1']),
      ('captains', null, ['r2', 'r4'], ['r2', 'r4']),
      ('whip', null, ['r4'], <String>[]),
    ].indexed)
      {
        'name': name,
        'folderKey': folder,
        'position': i,
        'readRoles': read,
        'writeRoles': write,
      },
  ],
  'skipped': [
    {'name': 'Voice', 'reason': 'Voice channel'},
  ],
  'skippedRoles': ['Bots'],
};

const _splitRoleIds = {
  'r1': 'admin',
  'r2': 'woofCap',
  'r3': 'woofP',
  'r4': 'whipC',
};

final _org = <String, Object?>{
  'roles': {
    'admin': _role('Admin', 0, ['manageTeam']),
    'woofCap': _role('Woof Captain', 1, ['manageEvents']),
    'woofP': _role('Woof Player', 2),
    'whipC': _role('Whiplash Coach', 3),
  },
  'linkedTeams': {
    'woof': {
      'name': 'Woof',
      'roles': ['woofCap', 'woofP'],
    },
    'whip': {
      'name': 'Whiplash',
      'roles': ['whipC'],
    },
  },
};

void main() {
  test('importing a plan onto a team (discord/import.json)', () {
    final plan = _templatePlan();
    final parsed = DiscordImportPlan.fromMap(plan);
    final fresh = DiscordImport.of(
      parsed,
      team: _team('t', {}),
      folders: const [],
      rooms: const [],
      newId: _ids(),
    );
    // The same plan again, onto what the first import made.
    final again = <String, Object?>{
      'roles': {for (final e in fresh.roles.entries) e.key: e.value.toMap()},
    };
    final againFolders = [
      for (final f in fresh.folders)
        {'id': f.id, 'name': f.name, 'position': f.position},
    ];
    final againRooms = [
      for (final (i, r) in fresh.rooms.indexed)
        {
          'id': 'room$i',
          'name': r.name,
          'folderId': r.folderId,
          'position': r.position,
        },
    ];
    final crowded = <String, Object?>{
      'roles': {
        for (var i = 0; i < CustomRole.maxRoles - 2; i++)
          'old$i': _role(i == 5 ? '  CAPTAINS ' : 'Old $i', i),
      },
    };
    final cases =
        <
          (
            String,
            Map<String, Object?>,
            Map<String, Object?>,
            List<Map<String, Object?>>,
            List<Map<String, Object?>>,
          )
        >[
          ('a team with nothing yet', plan, {}, [], []),
          (
            'the same template again adds nothing',
            plan,
            again,
            againFolders,
            againRooms,
          ),
          (
            'roles and folders reused by name, rooms added after the ones there',
            plan,
            {
              'roles': {
                'mine': _role('ADMIN', 4, ['moderate']),
                'x': _role('Coaches', 9),
              },
            },
            [
              {'id': 'fInfo', 'name': ' info ', 'position': 3},
              {'id': 'fOther', 'name': 'Other', 'position': 7},
            ],
            [
              {
                'id': 'r1',
                'name': 'Announcements',
                'folderId': 'fInfo',
                'position': 2,
              },
              {'id': 'r2', 'name': 'random', 'folderId': null, 'position': 4},
              {
                'id': 'r3',
                'name': 'off-topic',
                'folderId': 'fOther',
                'position': 0,
              },
            ],
          ),
          ('the role limit leaves roles out', plan, crowded, [], []),
          (
            'a plan that already skipped roles',
            {
              ...plan,
              'skippedRoles': ['Bots', 'Muted'],
            },
            {},
            [],
            [],
          ),
        ];
    checkFixture(
      'discord/import.json',
      'DiscordImport.of(plan, team, folders, rooms) with new ids n1, n2, ... '
          '(planImport in discord.ts). Teams are as ImportTeam takes them.',
      [
        for (final (name, plan, team, folders, rooms) in cases)
          {
            'name': name,
            'plan': plan,
            'team': team,
            'folders': folders,
            'rooms': rooms,
            'expected': _import(
              DiscordImport.of(
                DiscordImportPlan.fromMap(plan),
                team: _team('t', team),
                folders: _folders(folders),
                rooms: _rooms(rooms),
                newId: _ids(),
              ),
            ),
          },
      ],
    );
  });

  test('splitting an import among a community\'s teams (discord/split.json)', () {
    final plan = DiscordImportPlan.fromMap(_splitPlan);
    final org = _team('org', _org);
    final cases = <(String, Map<int, String?>)>[
      ('as suggested', {}),
      (
        'overrides: to a team, to the community, and to a team that isn\'t linked (ignored)',
        {0: 'woof', 1: null, 5: 'nope'},
      ),
    ];
    checkFixture(
      'discord/split.json',
      'DiscordTeamSplit.of(plan, org, roleIds, overrides) (splitPlan), then '
          'planFor the community (null) and each team.',
      [
        for (final (name, overrides) in cases)
          () {
            final split = DiscordTeamSplit.of(
              plan,
              org: org,
              roleIds: _splitRoleIds,
              overrides: overrides,
            );
            return {
              'name': name,
              'plan': _splitPlan,
              'org': _org,
              'roleIds': _splitRoleIds,
              'overrides': [
                for (final e in overrides.entries) [e.key, e.value],
              ],
              'suggested': split.suggested,
              'destinations': split.destinations,
              'teams': split.teams.toList(),
              'planFor': {
                for (final t in [null, 'woof', 'whip'])
                  '$t': _planPart(split.planFor(t)),
              },
            };
          }(),
      ],
    );
  });

  test('a linked team\'s share (discord/team_chat.json)', () {
    final plan = DiscordImportPlan.fromMap(_splitPlan);
    final split = DiscordTeamSplit.of(
      plan,
      org: _team('org', _org),
      roleIds: _splitRoleIds,
    );
    // Two community roles at the same position: the app orders them by
    // name, comparing code units.
    final tiedOrg = <String, Object?>{
      'roles': {
        ...(_org['roles']! as Map<String, Object?>),
        'woofCap': _role('Fast', 1),
        'woofP': _role('Élite', 1),
      },
      'linkedTeams': _org['linkedTeams'],
    };
    final cases =
        <
          (
            String,
            Map<String, Object?>,
            String,
            Map<String, Object?>,
            List<Map<String, Object?>>,
            List<Map<String, Object?>>,
          )
        >[
          ('a new team', _org, 'woof', {}, [], []),
          (
            'a team whose copy of a community role was renamed',
            _org,
            'woof',
            {
              'roles': {'mine': _role('Captains', 0)},
              'orgRoles': {'mine': 'woofCap'},
            },
            [
              {'id': 'fw', 'name': 'woof', 'position': 0},
            ],
            [
              {
                'id': 'rw',
                'name': 'woof-chat',
                'folderId': 'fw',
                'position': 0,
              },
            ],
          ),
          (
            'Whiplash: one room only its coach reads, so the whole team',
            _org,
            'whip',
            {},
            [],
            [],
          ),
          ('community roles tied on position', tiedOrg, 'woof', {}, [], []),
        ];
    checkFixture(
      'discord/team_chat.json',
      'TeamChatImport.of(planFor(team), org, team, roleIds, folders, rooms) '
          'with new ids n1, n2, ... (teamChatImport in discord.ts), on the '
          'split.json plan as suggested.',
      [
        for (final (name, org, teamId, team, folders, rooms) in cases)
          () {
            final orgTeam = _team('org', org);
            final teamSplit = DiscordTeamSplit.of(
              plan,
              org: orgTeam,
              roleIds: _splitRoleIds,
            );
            final t = TeamChatImport.of(
              teamSplit.planFor(teamId),
              org: orgTeam,
              team: _team(teamId, team),
              roleIds: _splitRoleIds,
              folders: _folders(folders),
              rooms: _rooms(rooms),
              newId: _ids(),
            );
            return {
              'name': name,
              'plan': _splitPlan,
              'org': org,
              'teamId': teamId,
              'team': team,
              'roleIds': _splitRoleIds,
              'folders': folders,
              'rooms': rooms,
              'expected': {
                'import': _import(t.import),
                'orgRoles': t.orgRoles,
                'isEmpty': t.isEmpty,
              },
            };
          }(),
      ],
    );
    expect(split.teams, {'woof', 'whip'});
  });
}
