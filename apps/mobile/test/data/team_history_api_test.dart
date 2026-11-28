import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/team_history/team_history_repository.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/api_fakes.dart';

Map<String, Object?> _team(
  String id, {
  bool current = true,
  bool? partial,
  Map<String, Object?> seasons = const {},
}) => {
  'teamId': id,
  'teamName': 'Team $id',
  'teamKind': 'team',
  'current': current,
  'spot': {'id': 's-$id', 'name': 'Alex', 'number': 7},
  'seasons': seasons,
  'partial': ?partial,
};

Map<String, Object?> _totals(int games, int goals) => {
  'games': games,
  'points': games * 4,
  'goals': goals,
  'assists': 1,
  'blocks': 2,
  'completions': 9,
  'throwaways': 1,
  'catches': 6,
  'drops': 0,
};

void main() {
  late FakeApi api;
  setUp(() => api = FakeApi());

  test('reads the player\'s history and parses every field', () async {
    api.on('GET /v1/players/u2/team-history', {
      'teams': [
        _team('t1', seasons: {'2026': _totals(3, 5), '2025': _totals(1, 0)}),
        _team('t2', current: false, partial: true),
      ],
    });
    final repo = TeamHistoryRepositoryApi(api: api.client());
    final r = await repo.teamHistory('u2');
    final teams = (r as Ok<List<dynamic>>).value;
    expect(teams, hasLength(2));
    final t1 = teams[0];
    expect(t1.teamName, 'Team t1');
    expect(t1.kind, TeamKind.team);
    expect(t1.current, isTrue);
    expect(t1.partial, isFalse);
    expect(t1.spot.name, 'Alex');
    expect(t1.spot.number, 7);
    expect(t1.seasonsNewestFirst, ['2026', '2025']);
    expect(t1.latestSeason, '2026');
    expect(t1.seasons['2026']!.goals, 5);
    expect(t1.seasons['2026']!.catches, 6);
    final t2 = teams[1];
    expect(t2.current, isFalse);
    expect(t2.partial, isTrue);
    expect(t2.latestSeason, isNull);
    expect(api.to('GET /v1/players/u2/team-history'), hasLength(1));
  });

  test('a spot without a number, other kinds, and bad entries', () async {
    api.on('GET /v1/players/u2/team-history', {
      'teams': [
        {
          ..._team('t1'),
          'teamKind': 'organization',
          'spot': {'id': 's', 'name': 'Bo', 'number': null},
        },
        {..._team('t2'), 'teamKind': 'community'},
        {'teamId': 'broken'},
        'nonsense',
      ],
    });
    final r = await TeamHistoryRepositoryApi(
      api: api.client(),
    ).teamHistory('u2');
    final teams = (r as Ok<List<dynamic>>).value;
    expect(teams, hasLength(2));
    expect(teams[0].spot.number, isNull);
    expect(teams[0].kind, TeamKind.organization);
    expect(teams[1].kind, TeamKind.community);
  });

  test('an empty history is an empty list', () async {
    api.on('GET /v1/players/u2/team-history', {'teams': <Object?>[]});
    final r = await TeamHistoryRepositoryApi(
      api: api.client(),
    ).teamHistory('u2');
    expect((r as Ok<List<dynamic>>).value, isEmpty);
  });

  test('an API error comes back as an error result', () async {
    api.on(
      'GET /v1/players/u2/team-history',
      apiError(500, 'internal', 'Something went wrong'),
    );
    final r = await TeamHistoryRepositoryApi(
      api: api.client(),
    ).teamHistory('u2');
    expect(r, isA<Error<List<dynamic>>>());
  });

  test('a build without an API has no history', () async {
    final r = await TeamHistoryRepositoryApi(api: null).teamHistory('u2');
    expect((r as Ok<List<dynamic>>).value, isEmpty);
  });
}
