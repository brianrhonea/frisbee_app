import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/follow/follow_repository.dart';
import 'package:frisbee_app/data/repositories/user_post/user_post_repository.dart';
import 'package:frisbee_app/data/repositories/workout_recorder/workout_recorder.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';
import 'package:frisbee_app/data/services/location_service.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/domain/models/workout.dart';
import 'package:frisbee_app/domain/models/workout_route.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/view_model_host.dart';
import 'package:frisbee_app/ui/groups/widgets/group_map.dart';
import 'package:frisbee_app/ui/posts/widgets/post_composer.dart';
import 'package:frisbee_app/ui/posts/widgets/post_widgets.dart';
import 'package:frisbee_app/ui/workouts/view_models/record_workout_viewmodel.dart';
import 'package:frisbee_app/ui/workouts/widgets/record_workout_screen.dart';
import 'package:frisbee_app/ui/workouts/widgets/route_widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/workout_recorder_test.dart' show FakeLocationService;
import '../domain/workout_route_test.dart' show straightTrack;
import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

/// A 2 km run at 5:00 /km.
Workout recordedRun() => Workout.recorded(
  activity: WorkoutActivity.run,
  moving: const Duration(minutes: 10),
  meters: 2000,
  route: WorkoutRoute(
    path: [for (final t in straightTrack(21)) t.point],
    splitsMi: const [483],
    splitsKm: const [300, 300],
    elevationGainMeters: 15,
  ),
);

void main() {
  setUp(() => debugDisableMapTiles = true);
  tearDown(() => debugDisableMapTiles = false);

  late FakeUserPostRepository posts;
  late FakeAuthRepository auth;

  setUp(() {
    posts = FakeUserPostRepository();
    auth = FakeAuthRepository(user: testUser);
  });

  List<Provider<Object?>> base() => [
    Provider<UserPostRepository>.value(value: posts),
    Provider<FollowRepository>.value(value: FakeFollowRepository()),
    Provider<FilePickerService>.value(value: FakeFilePickerService()),
  ];

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('a post shows the route, stats in miles and the splits', (
    tester,
  ) async {
    bigScreen(tester);
    final w = recordedRun();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            children: [
              UserPostCard(
                post: UserPost(id: 'p', authorName: 'Sam', workout: w),
                loadImage: (_) async => throw UnimplementedError(),
              ),
              WorkoutSplits(workout: w),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(RouteMap), findsOneWidget);
    expect(find.text('1.24 mi'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    // Average pace on the card, and mile 1's pace in the splits.
    expect(find.text('8:03 /mi'), findsNWidgets(2));
    expect(find.text('49 ft'), findsOneWidget);
    // One whole mile, then the 0.24 left over.
    expect(find.text('Mile'), findsOneWidget);
    expect(find.text('8:03'), findsOneWidget);
    expect(find.text('0.24'), findsOneWidget);

    await tester.tap(find.text('km'));
    await tester.pump();
    expect(find.text('5:00 /km'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the composer shares a recorded run, hiding its ends', (
    tester,
  ) async {
    bigScreen(tester);
    final w = recordedRun();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ...base(),
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPostComposer(context, recorded: w),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Share a workout'), findsOneWidget);
    expect(find.byType(RouteMap), findsOneWidget);
    expect(find.text('Minutes'), findsNothing, reason: 'time is recorded');
    expect(find.text('Gym'), findsNothing, reason: 'only GPS activities');
    expect(find.text('Hide your start and finish'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await tester.pumpAndSettle();

    final saved = posts.posts.single.workout!;
    expect(saved.durationSeconds, 600);
    expect(saved.distanceKm, 2);
    expect(saved.route!.splitsKm, [300, 300]);
    expect(saved.route!.pathMeters, closeTo(1600, 2));
  });

  testWidgets('records, pauses, finishes and posts a run', (tester) async {
    bigScreen(tester);
    final location = FakeLocationService();
    var now = DateTime(2026, 11, 2, 7);
    final recorder = WorkoutRecorder(location: location, clock: () => now);
    addTearDown(recorder.dispose);
    Future<void> fix(double north) async {
      location.fixes!.add(
        LocationFix(
          lat: 40 + north * 100 / 111195,
          lng: -105,
          accuracy: 5,
          time: now,
        ),
      );
      await tester.pump();
    }

    final router = GoRouter(
      initialLocation: Routes.recordWorkout,
      routes: [
        GoRoute(
          path: Routes.recordWorkout,
          builder: (_, _) => ViewModelHost(
            create: (_) =>
                RecordWorkoutViewModel(recorder: recorder, location: location),
            builder: (_, vm) => RecordWorkoutScreen(viewModel: vm),
          ),
        ),
        GoRoute(
          path: '${Routes.postsPath}/:id',
          builder: (_, s) => Text('Post ${s.pathParameters['id']}'),
        ),
      ],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ...base(),
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pump();
    expect(find.text('Finding you…'), findsOneWidget);
    await fix(0);
    expect(find.text('Start'), findsOneWidget);
    await tester.tap(find.text('Ride'));
    await tester.pump();
    await tester.tap(find.text('Run'));
    await tester.pump();

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Recording'), findsOneWidget);
    for (var i = 1; i <= 20; i++) {
      now = now.add(const Duration(seconds: 30));
      await fix(i.toDouble());
    }
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('1.24 mi'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Finish'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Share a workout'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await tester.pumpAndSettle();

    final saved = posts.posts.single;
    expect(saved.workout!.activity, WorkoutActivity.run);
    expect(saved.workout!.durationSeconds, 600);
    expect(find.text('Post ${saved.id}'), findsOneWidget);
    expect(recorder.state, RecorderState.idle);
    expect(tester.takeException(), isNull);
  });

  testWidgets('asks for location permission', (tester) async {
    final location = FakeLocationService()..access = LocationAccess.denied;
    final recorder = WorkoutRecorder(location: location);
    addTearDown(recorder.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ViewModelHost(
          create: (_) =>
              RecordWorkoutViewModel(recorder: recorder, location: location),
          builder: (_, vm) => RecordWorkoutScreen(viewModel: vm),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Location permission needed'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
