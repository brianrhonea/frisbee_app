import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_name.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  TeamListing listing(
    String name, {
    Division division = Division.mixed,
    TeamKind kind = TeamKind.team,
    String id = 'x',
  }) => TeamListing(
    id: id,
    name: name,
    division: division,
    level: CompetitionLevel.club,
    city: '',
    kind: kind,
  );

  group('teamNameKey', () {
    test('ignores case, spacing, punctuation and a leading "the"', () {
      expect(teamNameKey('Texas BQQ'), teamNameKey('texas  bqq'));
      expect(teamNameKey('B.Q.Q.'), teamNameKey('BQQ'));
      expect(teamNameKey('B QQ'), teamNameKey('bqq'));
      expect(teamNameKey("Rock 'n' Roll"), teamNameKey('Rock n Roll'));
      expect(teamNameKey('The Haze'), teamNameKey('Haze'));
    });

    test('spells out state abbreviations and common short forms', () {
      expect(teamNameKey('TX BQQ'), teamNameKey('Texas BQQ'));
      expect(teamNameKey('NY Rumble'), teamNameKey('New York Rumble'));
      expect(teamNameKey('Univ of Oregon'), teamNameKey('University of OR'));
      expect(teamNameKey('Disc & Dash'), teamNameKey('Disc and Dash'));
    });

    test('keeps different names apart', () {
      expect(teamNameKey('Texas BQQ'), isNot(teamNameKey('Texas BBQ')));
      expect(teamNameKey('Haze'), isNot(teamNameKey('Hazel')));
    });
  });

  group('teamNameClashes', () {
    test('the same name in the same division clashes', () {
      expect(
        teamNameClashes(
          listing('Texas BQQ'),
          name: 'tx bqq',
          kind: TeamKind.team,
          division: Division.mixed,
        ),
        isTrue,
      );
    });

    test('another division, another kind, or the team itself is fine', () {
      final l = listing('Texas BQQ', id: 't1');
      expect(
        teamNameClashes(
          l,
          name: 'TX BQQ',
          kind: TeamKind.team,
          division: Division.open,
        ),
        isFalse,
      );
      expect(
        teamNameClashes(
          l,
          name: 'TX BQQ',
          kind: TeamKind.community,
          division: Division.mixed,
        ),
        isFalse,
      );
      expect(
        teamNameClashes(
          l,
          name: 'Texas BQQ',
          kind: TeamKind.team,
          division: Division.mixed,
          excludeId: 't1',
        ),
        isFalse,
      );
    });

    test('groups clash on name alone', () {
      expect(
        teamNameClashes(
          listing('Austin Pickup', kind: TeamKind.community),
          name: 'austin pick-up',
          kind: TeamKind.community,
          division: Division.open,
        ),
        isTrue,
        reason: 'spacing and hyphens are ignored',
      );
      expect(
        teamNameClashes(
          listing(
            'Austin Pickup',
            kind: TeamKind.community,
            division: Division.women,
          ),
          name: 'AUSTIN PICKUP',
          kind: TeamKind.community,
          division: Division.open,
        ),
        isTrue,
      );
    });
  });

  test('the probe searches the distinctive word in all its spellings', () {
    expect(teamNameProbe('TX BQQ'), ['bqq']);
    expect(teamNameProbe('Texas Ultimate'), containsAll(['texas', 'tx']));
    expect(teamNameProbe('New York'), containsAll(['newyork', 'new', 'ny']));
    expect(teamNameProbe(''), isEmpty);
  });

  group('the team repository', () {
    late FakeTeamRepository repo;

    setUp(() => repo = FakeTeamRepository());

    NewTeam team(String name, [Division d = Division.mixed]) =>
        NewTeam(name: name, division: d, level: CompetitionLevel.club);

    test('refuses a near-duplicate name in the same division', () async {
      expect(await repo.createTeam(team('Texas BQQ'), testUser), isA<Ok>());
      final again = await repo.createTeam(team('tx bqq'), testUser);
      expect(
        (again as Error).error,
        isA<TeamNameTakenException>().having(
          (e) => e.toString(),
          'message',
          contains('Mixed team called "Texas BQQ"'),
        ),
      );
      expect(
        await repo.createTeam(team('TX BQQ', Division.open), testUser),
        isA<Ok>(),
      );
    });

    test(
      'renaming to a taken name is refused; keeping your own is fine',
      () async {
        await repo.createTeam(team('Texas BQQ'), testUser);
        final id = (await repo.createTeam(team('Haze'), testUser) as Ok).value;
        final haze = repo.teams[id]!;
        expect(await repo.updateTeam(haze.copyWith(city: 'Austin')), isA<Ok>());
        expect(
          (await repo.updateTeam(haze.copyWith(name: 'TX B.Q.Q.')) as Error)
              .error,
          isA<TeamNameTakenException>(),
        );
      },
    );
  });
}
