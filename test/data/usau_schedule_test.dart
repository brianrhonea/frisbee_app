import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/usau_schedule/usau_schedule_repository_usau.dart';
import 'package:frisbee_app/data/services/usau/usau_client.dart';
import 'package:frisbee_app/data/services/usau/usau_parser.dart';
import 'package:frisbee_app/domain/models/usau_schedule.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Shared with the Cloud Functions parser tests.
String fixture(String name) =>
    File('functions/test/fixtures/$name').readAsStringSync();

const eventUrl =
    'https://play.usaultimate.org/events/2026-USA-Ultimate-Club-Nationals/';
const scheduleUrl = '${eventUrl}schedule/Men/Club-Men/';

const men = UsauDivision(label: 'Men', level: 'Club');

void main() {
  group('parseEventDivisions (real page snapshot)', () {
    final links = parseEventDivisions(
      fixture('event_details.html'),
      pageUrl: eventUrl,
    );

    test('finds one division per gender and level', () {
      expect(links.map((l) => l.division.title), [
        'Club Men',
        'Club Mixed',
        'Club Women',
      ]);
    });

    test('posts the form back with the clicked button', () {
      final request = links.first.request;
      expect(request.url, eventUrl);
      final fields = request.fields!;
      expect(fields['__VIEWSTATE'], isNotEmpty);
      expect(fields['__EVENTTARGET'], '');
      expect(
        fields['CT_Main_0\$rptGenderDivisions\$ctl00\$rptCompetitionLevels'
            '\$ctl00\$btnCompetitionLevel'],
        'Club ',
      );
      // Only the clicked button is submitted.
      expect(
        fields.keys.where((k) => k.contains('btnCompetitionLevel')),
        hasLength(1),
      );
    });

    test('is empty when no schedule is posted', () {
      expect(
        parseEventDivisions(fixture('tournaments.html'), pageUrl: eventUrl),
        isEmpty,
      );
    });
  });

  group('parseDivisionSchedule (real page snapshot)', () {
    final schedule = parseDivisionSchedule(
      fixture('event_details_men_example.html'),
      url: scheduleUrl,
    );
    UsauStage stage(String title) =>
        schedule.stages.firstWhere((s) => s.title == title);

    test('reads the title and one stage per tab', () {
      expect(schedule.title, 'Club - Men');
      expect(schedule.url, scheduleUrl);
      expect(schedule.stages.map((s) => s.title), [
        'Friday Pool Play',
        "2026 Men's Club Championship",
        'Fourth Place Crossovers',
        '2027 Pro Flight Qualification',
        'Elite Flight Placement',
      ]);
    });

    test('reads pool standings with seeds and records', () {
      final pools = stage('Friday Pool Play').pools;
      expect(pools.map((p) => p.name), [
        'Pool A',
        'Pool B',
        'Pool C',
        'Pool D',
      ]);
      final first = pools.first.teams.first;
      expect(pools.first.teams, hasLength(4));
      expect(first.name, 'Ring of Fire');
      expect(first.seed, 8);
      expect(first.record, '3 - 0');
      expect(
        first.url,
        startsWith('https://play.usaultimate.org/events/teams/'),
      );
    });

    test('reads pool games', () {
      final lists = stage('Friday Pool Play').gameLists;
      expect(lists.first.title, 'Pool A Schedule & Scores');
      final g = lists.first.games.first;
      expect(g.id, '418579');
      expect(
        (g.date, g.time, g.field, g.status),
        ('Fri 10/23', '9:00 AM', '5', 'Final'),
      );
      expect(
        (g.home.name, g.home.seed, g.home.score, g.home.won),
        ('Chicago Machine', 1, '15', true),
      );
      expect((g.away.name, g.away.score, g.away.won), ('GOAT', '12', false));
    });

    test('reads crossovers as a game list', () {
      final s = stage('Fourth Place Crossovers');
      expect(s.brackets, isEmpty);
      expect(s.gameLists.single.title, 'Crossover');
      expect(s.gameLists.single.games.first.home.name, 'Sockeye');
    });

    test('reads the championship bracket in play order', () {
      final bracket = stage("2026 Men's Club Championship").brackets.single;
      expect(bracket.title, 'Championship');
      expect(bracket.rounds.map((r) => r.name), [
        'Prequarterfinals',
        'Quarterfinals',
        'Semifinals',
        'Final',
      ]);
      final last = bracket.rounds.last.games.single;
      expect(last.id, '418613');
      expect(last.label, 'G1');
      expect(
        (last.home.name, last.home.score, last.home.won),
        ('Ring of Fire', '15', true),
      );
      expect(
        (last.away.name, last.away.score, last.away.won),
        ('Chicago Machine', '12', false),
      );
      expect(
        (last.field, last.status, last.date, last.time),
        ('4', 'Final', '10/25/2026', '3:45 PM'),
      );
      final semis = bracket.rounds[2].games;
      expect(semis.map((g) => g.nextId), ['418613', '418613']);
      expect(bracket.rounds.first.games.map((g) => g.slot), [2, 3, 6, 7]);
    });

    test('reads every placement bracket', () {
      expect(
        stage('2027 Pro Flight Qualification').brackets.map((b) => b.title),
        [
          'Fifth Place Bracket',
          'Pro Flight Play In (A)',
          'Pro Flight Play In (B)',
        ],
      );
      expect(stage('Elite Flight Placement').brackets.map((b) => b.title), [
        'Eleventh Place',
        'Thirteenth Place Bracket',
        'Fifteenth Place',
      ]);
    });
  });

  group('bracketLayout', () {
    UsauBracketGame game(String id, {int? slot, String next = ''}) =>
        UsauBracketGame(
          id: id,
          slot: slot,
          nextId: next,
          home: const UsauGameSide(name: 'A'),
          away: const UsauGameSide(name: 'B'),
        );

    test('places games in their USAU slots and links them', () {
      final schedule = parseDivisionSchedule(
        fixture('event_details_men_example.html'),
        url: scheduleUrl,
      );
      final bracket = schedule.stages[1].brackets.single;
      final layout = bracketLayout(bracket);
      expect(layout.rows, 7);
      double center(String id) => layout.positions.entries
          .firstWhere((e) => e.key.id == id)
          .value
          .center;
      // Final in the middle, semis at the quarter points; the unused top
      // half slot is trimmed.
      expect(center('418613'), 3.5);
      expect(center('418611'), 1.5);
      expect(center('418612'), 5.5);
      // Prequarterfinal slot 2 of 8 sits in the second row.
      expect(center('418603'), 1.0);
      // 4 prequarters + 4 quarters + 2 semis feed a later game.
      expect(layout.links, hasLength(10));
    });

    test('fills games without slots into free slots', () {
      final layout = bracketLayout(
        UsauBracket(
          title: 'B',
          rounds: [
            UsauBracketRound(
              name: 'Semis',
              games: [
                game('1', next: '3'),
                game('2', slot: 1, next: '3'),
              ],
            ),
            UsauBracketRound(name: 'Final', games: [game('3')]),
          ],
        ),
      );
      final centers = {
        for (final e in layout.positions.entries) e.key.id: e.value.center,
      };
      expect(centers, {'2': 0.5, '1': 1.5, '3': 1.0});
      expect(layout.links, hasLength(2));
    });

    test('trims slots a play-in bracket leaves empty', () {
      final schedule = parseDivisionSchedule(
        fixture('event_details_men_example.html'),
        url: scheduleUrl,
      );
      final layout = bracketLayout(schedule.stages[3].brackets[1]);
      // Quarterfinals in slots 3-4 of 4 and a final above them: 2.5 rows,
      // not 4.
      expect(layout.rows, 2.5);
      final centers = layout.positions.values.map((p) => p.center);
      expect(centers.reduce((a, b) => a < b ? a : b), 0.5);
    });

    test('is empty without rounds', () {
      final layout = bracketLayout(const UsauBracket(title: 'x'));
      expect(layout.rows, 0);
      expect(layout.positions, isEmpty);
    });
  });

  group('UsauClient.fetchDivisionSchedule', () {
    test('replays the postback and follows the redirect', () async {
      final requests = <http.BaseRequest>[];
      final client = UsauClient(
        requestDelay: Duration.zero,
        client: MockClient((req) async {
          requests.add(req);
          if (req.method == 'POST') {
            expect(req.bodyFields['__VIEWSTATE'], isNotEmpty);
            return http.Response(
              '',
              302,
              headers: {
                'location':
                    '/events/2026-USA-Ultimate-Club-Nationals/'
                    'schedule/Men/Club-Men/',
                'set-cookie': 'ASP.NET_SessionId=abc; path=/',
              },
            );
          }
          final name = req.url.path.contains('/schedule/')
              ? 'event_details_men_example.html'
              : 'event_details.html';
          return http.Response.bytes(utf8.encode(fixture(name)), 200);
        }),
      );
      final schedule = await client.fetchDivisionSchedule(eventUrl, men);
      expect(requests.map((r) => r.method), ['GET', 'POST', 'GET']);
      expect(requests.last.headers['Cookie'], contains('ASP.NET_SessionId'));
      expect(schedule.url, scheduleUrl);
      expect(schedule.title, 'Club - Men');
    });

    test('throws when the division is not on the event page', () async {
      final client = UsauClient(
        requestDelay: Duration.zero,
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(fixture('event_details.html')),
            200,
          ),
        ),
      );
      await expectLater(
        client.fetchDivisionSchedule(
          eventUrl,
          const UsauDivision(label: 'Men', level: 'College'),
        ),
        throwsException,
      );
    });
  });

  group('UsauScheduleRepositoryUsau', () {
    test('caches schedules and refreshes from the schedule URL', () async {
      final requests = <String>[];
      final repo = UsauScheduleRepositoryUsau(
        client: UsauClient(
          requestDelay: Duration.zero,
          client: MockClient((req) async {
            requests.add('${req.method} ${req.url.path}');
            if (req.method == 'POST') {
              return http.Response('', 302, headers: {'location': scheduleUrl});
            }
            final name = req.url.path.contains('/schedule/')
                ? 'event_details_men_example.html'
                : 'event_details.html';
            return http.Response.bytes(utf8.encode(fixture(name)), 200);
          }),
        ),
      );

      final divisions = await repo.getDivisions(eventUrl);
      expect((divisions as Ok).value, hasLength(3));
      expect(await repo.getSchedule(eventUrl, men), isA<Ok>());
      expect(await repo.getSchedule(eventUrl, men), isA<Ok>());
      expect(requests, hasLength(4)); // event page twice, post, schedule
      requests.clear();
      expect(await repo.getSchedule(eventUrl, men, refresh: true), isA<Ok>());
      expect(requests, [
        'GET /events/2026-USA-Ultimate-Club-Nationals/schedule/Men/Club-Men/',
      ]);
    });

    test('rejects non-USAU URLs', () async {
      final repo = UsauScheduleRepositoryUsau(
        client: UsauClient(
          client: MockClient((_) async => fail('should not fetch')),
        ),
      );
      expect(await repo.getDivisions('https://example.com/'), isA<Error>());
    });
  });
}
