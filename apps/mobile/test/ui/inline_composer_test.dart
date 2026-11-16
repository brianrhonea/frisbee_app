import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/image_compressor.dart';
import 'package:frisbee_app/domain/models/follow.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/domain/models/workout.dart';
import 'package:frisbee_app/domain/models/workout_route.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/posts/view_models/inline_composer_viewmodel.dart';
import 'package:frisbee_app/ui/posts/widgets/inline_composer.dart';
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

    test('links alone are not a post; a typed link is added on post', () async {
      final vm = build();
      vm
        ..openLink()
        ..setLinkText('example.com/clip');
      expect(vm.canPost, isFalse);
      expect(vm.addLink(), isTrue);
      expect(vm.links, ['https://example.com/clip']);
      expect(vm.linkOpen, isFalse);

      vm
        ..openLink()
        ..setLinkText('not a link')
        ..setBody('See this');
      await vm.post.execute();
      expect(vm.post.error, isTrue);
      expect(vm.linkError, isNotNull);
      expect(userPosts.posts, isEmpty);

      vm.setLinkText('youtu.be/x');
      await vm.post.execute();
      expect(userPosts.posts.single.links, [
        'https://example.com/clip',
        'https://youtu.be/x',
      ]);
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

    Finder postButton() => find.widgetWithText(FilledButton, 'Post');
    bool postEnabled(WidgetTester tester) =>
        tester.widget<FilledButton>(postButton()).onPressed != null;

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

    testWidgets('Photo, Link and Workout open inside the box, no popup', (
      tester,
    ) async {
      await pump(tester);
      // Photos upload as picked (shrinking runs on another isolate).
      picker
        ..compressor = const ImageCompressor(enabled: false)
        ..next = [FakeFilePickerService.file('field.png', 10)];
      await tester.tap(find.text('Photo'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove photo'), findsOneWidget);
      expect(postEnabled(tester), isTrue);

      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      expect(find.text('example.com/highlights'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'example.com/highlights'),
        'example.com/clip',
      );
      await tester.tap(find.byTooltip('Add link'));
      await tester.pumpAndSettle();
      expect(find.text('example.com/clip'), findsOneWidget);

      await tester.tap(find.text('Workout'));
      await tester.pumpAndSettle();
      expect(find.text('Minutes'), findsOneWidget);
      expect(find.text('How did it go? (optional)'), findsOneWidget);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
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
