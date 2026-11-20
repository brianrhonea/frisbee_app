// Discover's public lists (F29: public team events; F10: spots left), as
// the website's Discover shows them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/discover.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/routing/routes.dart' show ExploreFilter;
import 'package:frisbee_app/ui/explore/view_models/explore_viewmodel.dart';
import 'package:frisbee_app/ui/explore/view_models/player_search_viewmodel.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/teams/view_models/team_search_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournaments_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournaments_list.dart';

import '../testing/discover_fakes.dart';
import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';
import 'explore_test.dart' show FakeRankingRepository;

void main() {
  final soon = DateTime.now().add(const Duration(days: 2));
  PublicTeamEvent publicEvent(
    String id,
    String title, {
    EventType type = EventType.pickup,
    String teamName = 'Austin Pickup',
    String location = 'Zilker Park',
  }) => PublicTeamEvent(
    id: id,
    teamId: 'team_$id',
    teamName: teamName,
    title: title,
    type: type,
    startsAt: soon,
    location: location,
  );

  HostedTournament event(
    String id,
    String name, {
    HostedStatus status = HostedStatus.registration,
  }) => HostedTournament(
    id: id,
    hostId: 'h',
    hostName: 'Austin Ultimate',
    name: name,
    location: 'Austin',
    startsOn: DateTime.now().add(const Duration(days: 10)),
    status: status,
  );

  ExploreViewModel build(
    FakeDiscoverRepository discover, {
    FakeHostedTournamentRepository? tournaments,
  }) {
    final vm = ExploreViewModel(
      tournamentRepository: tournaments ?? FakeHostedTournamentRepository(),
      rankingRepository: FakeRankingRepository(),
      authRepository: FakeAuthRepository(user: testUser),
      discoverRepository: discover,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  group('ExploreViewModel public lists', () {
    test('reads public events and spots once; All shows every event, Pickup '
        'pickup games, other chips none', () async {
      final discover = FakeDiscoverRepository()
        ..events = [
          publicEvent('p1', 'Sunday pickup'),
          publicEvent(
            'o1',
            'Open practice',
            type: EventType.practice,
            teamName: 'Austin Flyers',
          ),
        ]
        ..spots = {'a': const TournamentSpots(left: 3, cap: 8)};
      final vm = build(discover);
      expect(vm.publicEventsLoaded, isFalse);
      await pumpEventQueue();
      expect(vm.publicEventsLoaded, isTrue);
      expect(discover.eventReads, 1);
      expect(vm.publicEventsFor(null).map((e) => e.id), ['p1', 'o1']);
      expect(vm.publicEventsFor(ExploreFilter.pickup).map((e) => e.id), ['p1']);
      expect(vm.publicEventsFor(ExploreFilter.teams), isEmpty);
      expect(vm.spotsOf('a'), const TournamentSpots(left: 3, cap: 8));
      expect(vm.spotsOf('b'), isNull);
    });

    test('search matches title, team and place on every word', () async {
      final discover = FakeDiscoverRepository()
        ..events = [
          publicEvent('p1', 'Sunday pickup'),
          publicEvent('o1', 'Open practice', type: EventType.practice),
        ];
      final vm = build(discover);
      await pumpEventQueue();
      expect(vm.matchingEvents('zilker sunday', null).map((e) => e.id), ['p1']);
      expect(vm.matchingEvents('austin', ExploreFilter.pickup).length, 1);
      expect(vm.matchingEvents('austin', null).length, 2);
      expect(vm.matchingEvents('', null), isEmpty);
    });

    test('a failed read is an error, not a hang', () async {
      final discover = FakeDiscoverRepository()..eventsFail = true;
      final vm = build(discover);
      await pumpEventQueue();
      expect(vm.publicEventsLoaded, isTrue);
      expect(vm.loadPublic.error, isTrue);
      expect(vm.publicEvents, isEmpty);
    });
  });

  group('Discover', () {
    Future<void> pumpDiscover(
      WidgetTester tester, {
      required FakeDiscoverRepository discover,
      FakeHostedTournamentRepository? tournaments,
    }) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = tournaments ?? FakeHostedTournamentRepository();
      final teamSearch = TeamSearchViewModel(
        teamRepository: FakeTeamRepository(),
        authRepository: FakeAuthRepository(user: testUser),
      );
      final players = PlayerSearchViewModel(
        profileRepository: FakeProfileRepository(),
      );
      final events = HostedTournamentsViewModel(
        tournamentRepository: repo,
        authRepository: FakeAuthRepository(user: testUser),
        discoverRepository: discover,
      );
      addTearDown(teamSearch.dispose);
      addTearDown(players.dispose);
      addTearDown(events.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ExploreScreen(
            viewModel: teamSearch,
            players: players,
            explore: build(discover, tournaments: repo),
            events: events,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, String label) async {
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
          .onSelected!(true);
      await tester.pumpAndSettle();
    }

    testWidgets('lists public team events under All and pickup games under '
        'Pickup, with the team, place and type', (tester) async {
      final discover = FakeDiscoverRepository()
        ..events = [
          publicEvent('p1', 'Sunday pickup'),
          publicEvent(
            'o1',
            'Open practice',
            type: EventType.practice,
            teamName: 'Austin Flyers',
          ),
        ];
      await pumpDiscover(tester, discover: discover);

      expect(find.text('Team events'), findsOneWidget);
      expect(find.text('Sunday pickup'), findsOneWidget);
      expect(find.text('Open practice'), findsOneWidget);
      expect(find.text('Austin Pickup'), findsOneWidget);
      expect(find.text('Austin Flyers'), findsOneWidget);
      expect(find.textContaining('Zilker Park'), findsNWidgets(2));
      expect(find.text('Pickup'), findsWidgets);
      expect(find.text('Practice'), findsOneWidget);

      await pick(tester, 'Pickup');
      expect(find.text('Pickup games'), findsOneWidget);
      expect(find.text('Sunday pickup'), findsOneWidget);
      expect(find.text('Open practice'), findsNothing);
      // Still the search hint for communities.
      expect(find.textContaining('letters to search pickup'), findsOneWidget);

      await pick(tester, 'Teams');
      expect(find.text('Sunday pickup'), findsNothing);
    });

    testWidgets('search finds public events too', (tester) async {
      final discover = FakeDiscoverRepository()
        ..events = [publicEvent('p1', 'Sunday pickup')];
      await pumpDiscover(tester, discover: discover);
      await tester.enterText(find.byType(TextField), 'sunday');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Events'), findsOneWidget);
      expect(find.text('Sunday pickup'), findsOneWidget);
    });

    testWidgets('lists every public event, as the website does', (
      tester,
    ) async {
      final discover = FakeDiscoverRepository()
        ..events = [
          for (var i = 0; i < 12; i++) publicEvent('p$i', 'Pickup night $i'),
        ];
      await pumpDiscover(tester, discover: discover);
      await pick(tester, 'Pickup');
      for (var i = 0; i < 12; i++) {
        await tester.scrollUntilVisible(
          find.text('Pickup night $i'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
      }
    });

    testWidgets('says when there are no pickup games', (tester) async {
      await pumpDiscover(tester, discover: FakeDiscoverRepository());
      await pick(tester, 'Pickup');
      expect(find.textContaining('No pickup games coming up'), findsOneWidget);
    });

    testWidgets('tournament cards show spots left, or Full · waitlist', (
      tester,
    ) async {
      final tournaments = FakeHostedTournamentRepository()
        ..tournaments.addAll({
          'a': event('a', 'Lone Star Classic'),
          'b': event('b', 'Packed Open'),
          'c': event('c', 'Seeded Cup', status: HostedStatus.seeding),
        });
      final discover = FakeDiscoverRepository()
        ..spots = {
          'a': const TournamentSpots(left: 3, cap: 8),
          'b': const TournamentSpots(left: 0, cap: 8),
        };
      await pumpDiscover(tester, discover: discover, tournaments: tournaments);
      expect(find.text('3 spots left'), findsOneWidget);
      expect(find.text('Full · waitlist'), findsOneWidget);
      expect(find.textContaining('spot left'), findsNothing);
    });
  });

  testWidgets('the Tournaments list shows spots left', (tester) async {
    final tournaments = FakeHostedTournamentRepository()
      ..tournaments['a'] = event('a', 'Lone Star Classic');
    final vm = HostedTournamentsViewModel(
      tournamentRepository: tournaments,
      authRepository: FakeAuthRepository(user: testUser),
      discoverRepository: FakeDiscoverRepository()
        ..spots = {'a': const TournamentSpots(left: 1, cap: 4)},
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(home: FindTournamentsScreen(viewModel: vm)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lone Star Classic'), findsOneWidget);
    expect(find.text('1 spot left'), findsOneWidget);
  });

  test('spots labels', () {
    expect(const TournamentSpots(left: 2, cap: 8).label, '2 spots left');
    expect(const TournamentSpots(left: 1, cap: 8).label, '1 spot left');
    expect(const TournamentSpots(left: 0, cap: 8).label, 'Full · waitlist');
    expect(const TournamentSpots(left: 0, cap: 8).isFull, isTrue);
    expect(TournamentSpots.fromJson({'left': 4, 'cap': 12})?.left, 4);
    expect(TournamentSpots.fromJson(null), isNull);
  });

  test('public events read from the API answer', () {
    final e = PublicTeamEvent.fromJson({
      'id': 'e1',
      'teamId': 't1',
      'teamName': 'Austin Pickup',
      'title': 'Sunday pickup',
      'type': 'pickup',
      'startsAt': '2026-11-22T15:00:00.000Z',
      'location': 'Zilker',
    })!;
    expect(e.isPickup, isTrue);
    expect(e.startsAt?.isUtc, isFalse);
    expect(PublicTeamEvent.fromJson({'id': 'e1'}), isNull);
    expect(
      PublicTeamEvent.fromJson({'id': 'e', 'teamId': 't', 'type': 'x'})?.type,
      isNull,
    );
  });
}
