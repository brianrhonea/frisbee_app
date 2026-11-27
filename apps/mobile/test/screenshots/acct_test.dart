// TEMPORARY (redesign subtask 3f): phone screenshots of sign-in,
// onboarding and settings on fake data. Skipped unless asked for:
//   flutter test test/screenshots/acct_test.dart \
//     --dart-define=SCREENSHOTS=<out dir> [--dart-define=SHOT_THEME=dark]
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/calendar.dart';
import 'package:frisbee_app/domain/models/follow.dart';
import 'package:frisbee_app/domain/models/notification.dart';
import 'package:frisbee_app/domain/models/personal_details.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/auth/view_models/choose_username_viewmodel.dart';
import 'package:frisbee_app/ui/auth/view_models/sign_in_viewmodel.dart';
import 'package:frisbee_app/ui/auth/view_models/sign_up_viewmodel.dart';
import 'package:frisbee_app/ui/auth/widgets/choose_username_screen.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_in_screen.dart';
import 'package:frisbee_app/ui/auth/widgets/sign_up_screen.dart';
import 'package:frisbee_app/ui/calendar/view_models/calendars_viewmodel.dart';
import 'package:frisbee_app/ui/calendar/widgets/calendars_screen.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/notifications/view_models/notification_settings_viewmodel.dart';
import 'package:frisbee_app/ui/notifications/widgets/follow_requests_screen.dart';
import 'package:frisbee_app/ui/notifications/widgets/notification_settings_screen.dart';
import 'package:frisbee_app/ui/people/view_models/following_viewmodel.dart';
import 'package:frisbee_app/ui/people/widgets/following_screen.dart';
import 'package:frisbee_app/ui/personal/view_models/personal_details_viewmodel.dart';
import 'package:frisbee_app/ui/personal/widgets/personal_details_screen.dart';
import 'package:frisbee_app/ui/profile/view_models/profile_viewmodel.dart';
import 'package:frisbee_app/ui/settings/widgets/settings_screen.dart';

import 'shot_env.dart';
import '../testing/fakes.dart';
import '../testing/social_fakes.dart';

const _out = String.fromEnvironment('SCREENSHOTS');
const _dark = String.fromEnvironment('SHOT_THEME') == 'dark';

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family('Inter', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'])
      'assets/fonts/Inter-$w.ttf',
  ]);
  await family('Barlow Condensed', [
    for (final w in ['Bold', 'ExtraBold', 'ExtraBoldItalic'])
      'assets/fonts/BarlowCondensed-$w.ttf',
  ]);
  var dir = File(Platform.resolvedExecutable).parent;
  const icons = 'bin/cache/artifacts/material_fonts/materialicons-regular.otf';
  while (!File('${dir.path}/$icons').existsSync() && dir.parent != dir) {
    dir = dir.parent;
  }
  await family('MaterialIcons', ['${dir.path}/$icons']);
}

const _me = AppUser(
  uid: 'u1',
  email: 'ava.brooks@gmail.com',
  displayName: 'Ava Brooks',
  username: 'avabrooks',
);

