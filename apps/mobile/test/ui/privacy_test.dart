import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/follow.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/view_models/profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/ui/settings/widgets/follow_requests_screen.dart';
import 'package:frisbee_app/ui/settings/widgets/settings_screen.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late FakeFollowRepository follows;

  setUp(() {
    auth = FakeAuthRepository(user: testUser);
    profiles = FakeProfileRepository()..viewer = testUser.uid;
    follows = FakeFollowRepository();
  });

  ProfileViewModel settings() => ProfileViewModel(
    authRepository: auth,
    themeRepository: FakeThemeRepository(),
    notificationRepository: FakeNotificationRepository(),
    directMessageRepository: FakeDirectMessageRepository(),
    profileRepository: profiles,
    followRepository: follows,
  );

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
    await tester.pumpAndSettle();
  }

  group('change password', () {
    Future<ProfileViewModel> open(WidgetTester tester) async {
      final vm = settings();
      addTearDown(vm.dispose);
      await pump(tester, AccountSettingsScreen(viewModel: vm));
      await tester.tap(find.text('Change password'));
      await tester.pumpAndSettle();
      return vm;
    }

    Future<void> fill(
      WidgetTester tester, {
      required String current,
      required String next,
      String? confirm,
    }) async {
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(0), current);
      await tester.enterText(fields.at(1), next);
      await tester.enterText(fields.at(2), confirm ?? next);
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
    }

    testWidgets('changes it after checking the current one', (tester) async {
      await open(tester);
      await fill(tester, current: 'wrong', next: 'Frisbee2026!');
      expect(find.text('Incorrect email or password.'), findsOne);
      expect(auth.password, 'secret');

      await fill(tester, current: 'secret', next: 'Frisbee2026!');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Password changed'), findsOne);
      expect(auth.password, 'Frisbee2026!');
    });

    testWidgets('checks the new one before sending', (tester) async {
      await open(tester);
      await fill(tester, current: 'secret', next: 'short');
      expect(find.byType(AlertDialog), findsOne);
      expect(auth.password, 'secret');

      await fill(
        tester,
        current: 'secret',
        next: 'Frisbee2026!',
        confirm: 'Frisbee2027!',
      );
      expect(find.text("The passwords don't match"), findsOne);
      expect(auth.password, 'secret');
    });

    testWidgets('Google accounts have no password to change', (tester) async {
      auth.method = SignInMethod.google;
      final vm = settings();
      addTearDown(vm.dispose);
      await pump(tester, AccountSettingsScreen(viewModel: vm));
      expect(find.text('Change password'), findsNothing);
      expect(find.text('You sign in with Google'), findsOne);
    });
  });

  testWidgets('Privacy hides stats, games and teams, taking them off at once', (
    tester,
  ) async {
    profiles.put(
      PlayerProfile(
        uid: testUser.uid,
        name: 'Test User',
        summary: const ProfileSummary(
          teams: [ProfileTeam(id: 't1', name: 'Hawks', kind: TeamKind.team)],
          games: [],
        ),
      ),
    );
    final vm = settings();
    addTearDown(vm.dispose);
    await pump(tester, PrivacySettingsScreen(viewModel: vm));
    bool on(String label) => tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, label))
        .value;
    expect([on('Stats'), on('Recent games'), on('Teams')], [true, true, true]);

    await tester.tap(find.text('Teams'));
    await tester.pumpAndSettle();
    final p = profiles.profiles[testUser.uid]!;
    expect(p.details.visibility.teams, isFalse);
    expect(p.details.visibility.stats, isTrue);
    expect(p.summary.teams, isEmpty);
    expect(on('Teams'), isFalse);
  });

  group('private profile', () {
    testWidgets('Privacy turns it on, and lists requests to answer', (
      tester,
    ) async {
      profiles.put(PlayerProfile(uid: testUser.uid, name: 'Test User'));
      final vm = settings();
      addTearDown(vm.dispose);
      await pump(tester, PrivacySettingsScreen(viewModel: vm));
      expect(find.text('Follow requests'), findsNothing);

      await tester.tap(find.text('Private profile'));
      await tester.pumpAndSettle();
      expect(profiles.profiles[testUser.uid]!.isPrivate, isTrue);
      expect(find.text('Follow requests'), findsOne);

      await follows.requestFollow(
        const AppUser(uid: 'u2', email: 'r@x.org', displayName: 'Riley'),
        testUser.uid,
      );
      await follows.requestFollow(
        const AppUser(uid: 'u3', email: 's@x.org', displayName: 'Sam'),
        testUser.uid,
      );
      await pump(tester, FollowRequestsScreen(viewModel: vm));
      expect(find.text('Riley'), findsOne);
      expect(find.text('Sam'), findsOne);

      await tester.tap(find.widgetWithText(FilledButton, 'Accept').first);
      await tester.pumpAndSettle();
      expect(follows.follows['u2']?.keys, [FollowTarget.userKey(testUser.uid)]);
      expect(find.text('Riley'), findsNothing);

      await tester.tap(find.byTooltip('Decline'));
      await tester.pumpAndSettle();
      expect(follows.follows['u3'], isNull);
      expect(follows.requests[testUser.uid], isEmpty);
      expect(find.text('No requests right now'), findsOne);
    });

    testWidgets('others see only the header until they are accepted', (
      tester,
    ) async {
      profiles.put(
        const PlayerProfile(
          uid: 'p2',
          name: 'Pat',
          username: 'pat',
          isPrivate: true,
          details: ProfileDetails(bio: 'Cutter from Tech.'),
        ),
      );
      follows.privateOwners.add('p2');
      final vm = PlayerProfileViewModel(
        uid: 'p2',
        profileRepository: profiles,
        authRepository: auth,
        teamRepository: FakeTeamRepository(),
        statsRepository: FakeStatsRepository(),
        directMessageRepository: FakeDirectMessageRepository(),
        followRepository: follows,
        notificationRepository: FakeNotificationRepository(),
      );
      addTearDown(vm.dispose);
      await pump(tester, PlayerProfileScreen(viewModel: vm));

      expect(find.text('Pat'), findsWidgets);
      expect(find.text('@pat'), findsOne);
      expect(find.text('This profile is private'), findsOne);
      expect(find.text('Cutter from Tech.'), findsNothing);
      expect(find.text('Overview'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Follow'));
      await tester.pumpAndSettle();
      expect(follows.requests['p2']?.keys, [testUser.uid]);
      expect(follows.follows[testUser.uid], isNull);
      expect(find.text('Requested'), findsOne);

      // Taking it back.
      await tester.tap(find.text('Requested'));
      await tester.pumpAndSettle();
      expect(follows.requests['p2'], isEmpty);
      expect(find.widgetWithText(FilledButton, 'Follow'), findsOne);

      // Ask again; Pat accepts.
      await tester.tap(find.widgetWithText(FilledButton, 'Follow'));
      await tester.pumpAndSettle();
      profiles.allowed.add('p2');
      await follows.acceptFollowRequest(
        const AppUser(uid: 'p2', email: 'p@x.org', displayName: 'Pat'),
        follows.requests['p2']![testUser.uid]!,
      );
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOne);
      expect(find.text('This profile is private'), findsNothing);
      expect(find.text('Cutter from Tech.'), findsOne);
    });
  });
}
