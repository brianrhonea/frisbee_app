import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/ranking/ranking_repository_usau.dart';
import 'package:frisbee_app/data/repositories/tournament/tournament_repository_usau.dart';
import 'package:frisbee_app/data/repositories/usau_team/usau_team_repository_usau.dart';
import 'package:frisbee_app/data/services/usau/usau_client.dart';
import 'package:frisbee_app/data/services/usau/usau_parser.dart';
import 'package:frisbee_app/domain/models/usau_team.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Shared with the Cloud Functions parser tests.
String fixture(String name) =>
    File('functions/test/fixtures/$name').readAsStringSync();

http.Response page(String name) =>
    http.Response.bytes(utf8.encode(fixture(name)), 200);

void main() {
  group('parseDateRange', () {
    test('parses a two-day range at UTC noon', () {
      final (s, e) = parseDateRange('\n  Nov 07, 2026 - Nov 08, 2026  ');
      expect(s, DateTime.utc(2026, 11, 7, 12));
      expect(e, DateTime.utc(2026, 11, 8, 12));
    });

    test('uses start as end for single dates', () {
      final (s, e) = parseDateRange('Mar 1, 2027');
      expect(s, DateTime.utc(2027, 3, 1, 12));
      expect(e, s);
    });

    test('returns nulls for garbage', () {
      expect(parseDateRange('TBA'), (null, null));
    });
  });

  group('parseCompetitionGroup', () {
    for (final (input, level, division) in [
      ('College - Women', 'College', 'Women'),
      ('High School - Mixed DI', 'High School', 'Mixed'),
      ('HIgh School - Girls', 'High School', 'Girls'),
      ('Club - Mixed Division 3', 'Club', 'Mixed'),
      ('Men Upper Division', '', 'Men'),
      ('Dev Division', '', ''),
    ]) {
      test(input, () {
        expect(parseCompetitionGroup(input), (
          level: level,
          division: division,
        ));
      });
    }
  });

  group('parseTournaments (real page snapshot)', () {
    final tournaments = parseTournaments(fixture('tournaments.html'));

    test('finds upcoming and past events', () {
      expect(tournaments.length, greaterThan(20));
    });

    test('parses the first upcoming event', () {
      final t = tournaments.firstWhere((x) => x.id == '2026-Coconut-Classic');
      expect(t.name, '2026 Coconut Classic');
      expect(t.url, 'https://play.usaultimate.org/events/2026-Coconut-Classic');
      expect(t.city, 'Freehold and Lawrenceville');
      expect(t.state, 'NJ');
      expect(t.competitionLevel, 'High School');
      expect(t.divisions, ['Boys', 'Girls']);
      expect(t.startDate, DateTime.utc(2026, 11, 7, 12));
      expect(t.endDate, DateTime.utc(2026, 11, 8, 12));
    });
  });

  group('parseRankSets (real page snapshot)', () {
    final sets = parseRankSets(fixture('rank_sets.html'));

    test('lists published rank sets once each', () {
      final keys = sets.map((s) => s.key).toList();
      expect(keys, containsAll(['Club-Men', 'College-Women']));
      expect(keys.toSet().length, keys.length);
    });

    test('builds absolute urls and labels', () {
      final mixed = sets.firstWhere((s) => s.key == 'Club-Mixed');
      expect(mixed.label, 'Club Mixed');
      expect(
        mixed.url,
        'https://play.usaultimate.org/teams/events/team_rankings/?RankSet=Club-Mixed',
      );
    });
  });

  group('parseRankings (synthetic fixture)', () {
    test('maps columns by header name', () {
      final rows = parseRankings(fixture('rankings_synthetic.html'));
      expect(rows, hasLength(3));
      final first = rows.first;
      expect(first.rank, 1);
      expect(first.teamName, 'Alpha Ultimate');
      expect(first.rating, 2150);
      expect(first.wins, 18);
      expect(first.losses, 2);
      expect(first.region, 'Northwest');
      expect(
        first.teamUrl,
        'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=abc',
      );
      expect(rows[2].rank, 3);
      expect(rows[2].teamName, 'Gamma');
      expect(rows[2].record, '7-9');
    });

    test('returns [] when no rankings table exists', () {
      expect(parseRankings('<table><tr><th>Foo</th></tr></table>'), isEmpty);
    });
  });

  group('parseRankingsPage (paged synthetic fixtures)', () {
    test('skips the pager row and finds the Next postback', () {
      final page = parseRankingsPage(fixture('rankings_paged_1.html'));
      expect(page.entries.map((e) => e.teamName), ['Alpha', 'Beta', 'Gamma']);
      final next = page.next!;
      expect(next.action, './?RankSet=Club-Mixed');
      expect(next.fields, {
        '__EVENTTARGET': r'CT_Main_0$gvList$ctl12$ctl00$ctl05',
        '__EVENTARGUMENT': '',
        '__VIEWSTATE': 'vs-page-1',
        '__EVENTVALIDATION': 'ev-page-1',
        r'CT_Main_0$F_RankSet': '12',
      });
    });

    test('has no next postback on the last page', () {
      final page = parseRankingsPage(fixture('rankings_paged_3.html'));
      expect(page.entries.map((e) => e.teamName), ['Eta']);
      expect(page.next, isNull);
    });

    test('client follows Next postbacks across every page', () async {
      final posts = <Map<String, String>>[];
      final client = UsauClient(
        requestDelay: Duration.zero,
        client: MockClient((req) async {
          if (req.method == 'GET') {
            return http.Response.bytes(
              utf8.encode(fixture('rankings_paged_1.html')),
              200,
              headers: {
                'set-cookie': 'ASP.NET_SessionId=abc; path=/; HttpOnly',
              },
            );
          }
          expect(
            req.url.toString(),
            'https://play.usaultimate.org/teams/events/team_rankings/?RankSet=Club-Mixed',
          );
          expect(req.headers['cookie'], 'ASP.NET_SessionId=abc');
          posts.add(req.bodyFields);
          return switch (req.bodyFields['__VIEWSTATE']) {
            'vs-page-1' => page('rankings_paged_2.html'),
            'vs-page-2' => page('rankings_paged_3.html'),
            _ => http.Response('', 500),
          };
        }),
      );
      final division = await client.fetchDivision((
        key: 'Club-Mixed',
        label: 'Club Mixed',
        title: '',
        url:
            'https://play.usaultimate.org/teams/events/team_rankings/?RankSet=Club-Mixed',
      ));
      expect(division.entries.map((e) => e.rank), [1, 2, 3, 4, 5, 6, 7]);
      expect(division.entries.last.teamName, 'Eta');
      expect(posts.map((p) => p['__EVENTTARGET']), [
        r'CT_Main_0$gvList$ctl12$ctl00$ctl05',
        r'CT_Main_0$gvList$ctl12$ctl00$ctl06',
      ]);
    });
  });

  group('parseUsauTeam (real page snapshot)', () {
    final team = parseUsauTeam(fixture('team_real.html'), url: 'u');

    test('reads name, city and coaches from the profile', () {
      expect(team.name, 'Sample Ultimate');
      expect(team.info, contains((label: 'City', value: 'Dallas, TX')));
      expect(
        team.info,
        contains((label: 'Coaches', value: 'Head Coach Name (Head Coach)')),
      );
    });

    test('reads every roster row', () {
      expect(team.roster, hasLength(32));
      expect(team.roster.first.name, 'Player 01');
      expect(team.roster.map((p) => p.position), contains('Cutter'));
    });

    test('reads the headerless right-rail schedule', () {
      expect(team.games, isNotEmpty);
      final first = team.games.first;
      expect(first.tournament, 'Texas 2 Finger 2026');
      expect(first.date, 'June 27');
      expect(first.score, '13 - 2');
      expect(first.opponent, 'San Antonio Warhawks');
      expect(first.opponentUrl, startsWith('https://play.usaultimate.org/'));
    });
  });

  group('parseUsauTeam (synthetic fixture)', () {
    const url =
        'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=abc';
    final team = parseUsauTeam(fixture('team_synthetic.html'), url: url);

    test('reads the heading and non-empty profile details', () {
      expect(team.name, 'Alpha Ultimate');
      expect(team.url, url);
      expect(team.info, [
        (label: 'Competition Level', value: 'Club'),
        (label: 'Gender Division', value: 'Mixed'),
        (label: 'City', value: 'Seattle, WA'),
      ]);
    });

    test('maps roster columns by header name', () {
      expect(team.roster.map((p) => p.name), [
        'Jordan Lee',
        'Sam Rivera',
        'Alex Kim',
      ]);
      final first = team.roster.first;
      expect(first.number, '7');
      expect(first.pronouns, 'she/her');
      expect(first.position, 'Handler');
      expect(first.height, '5\' 8"');
      expect(team.roster[1].number, '00');
    });

    test('groups games by tournament and scores results', () {
      expect(team.games.map((g) => (g.tournament, g.opponent, g.result)), [
        ('Pro Championships', 'Beta', GameResult.win),
        ('Pro Championships', 'Gamma', GameResult.loss),
        ('Regionals', 'Delta', GameResult.win),
        ('Regionals', 'Epsilon', GameResult.upcoming),
      ]);
      expect(team.games.first.date, 'Aug 3');
      expect(team.games.first.score, '13 - 9');
      expect(
        team.games.first.opponentUrl,
        'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=def',
      );
      expect((team.wins, team.losses), (2, 1));
    });
  });

  group('team tabs and events', () {
    const url =
        'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=abc';

    test('finds only the postback events tab', () {
      final tabs = parseTeamTabs(fixture('team_synthetic.html'), pageUrl: url);
      // Site nav "Events" and the in-page "#schedule" anchor are skipped.
      expect(tabs, hasLength(1));
      expect(tabs.single.url, url);
      expect(tabs.single.fields, {
        '__EVENTTARGET': r'CT_Main_0$lnkEvents',
        '__EVENTARGUMENT': '',
        '__VIEWSTATE': 'vs-team',
      });
    });

    test('follows same-team links but not other teams', () {
      final tabs = parseTeamTabs(
        '<a href="/teams/events/team_events/?TeamId=abc">Events</a>'
        '<a href="/teams/events/team_events/?TeamId=zzz">Schedule</a>',
        pageUrl: url,
      );
      expect(tabs.map((t) => (t.url, t.fields)), [
        (
          'https://play.usaultimate.org/teams/events/team_events/?TeamId=abc',
          null,
        ),
      ]);
    });

    test('parses events with dates, location and finish', () {
      final events = parseUsauTeam(
        fixture('team_schedule_synthetic.html'),
        url: url,
      ).events;
      final pro = events[1];
      expect(pro.name, 'Pro Championships');
      expect(pro.url, 'https://play.usaultimate.org/events/Pro-Championships/');
      expect(pro.startDate, DateTime.utc(2026, 8, 2, 12));
      expect(pro.endDate, DateTime.utc(2026, 8, 4, 12));
      expect(pro.location, 'Denver, CO');
      expect(pro.placement, '1st');
      expect(pro.won, isTrue);
      expect(events[2].won, isFalse);

      final now = DateTime.utc(2026, 10, 28);
      expect(events[0].isUpcoming(now), isTrue);
      expect(pro.isUpcoming(now), isFalse);
      // Still upcoming during its last day.
      expect(events[0].isUpcoming(DateTime.utc(2026, 11, 8, 20)), isTrue);
      expect(events[0].isUpcoming(DateTime.utc(2026, 11, 9, 1)), isFalse);
    });
  });

  group('UsauTeamRepositoryUsau', () {
    const url =
        'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=abc';
    late int requests;
    late bool fail;
    late UsauTeamRepositoryUsau repo;

    setUp(() {
      requests = 0;
      fail = false;
      repo = UsauTeamRepositoryUsau(
        client: UsauClient(
          requestDelay: Duration.zero,
          client: MockClient((req) async {
            requests++;
            if (fail) return http.Response('', 503);
            return req.method == 'POST'
                ? page('team_schedule_synthetic.html')
                : page('team_synthetic.html');
          }),
        ),
      );
    });

    test('caches a team after the first load', () async {
      final first = await repo.getTeam(url);
      expect((first as Ok<UsauTeam>).value.roster, hasLength(3));
      await repo.getTeam(url);
      // The team page plus its "Events & Schedule" postback tab.
      expect(requests, 2);
    });

    test('merges the events & schedule tab into the team', () async {
      final team = (await repo.getTeam(url) as Ok<UsauTeam>).value;
      expect(team.roster, hasLength(3));
      expect(team.events.map((e) => e.name), [
        'Fall Classic',
        'Pro Championships',
        'Regionals',
      ]);
      // Beta appears on both pages but is listed once.
      expect(team.games.map((g) => g.opponent), [
        'Beta',
        'Gamma',
        'Delta',
        'Epsilon',
        'Zeta',
        'Eta',
      ]);
      expect(team.games.last.result, GameResult.upcoming);
    });

    test('retries after a failure', () async {
      fail = true;
      expect(await repo.getTeam(url), isA<Error<UsauTeam>>());
      fail = false;
      expect(await repo.getTeam(url), isA<Ok<UsauTeam>>());
      expect(requests, 3);
    });

    test('refuses urls outside USA Ultimate', () async {
      expect(
        await repo.getTeam('https://example.com/?TeamId=abc'),
        isA<Error<UsauTeam>>(),
      );
      expect(requests, 0);
    });
  });

  test('Routes.usauTeam round-trips the url and name', () {
    const url =
        'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=a%2fb%3d';
    final uri = Uri.parse(Routes.usauTeam(url, name: 'Alpha & Co'));
    expect(uri.path, '/rankings/team');
    expect(uri.queryParameters, {'url': url, 'name': 'Alpha & Co'});
  });

  group('USAU repositories', () {
    late int requests;
    late bool failRankings;

    UsauClient client() => UsauClient(
      requestDelay: Duration.zero,
      client: MockClient((req) async {
        requests++;
        final path = req.url.path;
        if (path.startsWith('/events/tournament')) {
          return page('tournaments.html');
        }
        if (path.startsWith('/teams/events/rankings')) {
          return page('rank_sets.html');
        }
        if (failRankings) return http.Response('', 503);
        return page('rankings_synthetic.html');
      }),
    );

    setUp(() {
      requests = 0;
      failRankings = false;
    });

    test('tournaments are sorted and cached after the first load', () async {
      final repo = TournamentRepositoryUsau(client: client());
      final first = await repo.watchTournaments().first;
      final dates = first.map((t) => t.startDate).nonNulls.toList();
      expect(dates, orderedEquals([...dates]..sort()));
      await repo.watchTournaments().first;
      expect(requests, 1);
    });

    test('rankings emit each division as it loads, then cache', () async {
      final repo = RankingRepositoryUsau(client: client());
      final emissions = await repo.watchDivisions().toList();
      final sets = parseRankSets(fixture('rank_sets.html'));
      expect(emissions.first, hasLength(1));
      expect(emissions.last, hasLength(sets.length));
      expect(requests, 1 + sets.length);

      final cached = await repo.watchDivisions().toList();
      expect(cached.single, hasLength(sets.length));
      expect(requests, 1 + sets.length);
    });

    test('rankings error when every division fails, and can retry', () async {
      failRankings = true;
      final repo = RankingRepositoryUsau(client: client());
      await expectLater(repo.watchDivisions(), emitsError(isA<Exception>()));

      failRankings = false;
      final retried = await repo.watchDivisions().last;
      expect(retried, isNotEmpty);
    });
  });
}