void main() {
  final skip = _out.isEmpty;
  final shot = GlobalKey();

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(shotWidth * 3.0, shotHeight * 3.0);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _dark ? AppTheme.dark : AppTheme.light,
          // No disc throw: the screen as it settles.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    // Let the logo image finish decoding, so every picture shows it.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    final boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late FakeFollowRepository follows;

  setUp(() {
    auth = FakeAuthRepository(user: _me);
    profiles = FakeProfileRepository()..viewer = _me.uid;
    profiles.put(PlayerProfile(uid: _me.uid, name: 'Ava Brooks'));
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

  testWidgets('01 sign in', skip: skip, (tester) async {
    final vm = SignInViewModel(authRepository: FakeAuthRepository());
    addTearDown(vm.dispose);
    await pump(tester, SignInScreen(viewModel: vm));
    await capture(tester, 'acct-01-sign-in');
  });

  testWidgets('02 sign up', skip: skip, (tester) async {
    final vm = SignUpViewModel(
      authRepository: FakeAuthRepository(),
      personalRepository: FakePersonalDetailsRepository(),
    );
    addTearDown(vm.dispose);
    await pump(tester, SignUpScreen(viewModel: vm));
    await capture(tester, 'acct-02-sign-up');
    await tester.enterText(find.byType(TextFormField).at(0), 'Ava');
    await tester.enterText(find.byType(TextFormField).at(1), 'Brooks');
    await tester.enterText(find.byType(TextFormField).at(4), 'Layout-D-26!');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await capture(tester, 'acct-02b-sign-up-scrolled');
  });

  testWidgets('03 username', skip: skip, (tester) async {
    final a =
        FakeAuthRepository(
            user: const AppUser(
              uid: 'u1',
              email: 'ava.brooks@gmail.com',
              displayName: 'Ava Brooks',
            ),
          )
          ..method = SignInMethod.google
          ..usernameMissing = true;
    final vm = ChooseUsernameViewModel(authRepository: a);
    addTearDown(vm.dispose);
    await pump(tester, ChooseUsernameScreen(viewModel: vm));
    await tester.pump(const Duration(seconds: 1));
    await capture(tester, 'acct-03-username');
  });

  testWidgets('04 finish sign-up details', skip: skip, (tester) async {
    final vm = PersonalDetailsViewModel(
      personalRepository: FakePersonalDetailsRepository(
        status: const PersonalDetailsStatus(complete: false, required: true),
      )..email = _me.email,
      authRepository: auth,
      finishing: true,
    );
    addTearDown(vm.dispose);
    await pump(tester, PersonalDetailsScreen(viewModel: vm));
    await capture(tester, 'acct-04-details');
  });

  testWidgets('05 settings', skip: skip, (tester) async {
    final vm = settings();
    addTearDown(vm.dispose);
    await pump(tester, SettingsScreen(viewModel: vm));
    await capture(tester, 'acct-05-settings');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await capture(tester, 'acct-05b-settings-scrolled');
  });

  testWidgets('06 general', skip: skip, (tester) async {
    final vm = settings();
    addTearDown(vm.dispose);
    await pump(tester, GeneralSettingsScreen(viewModel: vm));
    await capture(tester, 'acct-06-settings-general');
  });

  testWidgets('07 privacy', skip: skip, (tester) async {
    final vm = settings();
    addTearDown(vm.dispose);
    await pump(tester, PrivacySettingsScreen(viewModel: vm));
    await capture(tester, 'acct-07-settings-privacy');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await capture(tester, 'acct-07b-settings-privacy-scrolled');
  });

  testWidgets('08 personal details', skip: skip, (tester) async {
    final vm = PersonalDetailsViewModel(
      personalRepository: FakePersonalDetailsRepository()..email = _me.email,
      authRepository: auth,
    );
    addTearDown(vm.dispose);
    await pump(tester, PersonalDetailsScreen(viewModel: vm));
    await capture(tester, 'acct-08-settings-personal');
  });

  testWidgets('09 calendars', skip: skip, (tester) async {
    const me = CalendarPerson(uid: 'u1', name: 'Ava Brooks');
    const riley = CalendarPerson(uid: 'r', name: 'Riley Chen');
    final calendars = FakeCalendarRepository()
      ..feedLink = const CalendarFeed(
        url: 'https://example.test/cal/abc.ics',
        webcal: 'webcal://example.test/cal/abc.ics',
      )
      ..calendarList = [
        CalendarInfo(
          id: 'u1',
          name: "Ava's calendar",
          color: CalendarColor.green,
          owner: me,
          role: CalendarRole.owner,
          isDefault: true,
          members: [(person: me, role: CalendarRole.owner)],
        ),
        CalendarInfo(
          id: 'c2',
          name: 'Throwing sessions',
          color: CalendarColor.blue,
          owner: me,
          role: CalendarRole.owner,
          members: [
            (person: me, role: CalendarRole.owner),
            (person: riley, role: CalendarRole.view),
          ],
        ),
        CalendarInfo(
          id: 'r',
          name: 'Flyers coaching',
          color: CalendarColor.purple,
          owner: riley,
          role: CalendarRole.view,
        ),
      ]
      ..inviteList = [
        CalendarInvite(
          calendarId: 'jo',
          calendarName: 'Snowmelt Hat carpool',
          color: CalendarColor.pink,
          role: CalendarRole.edit,
          from: CalendarPerson(uid: 'jo', name: 'Jo Park'),
        ),
      ];
    final vm = CalendarsViewModel(
      calendarRepository: calendars,
      profileRepository: FakeProfileRepository(),
      uid: 'u1',
    );
    addTearDown(vm.dispose);
    await pump(tester, CalendarsScreen(viewModel: vm));
    await capture(tester, 'acct-09-settings-calendar');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await capture(tester, 'acct-09b-settings-calendar-scrolled');
  });

  testWidgets('10 account', skip: skip, (tester) async {
    final vm = settings();
    addTearDown(vm.dispose);
    await pump(tester, AccountSettingsScreen(viewModel: vm));
    await capture(tester, 'acct-10-settings-account');
  });

  testWidgets('11 notification settings', skip: skip, (tester) async {
    final teams = FakeTeamRepository()
      ..teams['t1'] = Team(
        id: 't1',
        name: 'Northside Flyers',
        division: Division.mixed,
        level: CompetitionLevel.club,
        ownerId: 'u1',
        members: const {'u1': TeamRole.owner},
      );
    final vm = NotificationSettingsViewModel(
      notificationRepository: FakeNotificationRepository(
        status: PushStatus.enabled,
      ),
      teamRepository: teams,
      authRepository: auth,
    );
    addTearDown(vm.dispose);
    await pump(tester, NotificationSettingsScreen(viewModel: vm));
    await capture(tester, 'acct-11-notification-settings');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await capture(tester, 'acct-11b-notification-settings-scrolled');
  });

  testWidgets('11c notification settings, push off', skip: skip, (
    tester,
  ) async {
    final vm = NotificationSettingsViewModel(
      notificationRepository: FakeNotificationRepository(
        status: PushStatus.notDetermined,
      ),
      teamRepository: FakeTeamRepository(),
      authRepository: auth,
    );
    addTearDown(vm.dispose);
    await pump(tester, NotificationSettingsScreen(viewModel: vm));
    await capture(tester, 'acct-11c-notification-settings-off');
  });

  testWidgets('12 follow requests', skip: skip, (tester) async {
    profiles.put(
      PlayerProfile(uid: _me.uid, name: 'Ava Brooks', isPrivate: true),
    );
    for (final (uid, name) in [
      ('s', 'Sam Ortiz'),
      ('j', 'Jo Park'),
      ('m', 'Maya Torres'),
    ]) {
      await follows.requestFollow(
        AppUser(uid: uid, displayName: name, username: name.split(' ')[0]),
        _me.uid,
      );
    }
    final vm = settings();
    addTearDown(vm.dispose);
    await pump(tester, FollowRequestsScreen(viewModel: vm));
    await capture(tester, 'acct-12-follow-requests');
  });

  testWidgets('13 following', skip: skip, (tester) async {
    for (final (t, notify) in [
      (const FollowTarget.team('t1', 'Northside Flyers'), true),
      (const FollowTarget.team('g1', 'Denver Thursday Pickup'), false),
      (const FollowTarget.tournament('h1', 'x9', 'Mile High Open'), true),
      (const FollowTarget.user('r', 'Riley Chen'), false),
      (const FollowTarget.user('s', 'Sam Ortiz'), false),
    ]) {
      await follows.follow(_me.uid, t, notify: notify);
    }
    final vm = FollowingViewModel(
      followRepository: follows,
      notificationRepository: FakeNotificationRepository(),
      authRepository: auth,
    );
    addTearDown(vm.dispose);
    await pump(tester, FollowingScreen(viewModel: vm));
    await capture(tester, 'acct-13-settings-following');
  });
}
