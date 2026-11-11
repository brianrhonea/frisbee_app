import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/team/team_repository_firebase.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/attachment_storage.dart';
import 'package:frisbee_app/data/services/feature_flags.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/invite_code.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One request the app sent: method, path and decoded JSON body (null when
/// it had none).
typedef Sent = ({String method, String path, Object? body});

/// [s] as a map, so expect() compares bodies deeply.
Map<String, Object?> _m(Sent s) => {
  'method': s.method,
  'path': s.path,
  'body': s.body,
};

void main() {
  late List<Sent> sent;
  late FakeFirebaseFirestore db;
  late Map<String, Object?> answer;

  ApiClient client() => ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1')),
    client: MockClient((req) async {
      sent.add((
        method: req.method,
        path: req.url.path,
        body: req.body.isEmpty ? null : jsonDecode(req.body),
      ));
      return http.Response(
        jsonEncode(answer),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  TeamRepositoryFirebase repo({bool api = true, FeatureFlags? flags}) =>
      TeamRepositoryFirebase(
        attachments: AttachmentStorage(),
        firestore: db,
        api: api ? client() : null,
        flags: flags,
      );

  const me = AppUser(uid: 'u1', displayName: 'Pat');
  final team = Team.fromMap('t1', {
    'name': 'The Haze',
    'division': 'open',
    'level': 'club',
    'city': 'Austin',
    'ownerId': 'u1',
    'members': {'u1': 'owner', 'u2': 'player'},
    'memberIds': ['u1', 'u2'],
  });
  final org = Team.fromMap('org1', {
    'name': "St. Mary's",
    'division': 'mixed',
    'level': 'youth',
    'kind': 'organization',
  });

  setUp(() {
    sent = [];
    db = FakeFirebaseFirestore();
    answer = {};
  });

  group('ApiClient', () {
    test('sends PUT and PATCH as JSON, DELETE with no body', () async {
      final api = client();
      await api.put('/v1/a', {'x': 1});
      await api.patch('/v1/b', {'y': 2});
      await api.delete('/v1/c');
      expect(
        sent.map(_m),
        [
          (method: 'PUT', path: '/v1/a', body: {'x': 1}),
          (method: 'PATCH', path: '/v1/b', body: {'y': 2}),
          (method: 'DELETE', path: '/v1/c', body: null),
        ].map(_m),
      );
    });
  });

  group('TeamRepositoryFirebase membership through the API', () {
    final cases = <String, (Future<Result<Object?>> Function(), Sent)>{
      'joinGroup': (
        () => repo().joinGroup('t1', me),
        (method: 'POST', path: '/v1/teams/t1/members', body: {}),
      ),
      'requestToJoin': (
        () => repo().requestToJoin('t1', me),
        (method: 'POST', path: '/v1/teams/t1/join-requests', body: {}),
      ),
      'cancelJoinRequest': (
        () => repo().cancelJoinRequest('t1', 'u1'),
        (method: 'DELETE', path: '/v1/teams/t1/join-requests/u1', body: null),
      ),
      'approveJoinRequest': (
        () => repo().approveJoinRequest(
          't1',
          const GroupJoinRequest(uid: 'u9', name: 'Nia'),
        ),
        (
          method: 'POST',
          path: '/v1/teams/t1/join-requests/u9/approve',
          body: {},
        ),
      ),
      'declineJoinRequest': (
        () => repo().declineJoinRequest('t1', 'u9'),
        (method: 'DELETE', path: '/v1/teams/t1/join-requests/u9', body: null),
      ),
      'inviteToTeam': (
        () => repo().inviteToTeam(team, 'u9', me),
        (method: 'POST', path: '/v1/teams/t1/invites', body: {'uid': 'u9'}),
      ),
      'acceptInvite': (
        () => repo().acceptInvite(
          const TeamInvite(teamId: 't1', teamName: 'The Haze'),
          me,
        ),
        (method: 'POST', path: '/v1/me/team-invites/t1/accept', body: {}),
      ),
      'declineInvite': (
        () => repo().declineInvite('u1', 't1'),
        (method: 'DELETE', path: '/v1/me/team-invites/t1', body: null),
      ),
      'updateTeam': (
        () => repo().updateTeam(team),
        (
          method: 'PATCH',
          path: '/v1/teams/t1',
          body: {
            'name': 'The Haze',
            'division': 'open',
            'level': 'club',
            'city': 'Austin',
          },
        ),
      ),
      'publishListing': (
        () => repo().publishListing(team),
        (method: 'PUT', path: '/v1/teams/t1/listing', body: {}),
      ),
      'setMemberRole': (
        () => repo().setMemberRole('t1', 'u2', TeamRole.player),
        (
          method: 'PUT',
          path: '/v1/teams/t1/members/u2/role',
          body: {'role': 'player'},
        ),
      ),
      'setStatKeeper': (
        () => repo().setStatKeeper('t1', 'u2', on: true),
        (
          method: 'PUT',
          path: '/v1/teams/t1/members/u2/stat-keeper',
          body: {'on': true},
        ),
      ),
      'transferOwnership': (
        () => repo().transferOwnership('t1', ownerUid: 'u1', newOwnerUid: 'u2'),
        (method: 'POST', path: '/v1/teams/t1/owner', body: {'uid': 'u2'}),
      ),
      'removeMember': (
        () => repo().removeMember('t1', 'u2'),
        (method: 'DELETE', path: '/v1/teams/t1/members/u2', body: null),
      ),
      'saveRoles': (
        () => repo().saveRoles(
          team,
          roles: {
            'r1': const CustomRole(
              id: 'r1',
              name: 'Stats',
              permissions: {TeamPermission.keepStats},
            ),
          },
          memberRoles: {
            'u2': {'r1'},
          },
        ),
        (
          method: 'PUT',
          path: '/v1/teams/t1/roles',
          body: {
            'roles': {
              'r1': {
                'name': 'Stats',
                'color': 0,
                'position': 0,
                'perms': ['keepStats'],
              },
            },
            'memberRoles': {
              'u2': ['r1'],
            },
          },
        ),
      ),
      'requestCommunityLink': (
        () => repo().requestCommunityLink(team, TeamListing.of(org), me),
        (
          method: 'PUT',
          path: '/v1/teams/t1/community',
          body: {'orgId': 'org1'},
        ),
      ),
      'leaveCommunity': (
        () => repo().leaveCommunity(team),
        (method: 'DELETE', path: '/v1/teams/t1/community', body: null),
      ),
      'acceptLinkRequest': (
        () => repo().acceptLinkRequest(
          org,
          const TeamLinkRequest(teamId: 't1', teamName: 'The Haze'),
          {'b', 'a'},
        ),
        (
          method: 'POST',
          path: '/v1/teams/org1/link-requests/t1/accept',
          body: {
            'roles': ['a', 'b'],
          },
        ),
      ),
      'declineLinkRequest': (
        () => repo().declineLinkRequest('org1', 't1'),
        (method: 'DELETE', path: '/v1/teams/org1/link-requests/t1', body: null),
      ),
      'saveLinkedTeam': (
        () => repo().saveLinkedTeam(
          'org1',
          const LinkedTeam(id: 't1', name: 'The Haze', roles: {'a'}),
        ),
        (
          method: 'PUT',
          path: '/v1/teams/org1/linked-teams/t1',
          body: {
            'roles': ['a'],
          },
        ),
      ),
      'unlinkTeam': (
        () => repo().unlinkTeam('org1', 't1'),
        (method: 'DELETE', path: '/v1/teams/org1/linked-teams/t1', body: null),
      ),
    };

    for (final MapEntry(key: name, value: (run, expected)) in cases.entries) {
      test('$name calls the API and writes nothing itself', () async {
        expect(await run(), isA<Ok<Object?>>());
        expect(sent.map(_m), [_m(expected)]);
        expect((await db.collection('teams').get()).docs, isEmpty);
      });
    }

    test('joinTeam sends the code as typed and returns the team id', () async {
      answer = {'teamId': 't1'};
      final r = await repo().joinTeam('abc-234', me);
      expect(r, isA<Ok<String>>().having((r) => r.value, 'id', 't1'));
      expect(
        _m(sent.single),
        _m((method: 'POST', path: '/v1/teams/join', body: {'code': 'abc-234'})),
      );
    });

    test('invite codes and links come from the API', () async {
      answer = {
        'code': 'ABC234',
        'teamId': 't1',
        'expiresAt': '2026-11-11T12:00:45.000Z',
      };
      final code = await repo().createInviteCode('t1', 'u1');
      expect(
        (code as Ok<InviteCode>).value.expiresAt.toUtc(),
        DateTime.utc(2026, 11, 11, 12, 0, 45),
      );
      await repo().createInviteLink('t1', 'u1', InviteLinkExpiry.week);
      expect(sent.map((s) => s.body), [
        {'teamId': 't1', 'ttl': 45},
        {'teamId': 't1', 'ttl': 604800},
      ]);
    });

    test('createTeamInCommunity posts the team and roles', () async {
      answer = {'id': 'new1'};
      final r = await repo().createTeamInCommunity(
        const NewTeam(
          name: 'JV',
          division: Division.women,
          level: CompetitionLevel.youth,
        ),
        me,
        org,
        {'z', 'a'},
      );
      expect((r as Ok<String>).value, 'new1');
      expect(
        _m(sent.single),
        _m((
          method: 'POST',
          path: '/v1/teams/org1/linked-teams',
          body: {
            'name': 'JV',
            'division': 'women',
            'level': 'youth',
            'city': '',
            'roles': ['a', 'z'],
          },
        )),
      );
    });
  });

  group('the Firestore fallback', () {
    setUp(() async {
      await db.doc('teams/t1').set({
        'name': 'Pickup',
        'kind': 'community',
        'requiresApproval': false,
        'members': {'u1': 'owner'},
        'memberIds': ['u1'],
        'memberNames': {'u1': 'Olive'},
      });
    });

    test('use_api_membership off writes Firestore directly', () async {
      final r = await repo(
        flags: FeatureFlags.fixed({'use_api_membership': false}),
      ).joinGroup('t1', const AppUser(uid: 'u2', displayName: 'Nia'));
      expect(r, isA<Ok<void>>());
      expect(sent, isEmpty);
      expect((await db.doc('teams/t1').get()).get('members'), {
        'u1': 'owner',
        'u2': 'player',
      });
    });

    test('so do builds without an API', () async {
      await repo(
        api: false,
      ).joinGroup('t1', const AppUser(uid: 'u2', displayName: 'Nia'));
      expect((await db.doc('teams/t1').get()).get('memberIds'), ['u1', 'u2']);
    });
  });
}
