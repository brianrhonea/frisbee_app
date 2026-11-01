import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/domain/models/follow.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/notification.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/domain/models/workout.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/follow/view_models/follow_viewmodel.dart';
import 'package:frisbee_app/ui/group_tournaments/view_models/group_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/follow/widgets/follow_button.dart';
import 'package:frisbee_app/ui/people/view_models/following_viewmodel.dart';
import 'package:frisbee_app/ui/people/widgets/following_screen.dart';
import 'package:frisbee_app/ui/posts/view_models/post_composer_viewmodel.dart';
import 'package:frisbee_app/ui/posts/widgets/post_composer_screen.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/group_tournament_fakes.dart';
import '../testing/social_fakes.dart';

void main() {
  late FakeFollowRepository follows;
  late FakeNotificationRepository notifications;
  late FakeAuthRepository auth;

  setUp(() {
    follows = FakeFollowRepository();
    notifications = FakeNotificationRepository();
    auth = FakeAuthRepository(user: testUser);
  });

  FollowViewModel followVm(FollowTarget target) => FollowViewModel(
    target: target,
    followRepository: follows,
    notificationRepository: notifications,
    authRepository: auth,
  );

  group('FollowViewModel', () {
    const hawks = FollowTarget.team('t1', 'Hawks');

    test('follows, rings the bell and unfollows', () async {
      final vm = followVm(hawks);
      await pumpEventQueue();
      expect(vm.loaded, isTrue);
      expect(vm.following, isFalse);

      await vm.toggleFollow.execute();
      await pumpEventQueue();
      expect(vm.following, isTrue);
      expect(vm.notifying, isFalse);
      expect(vm.followers, 1);

      await vm.toggleNotify.execute();
      await pumpEventQueue();
      expect(vm.notifying, isTrue);
      // Turning the bell on asks for push permission.
      expect(notifications.status, PushStatus.enabled);
      expect(vm.toggleNotify.result, isA<Ok<PushStatus?>>());

      await vm.toggleFollow.execute();
      await pumpEventQueue();
      expect(vm.following, isFalse);
      expect(follows.follows[testUser.uid], isEmpty);
      expect(vm.followers, 0);
      vm.dispose();
    });

    test("people can't follow themselves", () async {
      final vm = followVm(FollowTarget.user(testUser.uid, 'Alex'));
      expect(vm.isSelf, isTrue);
      vm.dispose();
    });

    testWidgets('the button shows Follow, then Following and a bell', (
      tester,
    ) async {
      final vm = followVm(hawks);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: FollowControl(viewModel: vm, showCount: true)),
        ),
      );
      await tester.pump();
      expect(find.text('Follow'), findsOneWidget);
      expect(find.text('0 followers'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none), findsNothing);

      await tester.tap(find.text('Follow'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Following'), findsOneWidget);
      expect(find.text('1 follower'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.notifications_active), findsOneWidget);
      expect(find.textContaining("We'll let you know"), findsOneWidget);
      vm.dispose();
    });
  });

  group('Following', () {
    testWidgets('lists follows with bells and unfollow', (tester) async {
      await follows.follow(
        testUser.uid,
        const FollowTarget.team('t1', 'Hawks'),
      );
      await follows.follow(
        testUser.uid,
        const FollowTarget.user('u2', 'Sam'),
        notify: true,
      );
      final vm = FollowingViewModel(
        followRepository: follows,
        notificationRepository: notifications,
        authRepository: auth,
      );
      await tester.pumpWidget(
        MaterialApp(home: FollowingScreen(viewModel: vm)),
      );
      await tester.pump();
      // People first.
      expect(
        tester.getTopLeft(find.text('Sam')).dy,
        lessThan(tester.getTopLeft(find.text('Hawks')).dy),
      );
      expect(find.byIcon(Icons.notifications_active), findsOneWidget);

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.notifications_active), findsNWidgets(2));

      await tester.tap(find.text('Unfollow').first);
      await tester.pump();
      await tester.pump();
      expect(find.text('Sam'), findsNothing);
      vm.dispose();
    });
  });

  group('Composer', () {
    late FakeUserPostRepository posts;

    PostComposerViewModel composer({bool workout = false, String? id}) =>
        PostComposerViewModel(
          postId: id,
          startWithWorkout: workout,
          userPostRepository: posts,
          followRepository: follows,
          authRepository: auth,
          filePicker: FakeFilePickerService(),
        );

    setUp(() => posts = FakeUserPostRepository());

    test('rejects empty posts and invalid workouts', () async {
      final vm = composer();
      await vm.save.execute(const UserPostDraft(post: UserPost(id: '')));
      expect(vm.save.result, isA<Error<String>>());
      await vm.save.execute(
        const UserPostDraft(
          post: UserPost(id: '', workout: Workout(durationMinutes: 0)),
        ),
      );
      expect(vm.save.result, isA<Error<String>>());
      expect(posts.posts, isEmpty);
      vm.dispose();
    });

    testWidgets('shares a workout with exercises', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vm = composer(workout: true);
      final router = GoRouter(
        initialLocation: '/compose',
        routes: [
          GoRoute(
            path: '/compose',
            builder: (_, _) => PostComposerScreen(viewModel: vm),
          ),
          GoRoute(
            path: '/posts/:id',
            builder: (_, state) => Text('Opened ${state.pathParameters['id']}'),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      expect(find.text('Share a workout'), findsOneWidget);

      // Minutes are required.
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pump();
      expect(find.text('How long, in minutes'), findsOneWidget);

      await tester.tap(find.text('Gym'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Minutes'),
        '45',
      );
      await tester.tap(find.text('Add exercise'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Exercise 1'),
        'Deadlift',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Sets'), '5');
      await tester.enterText(find.widgetWithText(TextFormField, 'Reps'), '3');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Notes (optional)'),
        'Heavy day',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pump();
      await tester.pump();

      final saved = posts.posts.single;
      expect(saved.body, 'Heavy day');
      expect(saved.workout!.activity, WorkoutActivity.gym);
      expect(saved.workout!.durationMinutes, 45);
      expect(saved.workout!.exercises.single.detail, '5 × 3');
      await tester.pumpAndSettle();
      expect(find.text('Opened ${saved.id}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      vm.dispose();
    });

    test('offers followed tournaments as tags', () async {
      await follows.follow(
        testUser.uid,
        const FollowTarget.event('nats', 'Nationals'),
      );
      await follows.follow(
        testUser.uid,
        const FollowTarget.team('t1', 'Hawks'),
      );
      final vm = composer();
      await pumpEventQueue();
      expect(vm.tournaments.map((t) => t.name), ['Nationals']);
      vm.dispose();
    });
  });

  group('UserProfile', () {
    testWidgets("shows someone's posts, follow button and message", (
      tester,
    ) async {
      final posts = FakeUserPostRepository()
        ..posts.add(
          UserPost(
            id: 'p1',
            authorId: 'u2',
            authorName: 'Sam',
            body: 'Hucks all day',
            createdAt: DateTime(2026, 10, 30),
          ),
        );
      final profiles = FakeProfileRepository()
        ..put(const PlayerProfile(uid: 'u2', name: 'Sam Lee'));
      final vm = PlayerProfileViewModel(
        uid: 'u2',
        profileRepository: profiles,
        authRepository: auth,
        teamRepository: FakeTeamRepository(),
        statsRepository: FakeStatsRepository(),
        directMessageRepository: FakeDirectMessageRepository(),
        userPostRepository: posts,
        followRepository: follows,
        notificationRepository: notifications,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlayerProfileScreen(viewModel: vm),
        ),
      );
      await tester.pump();
      expect(find.text('Sam Lee'), findsWidgets);
      expect(find.text('0 followers · 0 following'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);

      await tester.tap(find.text('Posts'));
      await tester.pump();
      expect(find.text('Hucks all day'), findsOneWidget);

      await tester.tap(find.text('Follow'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Following'), findsOneWidget);
      expect(find.text('1 follower · 0 following'), findsOneWidget);
      expect(tester.takeException(), isNull);
      vm.dispose();
    });

    test('your own profile has no follow button', () async {
      final vm = PlayerProfileViewModel(
        uid: testUser.uid,
        profileRepository: FakeProfileRepository(),
        authRepository: auth,
        teamRepository: FakeTeamRepository(),
        statsRepository: FakeStatsRepository(),
        directMessageRepository: FakeDirectMessageRepository(),
        userPostRepository: FakeUserPostRepository(),
        followRepository: follows,
        notificationRepository: notifications,
      );
      await pumpEventQueue();
      expect(vm.isMe, isTrue);
      expect(vm.follow, isNull);
      expect(vm.social, isTrue);

      vm.dispose();
    });
  });

  group('Group tournaments', () {
    test('can be followed, by group and tournament id', () async {
      final repo = FakeGroupTournamentRepository()
        ..tournaments['g1'] = [
          GroupTournament(
            id: 'x1',
            name: 'Fall Hat',
            settings: TournamentSettings(startsAt: DateTime(2026, 11, 8)),
          ),
        ];
      final vm = GroupTournamentViewModel(
        groupId: 'g1',
        tournamentId: 'x1',
        teamRepository: FakeTeamRepository(),
        tournamentRepository: repo,
        authRepository: auth,
        followRepository: follows,
        notificationRepository: notifications,
      );
      await pumpEventQueue();
      expect(vm.listing?.name, 'Fall Hat');
      final follow = vm.follow!;
      expect(follow.target.key, 'tournament_g1_x1');
      await follow.toggleFollow.execute();
      await pumpEventQueue();
      expect(
        follows.follows[testUser.uid]!['tournament_g1_x1']!.target.groupId,
        'g1',
      );
      vm.dispose();
    });

    test('has no follow button without the repositories', () async {
      final vm = GroupTournamentViewModel(
        groupId: 'g1',
        tournamentId: 'x1',
        teamRepository: FakeTeamRepository(),
        tournamentRepository: FakeGroupTournamentRepository(),
        authRepository: auth,
      );
      await pumpEventQueue();
      expect(vm.follow, isNull);
      vm.dispose();
    });
  });
}
