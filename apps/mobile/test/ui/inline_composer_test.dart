import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/domain/models/post_prompts.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/data/services/image_compressor.dart';
import 'package:frisbee_app/domain/models/follow.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/domain/models/workout.dart';
import 'package:frisbee_app/domain/models/workout_route.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/posts/view_models/inline_composer_viewmodel.dart';
import 'package:frisbee_app/ui/posts/widgets/inline_composer.dart';
import 'package:frisbee_app/ui/workouts/widgets/workout_fields.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

void main() {
  late FakeUserPostRepository userPosts;
  late FakeTeamPostRepository teamPosts;
  late FakeFollowRepository follows;
  late FakeFilePickerService picker;
  late List<Team> teams;

  final flyers = teamWith({testUser.uid: TeamRole.owner}, id: 'fly');
  final pickup = Team(
    id: 'grp',
    name: 'Lake Pickup',
    kind: TeamKind.community,
    requiresApproval: true,
    division: Division.mixed,
    level: CompetitionLevel.pickup,
    ownerId: testUser.uid,
    members: {testUser.uid: TeamRole.owner},
  );

  setUp(() {
    userPosts = FakeUserPostRepository();
    teamPosts = FakeTeamPostRepository();
    follows = FakeFollowRepository();
    picker = FakeFilePickerService();
    teams = [];
  });

  InlineComposerViewModel build() {
    final vm = InlineComposerViewModel(
      authRepository: FakeAuthRepository(user: testUser),
      userPostRepository: userPosts,
      teamPostRepository: teamPosts,
      followRepository: follows,
      filePicker: picker,
      audiences: () => teams,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  group('InlineComposerViewModel', () {
    test('posts words to Everyone, then clears', () async {
      final vm = build();
      expect(vm.canPost, isFalse, reason: 'nothing to post yet');
      vm.setBody('Great layout D today');
      expect(vm.canPost, isTrue);

      await vm.post.execute();
      expect(vm.post.result, isA<Ok<PostedTo>>());
      expect(userPosts.posts.single.body, 'Great layout D today');
      expect(vm.body, isEmpty);
      expect(vm.canPost, isFalse);
    });

    test('no link tool: a pasted link is part of the words', () async {
      final vm = build()..setBody('Highlights https://youtu.be/x');
      await vm.post.execute();
      final post = userPosts.posts.single;
      expect(post.body, 'Highlights https://youtu.be/x');
      expect(post.links, isEmpty);
    });

    test('photos: picked into the box, up to the limit, then posted', () async {
      final vm = build();
      picker.next = [
        for (var i = 0; i < 5; i++) FakeFilePickerService.file('p$i.png', 10),
      ];
      await vm.addPhotos();
      expect(vm.photos, hasLength(UserPost.maxImages));
      expect(vm.notice, contains('up to ${UserPost.maxImages} photos'));
      expect(vm.canAddPhotos, isFalse);
      expect(vm.canPost, isTrue, reason: 'a photo is enough');

      vm.removePhoto(vm.photos.first);
      expect(vm.photos, hasLength(3));
      await vm.post.execute();
      expect(userPosts.uploaded, ['p1.png', 'p2.png', 'p3.png']);
      expect(vm.photos, isEmpty);
    });

    test('a workout is checked, converted and posted', () async {
      final vm = build()..unit = DistanceUnit.mi;
      vm.toggleWorkout();
      expect(vm.canPost, isTrue, reason: 'a workout may have no words');
      await vm.post.execute();
      expect(errorText(vm), 'How long, in minutes');

      vm
        ..setActivity(WorkoutActivity.gym)
        ..setMinutes('45')
        ..setDistance('2')
        ..setEffort(7)
        ..addExercise();
      vm.updateExercise(vm.workout!.exercises.single, sets: '3');
      expect(vm.post.error, isFalse, reason: 'a change clears the error');
      await vm.post.execute();
      expect(errorText(vm), 'Name each exercise');

      vm.updateExercise(vm.workout!.exercises.single, name: 'Squat');
      await vm.post.execute();
      final w = userPosts.posts.single.workout!;
      expect(w.activity, WorkoutActivity.gym);
      expect(w.durationMinutes, 45);
      expect(w.distanceKm, closeTo(3.22, 0.01));
      expect(w.effort, 7);
      expect(w.exercises.single.name, 'Squat');
      expect(w.exercises.single.sets, 3);
      expect(vm.workout, isNull, reason: 'cleared after posting');
    });

    test('tags a followed tournament', () async {
      await follows.follow(
        testUser.uid,
        const FollowTarget.tournament('h', 'lone', 'Lone Star'),
      );
      final vm = build();
      await pumpEventQueue();
      expect(vm.tournaments.single.name, 'Lone Star');
      vm
        ..setTag(vm.tournaments.single.key)
        ..setBody('At the fields');
      await vm.post.execute();
      expect(userPosts.posts.single.tournamentName, 'Lone Star');
    });

    test('with the API, only tournaments within a week are offered', () async {
      await follows.follow(
        testUser.uid,
        const FollowTarget.tournament('h', 'lone', 'Lone Star'),
      );
      await follows.follow(
        testUser.uid,
        const FollowTarget.tournament('h', 'far', 'Far Away Open'),
      );
      // The API's answer: just the one starting this week.
      userPosts.tagAnswer = [
        const FollowTarget.tournament('h', 'lone', 'Lone Star'),
      ];
      final vm = build();
      await pumpEventQueue();
      expect(vm.tournaments.map((t) => t.name), ['Lone Star']);
      userPosts.tagAnswer = [];
      await follows.follow(
        testUser.uid,
        const FollowTarget.tournament('h', 'new', 'New One'),
      );
      await pumpEventQueue();
      expect(vm.tournaments, isEmpty, reason: 'asked again on a new follow');
    });

    test('a team post: title, place, Public; no workout or tag', () async {
      teams = [flyers];
      await follows.follow(
        testUser.uid,
        const FollowTarget.tournament('h', 'lone', 'Lone Star'),
      );
      final vm = build();
      await pumpEventQueue();
      vm
        ..toggleWorkout()
        ..setTag(vm.tournaments.single.key);
      expect(vm.audiences, [flyers]);

      vm.pickAudience(flyers);
      expect(vm.team, flyers);
      expect(vm.workout, isNull, reason: 'team posts have no workout');
      expect(vm.tagKey, isNull);
      expect(vm.offersWorkout, isFalse);
      expect(vm.tournaments, isEmpty);
      expect(vm.offersPublic, isTrue);

      vm
        ..setTitle('Tryouts')
        ..setBody('Saturday 10am')
        ..setPlace('Zilker')
        ..setPublic(true);
      await vm.post.execute();
      expect((vm.post.result as Ok<PostedTo>).value.teamName, 'Team');
      final saved = teamPosts.posts['fly']!.single;
      expect(saved.title, 'Tryouts');
      expect(saved.location, 'Zilker');
      expect(saved.isPublic, isTrue);
      expect(userPosts.posts, isEmpty);
      // The audience stays; the fields clear.
      expect(vm.team, flyers);
      expect(vm.title, isEmpty);
      expect(vm.isPublic, isFalse);
    });

    test("a private group's posts are never Public", () async {
      teams = [pickup];
      final vm = build()..pickAudience(pickup);
      expect(vm.offersPublic, isFalse);
      vm
        ..setPublic(true)
        ..setBody('Pickup moved to 6');
      await vm.post.execute();
      expect(teamPosts.posts['grp']!.single.isPublic, isFalse);
    });

    test('back to Everyone, and a team no longer managed falls back', () {
      teams = [flyers];
      final vm = build()..pickAudience(flyers);
      vm.pickAudience(null);
      expect(vm.team, isNull);
      expect(vm.offersWorkout, isTrue);
      vm.pickAudience(flyers);
      teams = [];
      expect(vm.team, isNull);
    });

    test('a team that left the list is never posted to Everyone', () async {
      teams = [flyers];
      final vm = build()
        ..pickAudience(flyers)
        ..setBody('Members only: practice moved');
      teams = [];
      await vm.post.execute();
      expect(vm.post.error, isTrue);
      expect(
        vm.post.result.toString(),
        contains('You can no longer post on that team'),
      );
      expect(userPosts.posts, isEmpty);
      expect(teamPosts.posts, isEmpty);
    });

    test('too long a post cannot be sent', () {
      final vm = build()..setBody('x' * (UserPost.maxBody + 1));
      expect(vm.charactersLeft, -1);
      expect(vm.canPost, isFalse);
    });
  });

  group('InlineComposer', () {
    Future<InlineComposerViewModel> pump(
      WidgetTester tester, {
      double width = 390,
    }) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vm = build();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [InlineComposer(viewModel: vm, name: 'Alex')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return vm;
    }

    Finder postButton() => find.widgetWithText(FilledButton, 'Send');
    bool postEnabled(WidgetTester tester) =>
        tester.widget<FilledButton>(postButton()).onPressed != null;

    testWidgets('header: who is posting, to whom; the avatar opens the '
        'profile; the hint is a prompt', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vm = build();
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => Scaffold(
              body: ListView(
                children: [InlineComposer(viewModel: vm, name: 'Alex')],
              ),
            ),
          ),
          GoRoute(
            path: Routes.profile,
            builder: (_, _) => const Text('My profile'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Posting to '), findsOneWidget);
      expect(find.text('Everyone'), findsOneWidget);
      final hint = tester
          .widget<TextField>(find.byType(TextField).first)
          .decoration!
          .hintText;
      expect(postPrompts, contains(hint));
      await tester.tap(find.byKey(const Key('composer-avatar')));
      await tester.pumpAndSettle();
      expect(find.text('My profile'), findsOneWidget);
    });

    testWidgets('typing enables Post; posting clears the box', (tester) async {
      final vm = await pump(tester);
      expect(postEnabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), 'Hucks all day');
      await tester.pump();
      expect(postEnabled(tester), isTrue);

      await tester.tap(postButton());
      await tester.pumpAndSettle();
      expect(userPosts.posts.single.body, 'Hucks all day');
      expect(find.text('Hucks all day'), findsNothing);
      expect(find.text('Posted'), findsOneWidget);
      expect(vm.body, isEmpty);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('Photo and Workout open inside the box, no popup', (
      tester,
    ) async {
      await pump(tester);
      // Photos upload as picked (shrinking runs on another isolate).
      picker
        ..compressor = const ImageCompressor(enabled: false)
        ..next = [FakeFilePickerService.file('field.png', 10)];
      // No camera here: Photos goes straight to the library.
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove photo'), findsOneWidget);
      expect(postEnabled(tester), isTrue);

      // No Link tool: pasted links in the words show as links.
      expect(find.text('Link'), findsNothing);

      await tester.tap(find.text('Workout'));
      await tester.pumpAndSettle();
      expect(find.text('Minutes'), findsOneWidget);
      expect(find.text('How did it go? (optional)'), findsOneWidget);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Photos + asks Take photo or Upload photos', (tester) async {
      picker
        ..canUseCamera = true
        ..compressor = const ImageCompressor(enabled: false)
        ..nextPhoto = FakeFilePickerService.file('snap.png', 10)
        ..next = [
          for (var i = 0; i < 5; i++) FakeFilePickerService.file('p$i.png', 10),
        ];
      await pump(tester);
      expect(find.byTooltip('Take photo'), findsNothing);

      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Upload photos'), findsOneWidget);
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove photo'), findsOneWidget);

      // Up to 4 in all: the extra picks are left out.
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload photos'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove photo'), findsNWidgets(4));
      expect(find.text('Posts can have up to 4 photos.'), findsOneWidget);
    });

    testWidgets('To picks a team: its fields show, Workout goes', (
      tester,
    ) async {
      teams = [flyers, pickup];
      final vm = await pump(tester);
      expect(find.text('Everyone'), findsOneWidget);
      expect(find.text('Workout'), findsOneWidget);

      await tester.tap(find.text('Everyone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Team').last);
      await tester.pumpAndSettle();
      expect(vm.team, flyers);
      expect(find.text('Title (optional)'), findsOneWidget);
      expect(find.text('Where (optional)'), findsOneWidget);
      expect(find.text("What's the news for Team?"), findsOneWidget);
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Workout'), findsNothing);

      // A private group: no Public.
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lake Pickup').last);
      await tester.pumpAndSettle();
      expect(find.text('Public'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a narrow phone with every tool', (tester) async {
      teams = [flyers];
      picker.canUseCamera = true;
      final vm = await pump(tester, width: 320);
      vm.pickAudience(flyers);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      vm.pickAudience(null);
      vm.toggleWorkout();
      vm.addExercise();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets("a workout's fields have room on a phone", (tester) async {
      final vm = await pump(tester);
      vm
        ..toggleWorkout()
        ..addExercise();
      await tester.pumpAndSettle();
      // Every box says what it's for, above it, even once typed in.
      final sets = tester.getSize(
        find.descendant(
          of: find.widgetWithText(WorkoutField, 'Sets'),
          matching: find.byType(TextField),
        ),
      );
      expect(sets.width, greaterThan(56));
      for (final label in [
        'Minutes',
        'Distance (optional)',
        'Reps',
        'Weight',
      ]) {
        expect(find.widgetWithText(WorkoutField, label), findsOneWidget);
      }
      expect(find.text('Exercise 1'), findsOneWidget);
      expect(find.text(ExerciseHints.name), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Post stays above the keyboard while typing', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vm = build();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 700),
                InlineComposer(viewModel: vm, name: 'Alex'),
                const SizedBox(height: 400),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.showKeyboard(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(find.byType(TextField), 'Line one');
      await tester.pumpAndSettle();
      final post = tester.getRect(find.widgetWithText(FilledButton, 'Send'));
      expect(post.bottom, lessThanOrEqualTo(844 - 300));
      expect(post.top, greaterThanOrEqualTo(0));
    });

    testWidgets('the draft outlasts the box being rebuilt', (tester) async {
      final vm = await pump(tester);
      await tester.enterText(find.byType(TextField), 'Half-written');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineComposer(viewModel: vm, name: 'Alex'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Half-written'), findsOneWidget);
      expect(postEnabled(tester), isTrue);
    });
  });
}

String errorText(InlineComposerViewModel vm) => switch (vm.post.result) {
  Error(:final error) => error.toString().replaceFirst('Exception: ', ''),
  _ => '',
};
