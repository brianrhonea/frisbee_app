// Checks the Dart side of the fixtures in packages/shared/fixtures, which
// the API's TypeScript tests check too, so the app and the API write the
// same documents and keywords.
//
// After changing what a new team starts with (or the name rules), refresh
// the fixtures, then run the API's tests:
//   flutter test test/data/shared_fixtures_test.dart --dart-define=UPDATE_FIXTURES=true
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/team/team_repository_firebase.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/model_utils.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_name.dart';
import 'package:frisbee_app/domain/models/username.dart';

const _update = bool.fromEnvironment('UPDATE_FIXTURES');
const _fixtures = '../../packages/shared/fixtures';

/// What the fixtures write for each server timestamp.
const serverTimestamp = '<serverTimestamp>';

/// The requests (CreateTeamRequest in packages/shared) and owners.
final _teamCases = <Map<String, Object?>>[
  {
    'case': 'team',
    'teamId': 'team1',
    'owner': {'uid': 'u1', 'displayName': 'Pat Lee', 'email': 'pat@x.test'},
    'request': {
      'name': 'TX B.Q.Q.',
      'division': 'mixed',
      'level': 'club',
      'city': 'Austin',
    },
  },
  {
    'case': 'league team, owner without a display name',
    'teamId': 'team2',
    'owner': {'uid': 'u2', 'email': 'sam@x.test'},
    'request': {
      'name': 'The Haze',
      'division': 'open',
      'level': 'league',
      'leagueId': 'league1',
    },
  },
  {
    'case': 'open community group with a location',
    'teamId': 'group1',
    'owner': {'uid': 'u3'},
    'request': {
      'name': 'Austin Pickup',
      'division': 'mixed',
      'level': 'pickup',
      'city': 'Austin',
      'kind': 'community',
      'description': 'Sundays at the park.',
      'requiresApproval': false,
      'location': {'address': 'Zilker Park', 'lat': 30.2669, 'lng': -97.7729},
    },
  },
  {
    'case': 'private school community hides its location',
    'teamId': 'org1',
    'owner': {'uid': 'u4', 'displayName': 'Coach K'},
    'request': {
      'name': 'St. Mary’s High',
      'division': 'women',
      'level': 'youth',
      'city': 'New York',
      'kind': 'organization',
      'description': '',
      'requiresApproval': true,
      'location': {'address': '1 Main St', 'lat': 40.7128, 'lng': -74.006},
    },
  },
];

/// A team made inside a school or club community (createTeamInCommunity).
final _communityTeamCase = <String, Object?>{
  'case': 'team made in a community',
  'teamId': 'team5',
  'owner': {'uid': 'u5', 'displayName': 'Coach K'},
  'org': {'id': 'org1', 'name': 'St. Mary’s High'},
  'request': {
    'name': 'St. Mary’s JV',
    'division': 'women',
    'level': 'youth',
    'city': 'New York',
  },
};

/// Stored team docs whose directory listing (TeamListing.of) is checked.
final _listingCases = <Map<String, Object?>>[
  {
    'case': 'team',
    'team': {
      'name': 'The Haze',
      'division': 'open',
      'level': 'club',
      'city': 'Austin',
      'ownerId': 'u1',
    },
  },
  {
    'case': 'official team without a city',
    'team': {
      'name': 'Stall 10',
      'division': 'mixed',
      'level': 'league',
      'official': true,
    },
  },
  {
    'case': 'open group with a location',
    'team': {
      'name': 'Austin Pickup',
      'division': 'mixed',
      'level': 'pickup',
      'city': 'Austin',
      'kind': 'community',
      'description': 'Sundays',
      'requiresApproval': false,
      'location': {'address': 'Zilker', 'lat': 30.2, 'lng': -97.7},
    },
  },
  {
    'case': 'private community hides its location',
    'team': {
      'name': 'St. Mary’s High',
      'division': 'women',
      'level': 'youth',
      'city': 'New York',
      'kind': 'organization',
      'description': 'Go Saints',
      'requiresApproval': true,
      'location': {'address': '1 Main St', 'lat': 40.7, 'lng': -74.0},
    },
  },
];

/// Custom roles saved by the owner (saveRoles: cleanMemberRoles + rolesData).
final _roleCases = <Map<String, Object?>>[
  {
    'case': 'roles, members cleaned, perms merged',
    'members': ['u1', 'u2', 'u3'],
    'roles': {
      'a': {
        'name': ' Coach ',
        'color': 4280391411,
        'position': 0,
        'perms': ['keepStats', 'manageTeam'],
      },
      'b': {
        'name': 'Chat',
        'color': 0,
        'position': 1,
        'perms': ['manageChats', 'moderate'],
      },
      'c': {'name': 'Fan', 'color': 0, 'position': 2, 'perms': <String>[]},
    },
    'memberRoles': {
      'u1': ['b', 'a', 'gone'],
      'u2': ['c'],
      'u3': <String>[],
      'left': ['a'],
    },
  },
];

