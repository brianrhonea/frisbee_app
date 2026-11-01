import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_search_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_section_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeEventRepository events;
  late FakeTeamPostRepository posts;
  late FakeAuthRepository auth;
  late FakeFilePickerService picker;

  final now = DateTime(2026, 10, 30, 12);

  setUp(() {
    teams = FakeTeamRepository();
    events = FakeEventRepository()
      ..events['e1'] = TeamEvent(
        id: 'e1',
        title: 'Practice',
        startsAt: now.add(const Duration(days: 1)),
      )
      ..events['e2'] = TeamEvent(
        id: 'e2',
        title: 'Open tryouts',
        type: EventType.other,
        startsAt: now.add(const Duration(days: 2)),
        location: 'Central Park',
        isPublic: true,
        rsvps: const {'owner': RsvpStatus.going},
      )
      ..events['old'] = TeamEvent(
        id: 'old',
        title: 'Last season',
        startsAt: now.subtract(const Duration(days: 30)),
        isPublic: true,
      );
    posts = FakeTeamPostRepository()
      ..posts['t1'] = [
        TeamPost(
          id: 'p1',
          title: 'Tryouts Saturday',
          body: 'Bring cleats.',
          isPublic: true,
          createdAt: now.subtract(const Duration(days: 1)),
        ),
        TeamPost(
          id: 'p2',
          body: 'Fees due Friday.',
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
      ];
    auth = FakeAuthRepository(user: testUser);
    picker = FakeFilePickerService();
  });

  void addTeam(Map<String, TeamRole> members, {bool listed = true}) {
    final team = teamWith(members);
    teams.teams[team.id] = team;
    if (listed) teams.listings[team.id] = TeamListing.of(team);
  }

  TeamHomeViewModel homeVm() => TeamHomeViewModel(
    teamId: 't1',
    teamRepository: teams,
    eventRepository: events,
    teamPostRepository: posts,
    authRepository: auth,
    filePicker: picker,
    clock: () => now,
  );

  group('TeamHomeViewModel', () {
    test('members see every post and upcoming event', () async {
      addTeam({'owner': TeamRole.owner, testUser.uid: TeamRole.player});
      final vm = homeVm();
      await pumpEventQueue();

      expect(vm.isMember, isTrue);
      expect(vm.myRole, TeamRole.player);
      expect(vm.canPost, isFalse);
      expect(vm.upcomingEvents.map((e) => e.id), ['e1', 'e2']);
      expect(vm.posts.map((p) => p.id), ['p2', 'p1']);
      expect(posts.watches, [false]);
    });

    test(
      'others see only public events and posts, without responses',
      () async {
        addTeam({'owner': TeamRole.owner});
        final vm = homeVm();
        await pumpEventQueue();

        expect(vm.isMember, isFalse);
        expect(vm.team, isNull);
        expect(vm.summary?.name, 'Team');
        expect(vm.upcomingEvents.map((e) => e.id), ['e2']);
        expect(vm.upcomingEvents.single.rsvps, isEmpty);
        expect(vm.posts.map((p) => p.id), ['p1']);
        expect(posts.watches, [true]);
      },
    );

    group('Follow button', () {
      TeamHomeViewModel followVm() => TeamHomeViewModel(
        teamId: 't1',
        teamRepository: teams,
        eventRepository: events,
        teamPostRepository: posts,
        authRepository: auth,
        filePicker: picker,
        followRepository: FakeFollowRepository(),
        notificationRepository: FakeNotificationRepository(),
        clock: () => now,
      );

      for (final role in [TeamRole.owner, TeamRole.player]) {
        test('is hidden from the ${role.name}, who sees every post', () async {
          addTeam({
            testUser.uid: role,
            'other': role == TeamRole.owner ? TeamRole.coach : TeamRole.owner,
          });
          final vm = followVm();
          await pumpEventQueue();
          expect(vm.isMember, isTrue);
          expect(vm.follow, isNull);
          vm.dispose();
        });
      }

      test('is offered to people not on the team', () async {
        addTeam({'owner': TeamRole.owner});
        final vm = followVm();
        await pumpEventQueue();
        expect(vm.isMember, isFalse);
        expect(vm.follow?.target.key, 'team_t1');
        vm.dispose();
      });
    });

    test('an unlisted team is not available to others', () async {
      addTeam({'owner': TeamRole.owner}, listed: false);
      final vm = homeVm();
      await pumpEventQueue();
      expect(vm.loaded, isTrue);
      expect(vm.summary, isNull);
    });

    test(
      'admins list a team that has no listing yet; players do not',
      () async {
        addTeam({
          'owner': TeamRole.owner,
          testUser.uid: TeamRole.player,
        }, listed: false);
        homeVm();
        await pumpEventQueue();
        expect(teams.published, isEmpty);

        teams.teams['t1'] = teamWith({testUser.uid: TeamRole.owner});
        homeVm();
        await pumpEventQueue();
        expect(teams.published, ['t1']);
        expect(teams.listings['t1']?.name, 'Team');
      },
    );

    test('a stale listing is republished once', () async {
      addTeam({testUser.uid: TeamRole.coach, 'owner': TeamRole.owner});
      teams.teams['t1'] = teams.teams['t1']!.copyWith(name: 'Renamed');
      homeVm();
      await pumpEventQueue();
      expect(teams.published, ['t1']);
      expect(teams.listings['t1']?.name, 'Renamed');
    });

    test('joining switches to the members view', () async {
      addTeam({'owner': TeamRole.owner});
      final vm = homeVm();
      await pumpEventQueue();
      expect(vm.isMember, isFalse);

      await vm.joinTeam.execute('CODEt1');
      await pumpEventQueue();
      expect(vm.isMember, isTrue);
      expect(vm.posts, hasLength(2));
      expect(posts.watches, [true, false]);
    });

    test('admins post', () async {
      addTeam({testUser.uid: TeamRole.owner});
      final vm = homeVm();
      await pumpEventQueue();
      expect(vm.canPost, isTrue);

      picker.next = [FakeFilePickerService.file('team.png', 10)];
      final picked = await vm.pickImages();
      expect(picked, isA<Ok<List<NewAttachment>>>());
      await vm.savePost.execute(
        PostDraft(
          post: const TeamPost(
            id: '',
            body: 'Jerseys are in',
            location: 'Wash Park',
            links: ['https://example.com/jerseys'],
            isPublic: true,
          ),
          newImages: (picked as Ok<List<NewAttachment>>).value,
        ),
      );
      await pumpEventQueue();
      final post = posts.posts['t1']!.last;
      expect(post.body, 'Jerseys are in');
      expect(post.authorName, testUser.label);
      expect(post.location, 'Wash Park');
      expect(post.links, ['https://example.com/jerseys']);
      expect(post.images.single.name, 'team.png');
      expect(posts.uploaded, ['team.png']);
      expect(vm.posts.first.body, 'Jerseys are in');

      await vm.deletePost.execute(post.id);
      await pumpEventQueue();
      expect(vm.posts.map((p) => p.body), isNot(contains('Jerseys are in')));
    });
  });

  test('photo picking skips files that are too big or not photos', () async {
    addTeam({testUser.uid: TeamRole.owner});
    final vm = homeVm();
    picker.next = [
      FakeFilePickerService.file('ok.jpg', 10),
      FakeFilePickerService.file('notes.pdf', 10),
      FakeFilePickerService.file('huge.png', maxAttachmentBytes + 1),
    ];
    final ok = await vm.pickImages();
    expect((ok as Ok<List<NewAttachment>>).value.map((a) => a.name), [
      'ok.jpg',
    ]);
    picker.next = [
      FakeFilePickerService.file('huge.png', maxAttachmentBytes + 1),
    ];
    expect(await vm.pickImages(), isA<Error<List<NewAttachment>>>());
  });

  test('links are normalized to web addresses', () {
    expect(TeamPost.normalizeLink('example.com/a'), 'https://example.com/a');
    expect(TeamPost.normalizeLink(' http://x.org '), 'http://x.org');
    expect(TeamPost.normalizeLink('ftp://x.org'), isNull);
    expect(TeamPost.normalizeLink('javascript:alert(1)'), isNull);
    expect(TeamPost.normalizeLink('not a link'), isNull);
    expect(TeamPost.normalizeLink('localhost'), isNull);
  });

  group('TeamHomeScreen', () {
    Future<void> pump(WidgetTester tester, TeamHomeViewModel vm) async {
      // Tall enough that the posts below the section links are built.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TeamHomeScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('members get section links, events and posts', (tester) async {
      addTeam({testUser.uid: TeamRole.coach, 'owner': TeamRole.owner});
      await pump(tester, homeVm());

      for (final s in TeamSection.forKind(TeamKind.team)) {
        expect(find.text(s.label), findsOneWidget);
      }
      expect(find.text('Schedule'), findsNothing);
      expect(find.text('Practice'), findsOneWidget);
      expect(find.text('Fees due Friday.'), findsOneWidget);
      expect(find.text('New post'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('others get the public page and can join', (tester) async {
      addTeam({'owner': TeamRole.owner});
      await pump(tester, homeVm());

      expect(find.text('Team Events'), findsNothing);
      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Open tryouts'), findsOneWidget);
      expect(find.text('Practice'), findsNothing);
      expect(find.text('Tryouts Saturday'), findsOneWidget);
      expect(find.text('Fees due Friday.'), findsNothing);
      expect(find.text('New post'), findsNothing);

      await tester.tap(find.text('Open tryouts'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Central Park'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('posts show their place, links and photos', (tester) async {
      addTeam({'owner': TeamRole.owner});
      posts.posts['t1'] = [
        TeamPost(
          id: 'p1',
          body: 'Tryouts',
          location: 'Wash Park',
          links: const ['https://www.example.com/signup/'],
          images: const [
            ChatAttachment(
              path: 'teams/t1/posts/p1/1/0-a.png',
              name: 'a.png',
              contentType: 'image/png',
              size: 10,
            ),
          ],
          isPublic: true,
          createdAt: now,
        ),
      ];
      await pump(tester, homeVm());
      expect(find.text('Wash Park'), findsOneWidget);
      expect(find.text('example.com/signup'), findsOneWidget);
      expect(find.bySemanticsLabel('a.png'), findsOneWidget);
    });

    testWidgets('a team with nothing public says so', (tester) async {
      addTeam({'owner': TeamRole.owner});
      events.events.clear();
      posts.posts.clear();
      await pump(tester, homeVm());
      expect(
        find.text("This team hasn't shared anything publicly yet."),
        findsOneWidget,
      );
    });

    testWidgets('admins write public or members-only posts', (tester) async {
      addTeam({testUser.uid: TeamRole.captain, 'owner': TeamRole.owner});
      posts.posts.clear();
      await pump(tester, homeVm());

      await tester.tap(find.text('New post'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(1), 'Pickup Sunday');
      await tester.enterText(find.byType(TextFormField).at(2), 'Wash Park');
      await tester.enterText(
        find.widgetWithText(TextField, 'Add a link'),
        'example.com/pickup',
      );
      await tester.ensureVisible(find.text('Public'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Public'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();

      expect(find.text('Pickup Sunday'), findsOneWidget);
      final post = posts.posts['t1']!.single;
      expect(post.isPublic, isTrue);
      expect(post.location, 'Wash Park');
      // Typed but not added with +: still saved.
      expect(post.links, ['https://example.com/pickup']);
    });
  });

  group('TeamSearchViewModel', () {
    test('finds listed teams by name or city and marks mine', () async {
      teams.listings['a'] = const TeamListing(
        id: 'a',
        name: 'Ring of Fire',
        division: Division.open,
        level: CompetitionLevel.club,
        city: 'Raleigh',
      );
      teams.listings['b'] = const TeamListing(
        id: 'b',
        name: 'Northside Flyers',
        division: Division.mixed,
        level: CompetitionLevel.league,
      );
      teams.teams['b'] = teamWith({
        'owner': TeamRole.owner,
        testUser.uid: TeamRole.player,
      }, id: 'b');
      final vm = TeamSearchViewModel(
        teamRepository: teams,
        authRepository: auth,
      );
      await pumpEventQueue();

      await vm.search.execute('ral');
      expect(vm.results.map((t) => t.name), ['Ring of Fire']);
      await vm.search.execute('north fly');
      expect(vm.results.single.id, 'b');
      expect(vm.isMine('b'), isTrue);
      expect(vm.isMine('a'), isFalse);
      await vm.search.execute('zzz');
      expect(vm.noMatches, isTrue);
      await vm.search.execute('r');
      expect(vm.results, isEmpty);
      expect(vm.noMatches, isFalse);
    });
  });

  test('old Schedule tab links open Team Events', () {
    expect(TeamSection.fromLegacyTab('schedule'), TeamSection.events);
    expect(TeamSection.fromLegacyTab('playbook'), TeamSection.playbook);
    expect(TeamSection.fromLegacyTab('nope'), isNull);
  });
}
