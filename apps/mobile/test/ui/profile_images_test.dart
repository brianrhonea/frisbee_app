import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/profile/profile_repository.dart';
import 'package:frisbee_app/data/services/image_compressor.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late FakeFilePickerService picker;

  setUp(() {
    auth = FakeAuthRepository(user: testUser);
    profiles = FakeProfileRepository()
      ..put(PlayerProfile(uid: testUser.uid, name: testUser.label))
      ..put(const PlayerProfile(uid: 'p2', name: 'Pat Lee'));
    picker = FakeFilePickerService();
  });

  PlayerProfileViewModel profileOf(String uid, {bool canPick = true}) =>
      PlayerProfileViewModel(
        uid: uid,
        profileRepository: profiles,
        authRepository: auth,
        teamRepository: FakeTeamRepository(),
        statsRepository: FakeStatsRepository(),
        directMessageRepository: FakeDirectMessageRepository(),
        filePicker: canPick ? picker : null,
      );

  group('profile picture', () {
    test('a picked photo is uploaded and set on the account', () async {
      final vm = profileOf(testUser.uid);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      var notified = 0;
      vm.addListener(() => notified++);
      picker.next = [FakeFilePickerService.file('me.png', 2000)];

      await vm.changeImage.execute((ProfileImage.photo, camera: false));

      expect(vm.changeImage.completed, isTrue);
      expect(profiles.uploads.single.$1, ProfileImage.photo);
      expect(auth.currentUser?.photoUrl, 'https://img.test/u1/photo-1');
      expect(vm.photoUrl, 'https://img.test/u1/photo-1');
      expect(notified, greaterThan(0));
      expect(profiles.deleted, isEmpty);
    });

    test('replacing it deletes the old upload; removing clears it', () async {
      auth.setUser(testUser.withPhotoUrl('https://img.test/old'));
      final vm = profileOf(testUser.uid);
      addTearDown(vm.dispose);
      picker.nextPhoto = FakeFilePickerService.file('cam.jpg', 2000);

      await vm.changeImage.execute((ProfileImage.photo, camera: true));
      expect(auth.currentUser?.photoUrl, 'https://img.test/u1/photo-1');
      expect(profiles.deleted, ['https://img.test/old']);

      await vm.removeImage.execute(ProfileImage.photo);
      expect(auth.currentUser?.photoUrl, isNull);
      expect(profiles.deleted.last, 'https://img.test/u1/photo-1');
    });

    test('picking nothing changes nothing', () async {
      final vm = profileOf(testUser.uid);
      addTearDown(vm.dispose);
      await vm.changeImage.execute((ProfileImage.photo, camera: false));
      expect(vm.changeImage.completed, isTrue);
      expect(profiles.uploads, isEmpty);
    });

    test('if the account refuses it, the upload is deleted', () async {
      final vm = profileOf(testUser.uid);
      addTearDown(vm.dispose);
      picker.next = [FakeFilePickerService.file('me.png', 2000)];
      auth.nextError = Exception('offline');

      await vm.changeImage.execute((ProfileImage.photo, camera: false));

      expect(vm.changeImage.error, isTrue);
      expect(auth.currentUser?.photoUrl, isNull);
      expect(profiles.deleted, ['https://img.test/u1/photo-1']);
    });
  });

  test('a header is set on the profile and seen by others', () async {
    final vm = profileOf(testUser.uid);
    addTearDown(vm.dispose);
    await pumpEventQueue();
    picker.next = [FakeFilePickerService.file('beach.jpg', 4000)];

    await vm.changeImage.execute((ProfileImage.header, camera: false));
    await pumpEventQueue();
    expect(vm.headerUrl, 'https://img.test/u1/header-1');

    final other = PlayerProfileViewModel(
      uid: testUser.uid,
      profileRepository: profiles,
      authRepository: FakeAuthRepository(user: const AppUser(uid: 'p2')),
      teamRepository: FakeTeamRepository(),
      statsRepository: FakeStatsRepository(),
      directMessageRepository: FakeDirectMessageRepository(),
    );
    addTearDown(other.dispose);
    await pumpEventQueue();
    expect(other.headerUrl, 'https://img.test/u1/header-1');
    expect(other.canEditImages, isFalse);

    await vm.removeImage.execute(ProfileImage.header);
    await pumpEventQueue();
    expect(vm.headerUrl, isNull);
    expect(profiles.deleted, ['https://img.test/u1/header-1']);
  });

  test("someone else's pictures can't be changed", () async {
    final vm = profileOf('p2');
    addTearDown(vm.dispose);
    expect(vm.canEditImages, isFalse);
    picker.next = [FakeFilePickerService.file('x.png', 10)];
    await vm.changeImage.execute((ProfileImage.header, camera: false));
    expect(vm.changeImage.result, isA<Error<void>>());
    expect(profiles.uploads, isEmpty);
  });

  testWidgets('Edit profile offers to change both pictures', (tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    picker
      ..canUseCamera = true
      // Shrinking runs in an isolate, which a widget test's clock never
      // finishes.
      ..compressor = const ImageCompressor(enabled: false);
    final vm = profileOf(testUser.uid);
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(home: PlayerProfileScreen(viewModel: vm)),
    );
    await tester.pumpAndSettle();

    // Only once editing, not on the profile itself.
    expect(find.byTooltip('Change profile picture'), findsNothing);
    expect(find.byTooltip('Change header photo'), findsNothing);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Change profile picture'), findsOneWidget);
    await tester.tap(find.byTooltip('Change header photo'));
    await tester.pumpAndSettle();
    expect(find.text('Choose photo'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Remove header photo'), findsNothing);

    picker.next = [FakeFilePickerService.file('beach.jpg', 4000)];
    await tester.tap(find.text('Choose photo'));
    await tester.pumpAndSettle();
    expect(vm.headerUrl, isNotNull);
    // On the profile and in the dialog's preview. Tests can't load it, so
    // the default banner shows in its place.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is NetworkImage &&
            (w.image as NetworkImage).url == vm.headerUrl,
      ),
      findsNWidgets(2),
    );

    await tester.tap(find.byTooltip('Change header photo'));
    await tester.pumpAndSettle();
    expect(find.text('Remove header photo'), findsOneWidget);
  });

  testWidgets("no edit buttons on someone else's profile", (tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = profileOf('p2');
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(home: PlayerProfileScreen(viewModel: vm)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsNothing);
    expect(find.byTooltip('Change profile picture'), findsNothing);
    expect(find.byTooltip('Change header photo'), findsNothing);
  });
}