/// Profile names and usernames (profileKeywords, Username).
const _profiles = <(String, String?)>[
  ('Pat Lee', 'pat_lee'),
  ('Pat Lee', null),
  ('Ana María', 'ana.maria'),
  ('X', 'averyveryverylongname'),
];
const _usernames = [
  ' @Pat_Lee ',
  'ab',
  'abcdefghijklmnopqrstu',
  'pat lee',
  '.pat',
  'pat.',
  'p..at',
  'Admin',
  'ok.name_1',
];

const _names = [
  'TX B.Q.Q.',
  'Texas BQQ',
  'The Haze',
  'St. Mary’s High',
  'New York Ultimate Club',
  'univ of NC',
  'Fish & Chips',
  'constructor',
  'Mixed',
  'A-B-C dEF_ghi.jkl',
  'Supercalifragilisticexpialidocious Disc Club',
];

NewTeam _newTeam(Map<String, Object?> r) {
  final loc = r['location'] as Map<String, Object?>?;
  return NewTeam(
    name: r['name']! as String,
    division: Division.values.byName(r['division']! as String),
    level: CompetitionLevel.values.byName(r['level']! as String),
    city: r['city'] as String? ?? '',
    kind: TeamKind.values.byName(r['kind'] as String? ?? 'team'),
    description: r['description'] as String? ?? '',
    requiresApproval: r['requiresApproval'] as bool? ?? false,
    location: loc == null
        ? null
        : GroupLocation(
            address: loc['address']! as String,
            latitude: (loc['lat']! as num).toDouble(),
            longitude: (loc['lng']! as num).toDouble(),
          ),
    leagueId: r['leagueId'] as String?,
  );
}

AppUser _owner(Map<String, Object?> o) => AppUser(
  uid: o['uid']! as String,
  displayName: o['displayName'] as String?,
  email: o['email'] as String?,
);

/// Compares [actual] with the fixture [name], or rewrites it.
void _check(String name, Object actual) {
  final file = File('$_fixtures/$name');
  final text = '${const JsonEncoder.withIndent('  ').convert(actual)}\n';
  if (_update) {
    file.writeAsStringSync(text);
    return;
  }
  expect(
    jsonDecode(file.readAsStringSync()),
    jsonDecode(text),
    reason: 'Out of date: see the comment at the top of this test.',
  );
}

void main() {
  test('new team documents match packages/shared/fixtures', () {
    _check('team_create.json', [
      for (final c in _teamCases)
        {
          ...c,
          'docs': newTeamDocs(
            c['teamId']! as String,
            _newTeam(c['request']! as Map<String, Object?>),
            _owner(c['owner']! as Map<String, Object?>),
            createdAt: serverTimestamp,
          ),
        },
    ]);
  });

  test('a team made in a community matches packages/shared/fixtures', () {
    final c = _communityTeamCase;
    final org = c['org']! as Map<String, Object?>;
    final team = _newTeam(c['request']! as Map<String, Object?>).inCommunity(
      Team.fromMap(org['id']! as String, {'name': org['name']}),
    );
    _check('team_community_create.json', {
      ...c,
      'docs': newTeamDocs(
        c['teamId']! as String,
        team,
        _owner(c['owner']! as Map<String, Object?>),
        createdAt: serverTimestamp,
      ),
    });
  });

  test('directory listings match packages/shared/fixtures', () {
    _check('team_listing.json', [
      for (final c in _listingCases)
        {
          ...c,
          'listing': TeamListing.of(
            Team.fromMap('t1', c['team']! as Map<String, dynamic>),
          ).toMap(),
        },
    ]);
  });

  test('custom roles match packages/shared/fixtures', () {
    _check('team_roles.json', [
      for (final c in _roleCases)
        () {
          final roles = parseCustomRoles(c['roles']);
          final memberRoles = parseMemberLists(c['memberRoles'], (s) => s);
          final members = (c['members']! as List).cast<String>();
          return {
            ...c,
            'saved': rolesData(
              roles,
              cleanMemberRoles(memberRoles, roles, members),
            ),
          };
        }(),
    ]);
  });

  test('profile and username rules match packages/shared/fixtures', () {
    _check('profile_names.json', {
      'keywords': [
        for (final (name, username) in _profiles)
          {
            'name': name,
            'username': username,
            'keywords': profileKeywords(name, username),
          },
      ],
      'usernames': [
        for (final u in _usernames)
          {
            'input': u,
            'normalized': Username.normalize(u),
            'problem': Username.problem(u),
          },
      ],
    });
  });

  test('team name rules match packages/shared/fixtures', () {
    _check('team_names.json', [
      for (final n in _names)
        {
          'name': n,
          'words': teamNameWords(n),
          'key': teamNameKey(n),
          'probe': teamNameProbe(n),
          'keywords': searchKeywords(n),
        },
    ]);
  });
}
