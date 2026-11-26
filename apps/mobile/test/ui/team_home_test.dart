import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/view_models/team_home_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_search_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_section_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';
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
    expect(TeamPost.normalizeLink('Https://X.org/Path'), 'https://X.org/Path');
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

    testWidgets("on a phone, tabs stay on the page and fold the header", (
      tester,
    ) async {
      addTeam({testUser.uid: TeamRole.coach, 'owner': TeamRole.owner});
      // A phone; wide enough for the test font's square letters.
      tester.view.physicalSize = const Size(560, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vm = homeVm();
      addTearDown(vm.dispose);
      final router = GoRouter(
        initialLocation: '/teams/t1',
        routes: [
          GoRoute(
            path: '/teams/:teamId',
            builder: (_, state) => TeamHomeScreen(
              viewModel: vm,
              section: TeamSection.fromPath(
                state.uri.queryParameters['section'],
              ),
              more: state.uri.queryParameters['section'] == TeamTab.morePath,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<NestedScrollView>(find.byType(NestedScrollView))
          .controller!;
      expect(scroll.offset, 0);
      expect(find.text('Fees due Friday.'), findsOneWidget);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      // Same page: the header folded up, the tabs and the list below it.
      expect(find.byType(TeamHomeScreen), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.matches, hasLength(1));
      expect(scroll.offset, greaterThan(0));
      expect(scroll.offset, scroll.position.maxScrollExtent);
      // Nothing below is tucked under the folded header.
      expect(find.text('Playbook').hitTestable(), findsOneWidget);
      expect(find.text('Feed'), findsOneWidget);

      await tester.tap(find.text('Feed'));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(find.text('Fees due Friday.'), findsOneWidget);

      // Scrolling the feed folds it too.
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(scroll.offset, scroll.position.maxScrollExtent);
    });

    group('tournament invites', () {
      late FakeHostedTournamentRepository hosted;
      setUp(() {
        hosted = FakeHostedTournamentRepository()
          ..invites['t1'] = [
            TeamTournamentInvite(
              tournamentId: 'spring',
              name: 'Spring Fling',
              hostName: 'Denver Ultimate',
              startsOn: now.add(const Duration(days: 30)),
              divisionLabel: 'Club Mixed',
              replyBy: now.add(const Duration(days: 16)),
            ),
            TeamTournamentInvite(
              tournamentId: 'late',
              name: 'Late Bloomer',
              startsOn: now.add(const Duration(days: 10)),
              replyBy: now.subtract(const Duration(days: 1)),
              expired: true,
            ),
          ];
      });
      TeamHomeViewModel invitesVm() => TeamHomeViewModel(
        teamId: 't1',
        teamRepository: teams,
        eventRepository: events,
        teamPostRepository: posts,
        authRepository: auth,
        filePicker: picker,
        tournamentRepository: hosted,
        clock: () => now,
      );

      testWidgets('admins get one Respond button that opens the respond flow', (
        tester,
      ) async {
        addTeam({testUser.uid: TeamRole.owner});
        final vm = invitesVm();
        final opened = <String>[];
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => TeamHomeScreen(viewModel: vm),
                ),
                GoRoute(
                  path: '/tournaments/:id/respond',
                  builder: (_, state) {
                    opened.add(state.uri.toString());
                    return const Text('respond');
                  },
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('tournament-invites')),
          findsOneWidget,
        );
        expect(find.text('Tournament invites · 2'), findsOneWidget);
        expect(find.text('Spring Fling'), findsOneWidget);
        expect(find.textContaining('Reply by'), findsOneWidget);
        // One button: Accept or Decline come first in the flow.
        expect(
          find.byKey(const ValueKey('respond-invite-spring')),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, 'Decline'), findsNothing);
        // An expired one says so, with nothing to press.
        expect(find.textContaining('Expired.'), findsOneWidget);
        expect(find.byKey(const ValueKey('respond-invite-late')), findsNothing);

        await tester.ensureVisible(
          find.byKey(const ValueKey('respond-invite-spring')),
        );
        await tester.tap(find.byKey(const ValueKey('respond-invite-spring')));
        await tester.pumpAndSettle();
        expect(opened, ['/tournaments/spring/respond?team=t1']);
      });

      testWidgets('accepted entries missing a roster or fee get Finish entry', (
        tester,
      ) async {
        addTeam({testUser.uid: TeamRole.owner});
        hosted.invites['t1'] = [];
        hosted.toFinish['t1'] = [
          TeamEntryToFinish(
            tournamentId: 'fall',
            name: 'Fall Classic',
            startsOn: now.add(const Duration(days: 20)),
            status: EntryStatus.accepted,
            rosterSet: true,
            deadline: now.add(const Duration(days: 5)),
          ),
        ];
        await pump(tester, invitesVm());
        expect(find.byKey(const ValueKey('entries-to-finish')), findsOneWidget);
        expect(find.text('Entry to finish'), findsOneWidget);
        expect(find.text('Fall Classic'), findsOneWidget);
        expect(find.textContaining('Fee due'), findsOneWidget);
        expect(find.byKey(const ValueKey('finish-entry-fall')), findsOneWidget);
      });

      testWidgets("players don't see them", (tester) async {
        addTeam({testUser.uid: TeamRole.player, 'owner': TeamRole.owner});
        await pump(tester, invitesVm());
        expect(find.byKey(const ValueKey('tournament-invites')), findsNothing);
      });
    });

    testWidgets('members get section links, events and posts', (tester) async {
      addTeam({testUser.uid: TeamRole.coach, 'owner': TeamRole.owner});
      await pump(tester, homeVm());

      // Five tabs (Teams is a community's); the other sections are under
      // More.
      final tabs = TeamTab.forSections(TeamSection.forKind(TeamKind.team));
      expect(tabs, [
        TeamTab.feed,
        TeamTab.schedule,
        TeamTab.chat,
        TeamTab.roster,
        TeamTab.more,
      ]);
      for (final t in tabs) {
        expect(find.text(t.label), findsOneWidget);
      }
      expect(find.text('Teams'), findsNothing);
      expect(find.text('Playbook'), findsNothing);
      expect(find.text('Members'), findsNothing);
      // The up-next card and the going tile.
      expect(find.text('Practice'), findsNWidgets(2));
      expect(find.text('Fees due Friday.'), findsOneWidget);
      expect(find.text('Post to the team…'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('owners empty or hand on the team before deleting it', (
      tester,
    ) async {
      addTeam({testUser.uid: TeamRole.owner, 'p1': TeamRole.player});
      final vm = homeVm();
      await pump(tester, vm);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete team'));
      await tester.pumpAndSettle();
      expect(find.text("Can't delete Team yet"), findsOneWidget);
      expect(find.textContaining('1 other member.'), findsOneWidget);
      expect(find.text('Go to Members'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(teams.teams, contains('t1'), reason: 'not deleted');

      // The view model refuses too, whatever the screen does.
      await vm.deleteTeam.execute('Team');
      await tester.pump();
      expect(
        find.textContaining('transfer ownership first'),
        findsOneWidget,
        reason: 'the screen shows the refusal',
      );
      expect(teams.teams, contains('t1'));
    });

    testWidgets('a sole owner is asked to confirm, then deletes', (
      tester,
    ) async {
      addTeam({testUser.uid: TeamRole.owner});
      await pump(tester, homeVm());

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete team'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Team?'), findsOneWidget);
      expect(find.textContaining("Can't delete"), findsNothing);

      // As on the website, the name has to be typed first.
      FilledButton deleteButton() =>
          tester.widget(find.widgetWithText(FilledButton, 'Delete'));
      expect(deleteButton().onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Tea');
      await tester.pump();
      expect(deleteButton().onPressed, isNull);
      await tester.enterText(find.byType(TextField), ' team ');
      await tester.pump();
      expect(deleteButton().onPressed, isNotNull, reason: 'any case');

      // While it deletes, a dialog nobody can dismiss shows how far it is.
      teams.deleteGate = Completer<void>();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Deleting Team'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('Deleting step 0'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(find.text('Deleting Team'), findsOneWidget, reason: 'stays up');
      expect(teams.teams, contains('t1'), reason: 'still going');
      expect(teams.deletedWithName, 'team');
    });

    testWidgets("the API's refusal is shown and the team stays", (
      tester,
    ) async {
      addTeam({testUser.uid: TeamRole.owner});
      teams.deleteError = const ApiException(
        'failed_precondition',
        "It plays in a league that hasn't finished, so it can't be deleted "
            'yet.',
      );
      await pump(tester, homeVm());

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete team'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Team');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.textContaining("league that hasn't finished"),
        findsOneWidget,
      );
      expect(find.text('Deleting Team'), findsNothing);
      expect(teams.teams, contains('t1'));
    });

    test('the view model refuses a name that does not match', () async {
      addTeam({testUser.uid: TeamRole.owner});
      final vm = homeVm();
      await pumpEventQueue();
      await vm.deleteTeam.execute('Other');
      expect(vm.deleteTeam.error, isTrue);
      expect(teams.deletedWithName, isNull);
      expect(teams.teams, contains('t1'));
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
      expect(find.text('Post to the team…'), findsNothing);

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

    testWidgets("a youth team's roster is private to outsiders", (
      tester,
    ) async {
      final youth = Team(
        id: 't1',
        name: 'Juniors',
        division: Division.mixed,
        level: CompetitionLevel.youth,
        ownerId: 'owner',
        members: const {'owner': TeamRole.owner},
      );
      teams.teams[youth.id] = youth;
      teams.listings[youth.id] = TeamListing.of(youth);
      final vm = homeVm();
      await pump(tester, vm);
      expect(vm.youthRosterPrivate, isTrue);
      expect(
        find.text('Rosters of youth teams are private: only members see them.'),
        findsOneWidget,
      );
    });

    testWidgets("members and adult teams' outsiders see no youth note", (
      tester,
    ) async {
      addTeam({'owner': TeamRole.owner});
      final outsider = homeVm();
      await pump(tester, outsider);
      expect(outsider.youthRosterPrivate, isFalse);
      expect(find.text(YouthRosterNote.text), findsNothing);
    });

    testWidgets('a team says outsiders need an invite code', (tester) async {
      addTeam({'owner': TeamRole.owner});
      await pump(tester, homeVm());
      expect(find.textContaining('invite code to join'), findsOneWidget);
    });

    testWidgets("Invite counts a group's join requests", (tester) async {
      final group = Team(
        id: 't1',
        name: 'Friends',
        division: Division.mixed,
        level: CompetitionLevel.pickup,
        ownerId: testUser.uid,
        members: {testUser.uid: TeamRole.owner},
        kind: TeamKind.community,
        requiresApproval: true,
      );
      teams.teams['t1'] = group;
      teams.listings['t1'] = TeamListing.of(group);
      teams.joinRequests['t1'] = [
        const GroupJoinRequest(uid: 'ann', name: 'Ann'),
        const GroupJoinRequest(uid: 'bo', name: 'Bo'),
      ];
      await pump(tester, homeVm());
      expect(find.text('Invite members'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('2')),
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

      await tester.tap(find.text('Post to the team…'));
      await tester.pumpAndSettle();
      expect(find.text('New post'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), 'Pickup Sunday');
      await tester.enterText(find.byType(TextFormField).at(2), 'Wash Park');
      // No link field: links go in the words.
      expect(find.widgetWithText(TextField, 'Add a link'), findsNothing);
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
      expect(post.links, isEmpty);
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

  group('Tournaments tab', () {
    final teamSections = TeamSection.forKind(TeamKind.team);

    test('stays under More unless promoted', () {
      expect(TeamTab.of(TeamSection.tournaments), TeamTab.more);
      expect(TeamTab.forSections(teamSections), [
        TeamTab.feed,
        TeamTab.schedule,
        TeamTab.chat,
        TeamTab.roster,
        TeamTab.more,
      ]);
      expect(TeamTab.moreSections(teamSections), [
        TeamSection.playbook,
        TeamSection.videos,
        TeamSection.stats,
        TeamSection.tournaments,
      ]);
    });

    test('promoted, it follows Chat and leaves More', () {
      expect(
        TeamTab.of(TeamSection.tournaments, promoted: true),
        TeamTab.tournaments,
      );
      expect(
        TeamTab.of(TeamSection.stats, promoted: true),
        TeamTab.more,
        reason: 'only Tournaments moves',
      );
      expect(TeamTab.forSections(teamSections, tournamentsTab: true), [
        TeamTab.feed,
        TeamTab.schedule,
        TeamTab.chat,
        TeamTab.tournaments,
        TeamTab.roster,
        TeamTab.more,
      ]);
      expect(TeamTab.moreSections(teamSections, tournamentsTab: true), [
        TeamSection.playbook,
        TeamSection.videos,
        TeamSection.stats,
      ]);
      expect(TeamTab.tournaments.route('t1'), Routes.teamTournaments('t1'));
    });

    test('a page without a Tournaments section gets no tab', () {
      final league = TeamSection.forKind(TeamKind.team, league: true);
      expect(TeamTab.forSections(league, tournamentsTab: true), [
        TeamTab.feed,
        TeamTab.chat,
        TeamTab.roster,
      ]);
    });

    late FakeHostedTournamentRepository hosted;
    setUp(() => hosted = FakeHostedTournamentRepository());

    EnteredTournament entry(EntryStatus status, DateTime startsOn) =>
        EnteredTournament(
          tournamentId: 'x1',
          name: 'Fall Brawl',
          status: status,
          startsOn: startsOn,
          endsOn: startsOn.add(const Duration(days: 1)),
        );

    TeamHomeViewModel tournamentVm() => TeamHomeViewModel(
      teamId: 't1',
      teamRepository: teams,
      eventRepository: events,
      teamPostRepository: posts,
      authRepository: auth,
      filePicker: picker,
      tournamentRepository: hosted,
      clock: () => now,
    );

    final nextWeek = DateTime(2026, 11, 6);

    test('members of a team with an entry ahead get the tab', () async {
      addTeam({testUser.uid: TeamRole.player, 'owner': TeamRole.owner});
      hosted.entered['t1'] = [entry(EntryStatus.accepted, nextWeek)];
      final vm = tournamentVm();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.tournamentsTab, isTrue);
    });

    test('declined or past entries, and outsiders, do not', () async {
      addTeam({testUser.uid: TeamRole.player, 'owner': TeamRole.owner});
      hosted.entered['t1'] = [
        entry(EntryStatus.declined, nextWeek),
        entry(EntryStatus.accepted, DateTime(2026, 10, 1)),
      ];
      final vm = tournamentVm();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.tournamentsTab, isFalse);

      addTeam({'owner': TeamRole.owner});
      hosted.entered['t1'] = [entry(EntryStatus.accepted, nextWeek)];
      final outsider = tournamentVm();
      addTearDown(outsider.dispose);
      await pumpEventQueue();
      expect(outsider.isMember, isFalse);
      expect(outsider.tournamentsTab, isFalse);
    });

    Future<void> pumpPhone(WidgetTester tester, TeamHomeViewModel vm) async {
      tester.view.physicalSize = const Size(560, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/teams/t1',
        routes: [
          GoRoute(
            path: '/teams/:teamId',
            builder: (_, state) => TeamHomeScreen(
              viewModel: vm,
              section: TeamSection.fromPath(
                state.uri.queryParameters['section'],
              ),
              more: state.uri.queryParameters['section'] == TeamTab.morePath,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a team with a tournament next week shows it as a tab', (
      tester,
    ) async {
      addTeam({testUser.uid: TeamRole.player, 'owner': TeamRole.owner});
      hosted.entered['t1'] = [entry(EntryStatus.accepted, nextWeek)];
      final vm = tournamentVm();
      addTearDown(vm.dispose);
      await pumpPhone(tester, vm);

      final tabLabels = [
        for (final t in [
          TeamTab.feed,
          TeamTab.schedule,
          TeamTab.chat,
          TeamTab.tournaments,
          TeamTab.roster,
          TeamTab.more,
        ])
          tester.getTopLeft(find.text(t.label)).dx,
      ];
      expect(tabLabels, orderedEquals([...tabLabels]..sort()));

      // The test font's wide letters push More past the edge of the row.
      await tester.ensureVisible(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Playbook'), findsOneWidget);
      // Just the tab: More doesn't list it.
      expect(find.text('Tournaments'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Tournaments'), findsNothing);
    });

    testWidgets('without one, Tournaments stays under More', (tester) async {
      addTeam({testUser.uid: TeamRole.player, 'owner': TeamRole.owner});
      hosted.entered['t1'] = [
        entry(EntryStatus.declined, nextWeek),
        entry(EntryStatus.accepted, DateTime(2026, 10, 1)),
      ];
      final vm = tournamentVm();
      addTearDown(vm.dispose);
      await pumpPhone(tester, vm);
      expect(find.text('Tournaments'), findsNothing);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Tournaments'), findsOneWidget);
    });
  });
}
