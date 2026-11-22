// Phone screenshots of the hat tournament, signup, draft and stats screens,
// light and dark, for design review. Skipped unless asked for:
//   flutter test test/screenshots/hatstats_test.dart \
//     --dart-define=SCREENSHOTS=<out dir>
// writes <out dir>/{light,dark}/<name>.png at 390x844.
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/stats.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/tournament_engine/generator.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/group_tournaments/view_models/group_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/group_tournaments/view_models/group_tournaments_viewmodel.dart';
import 'package:frisbee_app/ui/group_tournaments/view_models/tournament_editor_viewmodel.dart';
import 'package:frisbee_app/ui/group_tournaments/widgets/group_tournament_screen.dart';
import 'package:frisbee_app/ui/group_tournaments/widgets/group_tournaments_tab.dart';
import 'package:frisbee_app/ui/group_tournaments/widgets/tournament_editor_screen.dart';
import 'package:frisbee_app/ui/stats/view_models/game_tracker_viewmodel.dart';
import 'package:frisbee_app/ui/stats/view_models/stats_viewmodel.dart';
import 'package:frisbee_app/ui/stats/view_models/tournament_viewmodel.dart';
import 'package:frisbee_app/ui/stats/widgets/game_screen.dart';
import 'package:frisbee_app/ui/stats/widgets/stats_tab.dart';
import 'package:frisbee_app/ui/stats/widgets/tournament_screen.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_form_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/live_draft_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/player_signups_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/team_draft_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournament_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/live_draft_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/team_draft_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/group_tournament_fakes.dart';
import '../testing/hosted_tournament_fakes.dart';
import '../testing/mock_stats_repository.dart';

const _out = String.fromEnvironment('SCREENSHOTS');

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

const _names = [
  'Ava Brooks',
  'Sam Ortiz',
  'Jo Park',
  'Mia Chen',
  'Leo Grant',
  'Zoe Hart',
  'Kai Reyes',
  'Ivy Lane',
  'Max Cole',
  'Ella Fox',
  'Noah Diaz',
  'Ruby Shaw',
  'Owen Pike',
  'Lena Voss',
  'Theo Marsh',
];

void main() {
  final skip = _out.isEmpty ? 'pass --dart-define=SCREENSHOTS=<dir>' : null;
  final shot = GlobalKey();

  FakeAuthRepository as(String uid) => FakeAuthRepository(
    user: AppUser(uid: uid, email: '$uid@x.com', displayName: 'Player $uid'),
  );

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    required bool dark,
  }) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name, bool dark) async {
    await tester.pump(const Duration(milliseconds: 400));
    final boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = '$_out/${dark ? 'dark' : 'light'}';
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> setUpView(WidgetTester tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  // ---- Hat tournaments in a group ----------------------------------------

  late FakeTeamRepository groupTeams;
  late FakeGroupTournamentRepository groups;
  final players = [for (var i = 0; i < 12; i++) 'p$i'];

  void seedGroup({required bool played}) {
    groupTeams = FakeTeamRepository();
    groups = FakeGroupTournamentRepository();
    final members = {
      'owner': TeamRole.owner,
      for (final p in players) p: TeamRole.player,
    };
    groupTeams.teams['g1'] = Team(
      id: 'g1',
      name: 'Sunday Pickup',
      division: Division.mixed,
      level: CompetitionLevel.pickup,
      city: 'Denver',
      ownerId: 'owner',
      members: members,
      memberNames: {
        'owner': 'Jo Director',
        for (final (i, p) in players.indexed) p: _names[i],
      },
      kind: TeamKind.community,
    );
    final t = GroupTournament(
      id: 't1',
      name: 'Fall Hat',
      status: TournamentStatus.scheduled,
      settings: TournamentSettings(
        startsAt: DateTime(2026, 11, 21, 9),
        format: TournamentFormat.poolsSingleElim,
        scoreCap: 11,
      ),
      teams: [
        for (final (i, n) in [
          'Hucks',
          'Layouts',
          'Hammers',
          'Scoobers',
        ].indexed)
          TournamentTeam(
            id: 'T${i + 1}',
            name: n,
            captainId: players[i * 3],
            playerIds: [for (var j = 0; j < 3; j++) players[i * 3 + j]],
            playerNames: {
              for (var j = 0; j < 3; j++) players[i * 3 + j]: _names[i * 3 + j],
            },
          ),
      ],
    );
    groups.tournaments['g1'] = [
      t,
      GroupTournament(
        id: 't2',
        name: 'Winter Hat',
        settings: TournamentSettings(startsAt: DateTime(2026, 12, 12, 10)),
      ),
    ];
    var games = generateSchedule(t).games;
    if (played) {
      var n = 0;
      games = [
        for (final g in games)
          if (g.hasTeams && n++ < 3)
            g.copyWith(
              status: GameStatus.done,
              scoreA: () => 11,
              scoreB: () => 6 + n,
            )
          else
            g,
      ];
    }
    groups.games['t1'] = games;
  }

  GroupTournamentViewModel groupVm(String uid) => GroupTournamentViewModel(
    groupId: 'g1',
    tournamentId: 't1',
    teamRepository: groupTeams,
    tournamentRepository: groups,
    authRepository: as(uid),
  );

  // ---- Hosted hat tournaments: signups and drafts ------------------------

  late FakeTeamRepository hostTeams;
  late FakeHostedTournamentRepository hosted;

  Future<String> hostHat({int signups = 12, bool captains = false}) async {
    hostTeams = FakeTeamRepository();
    hosted = FakeHostedTournamentRepository();
    hostTeams.teams['host'] = Team(
      id: 'host',
      name: 'Front Range Ultimate',
      division: Division.mixed,
      level: CompetitionLevel.club,
      ownerId: 'director',
      members: {'director': TeamRole.owner},
      memberNames: {'director': 'Jo Director'},
      kind: TeamKind.community,
    );
    final f = HostedTournamentFormViewModel(
      hostId: 'host',
      tournamentRepository: hosted,
      teamRepository: hostTeams,
      authRepository: as('director'),
      now: () => DateTime(2027, 3, 1),
    );
    await pumpEventQueue();
    f.setEntryType(TournamentEntryType.players);
    if (captains) f.setDraftMode(DraftMode.captains);
    f.name = 'Spring Hat';
    f.setHasFee(true);
    f.feeAmount = '20';
    f.feeInstructions = 'Venmo @host';
    f.setFeeDue(DateTime(2027, 4, 1));
    f.setFieldSize(4);
    f.setFormat(f.format.copyWith(maxTeams: 8));
    await f.save.execute();
    final id = (f.save.result as Ok<String>).value;
    f.dispose();
    final page = HostedTournamentViewModel(
      tournamentId: id,
      tournamentRepository: hosted,
      teamRepository: hostTeams,
      authRepository: as('director'),
      now: () => DateTime(2027, 3, 10),
    );
    await pumpEventQueue();
    await page.setStatus.execute(HostedStatus.registration);
    await pumpEventQueue();
    page.dispose();
    final division = hosted.divisions[id]!.keys.single;
    for (var i = 0; i < signups; i++) {
      hosted.signups.putIfAbsent(id, () => {})['p$i'] = PlayerSignup(
        uid: 'p$i',
        name: _names[i],
        divisionId: division,
        skill: 1 + (i * 3) % 5,
        gender: i.isEven ? GenderMatch.mmp : GenderMatch.wmp,
        status: i < signups - 3
            ? SignupStatus.accepted
            : i == signups - 1
            ? SignupStatus.waitlisted
            : SignupStatus.applied,
      );
    }
    return id;
  }

  HostedTournamentViewModel hostedPage(String id, String uid) =>
      HostedTournamentViewModel(
        tournamentId: id,
        tournamentRepository: hosted,
        teamRepository: hostTeams,
        authRepository: as(uid),
        now: () => DateTime(2027, 3, 10),
      );

  PlayerSignupsViewModel signupsVm(String id, String uid, {bool m = false}) =>
      PlayerSignupsViewModel(
        tournamentId: id,
        tournamentRepository: hosted,
        authRepository: as(uid),
        manager: m,
      );

  LiveDraftViewModel board(String uid, String id, String d) =>
      LiveDraftViewModel(
        tournamentId: id,
        divisionId: d,
        tournamentRepository: hosted,
        teamRepository: hostTeams,
        authRepository: as(uid),
        now: () => DateTime(2027, 1, 1, 0, 0, 23),
      );

  // ---- Stats -------------------------------------------------------------

  late MockStatsRepository stats;
  late FakeTeamRepository statTeams;

  void seedStats() {
    statTeams = FakeTeamRepository()
      ..teams['t1'] = teamWith({'u1': TeamRole.owner});
    stats = MockStatsRepository(teamRepository: statTeams);
  }

  GameTrackerViewModel tracker(String gameId) => GameTrackerViewModel(
    teamId: 't1',
    gameId: gameId,
    statsRepository: stats,
    teamRepository: statTeams,
    authRepository: FakeAuthRepository(user: testUser),
  );

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('hat tournament list ($theme)', skip: skip != null, (
      tester,
    ) async {
      await setUpView(tester);
      seedGroup(played: false);
      final vm = GroupTournamentsViewModel(
        groupId: 'g1',
        teamRepository: groupTeams,
        tournamentRepository: groups,
        authRepository: as('owner'),
      );
      await pump(
        tester,
        Scaffold(
          appBar: AppBar(title: const Text('Sunday Pickup')),
          body: ListView(children: [HatTournamentsList(viewModel: vm)]),
        ),
        dark: dark,
      );
      await capture(tester, 'hat-01-list', dark);
    });

    testWidgets('hat tournament ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      seedGroup(played: true);
      // p3 captains Layouts.
      await pump(
        tester,
        GroupTournamentScreen(viewModel: groupVm('p3')),
        dark: dark,
      );
      await capture(tester, 'hat-02-schedule', dark);
      await tab(tester, 'Standings');
      await capture(tester, 'hat-03-standings', dark);
      await tab(tester, 'Bracket');
      await capture(tester, 'hat-04-bracket', dark);
      await tab(tester, 'Teams');
      await capture(tester, 'hat-05-teams', dark);
      await tab(tester, 'Schedule');
      final report = find.text('Report score');
      if (report.evaluate().isNotEmpty) {
        await tester.tap(report.first);
        await tester.pumpAndSettle();
        await capture(tester, 'hat-06-game-sheet', dark);
      }
    });

    testWidgets('hat tournament, organizer ($theme)', skip: skip != null, (
      tester,
    ) async {
      await setUpView(tester);
      seedGroup(played: false);
      groups.games['t1'] = [];
      groups.tournaments['g1'] = [
        groups.tournaments['g1']!.first.copyWith(
          status: TournamentStatus.setup,
        ),
      ];
      await pump(
        tester,
        GroupTournamentScreen(viewModel: groupVm('owner')),
        dark: dark,
      );
      await capture(tester, 'hat-07-setup', dark);
    });

    testWidgets('hat tournament editor ($theme)', skip: skip != null, (
      tester,
    ) async {
      await setUpView(tester);
      seedGroup(played: false);
      final vm = TournamentEditorViewModel(
        groupId: 'g1',
        tournamentId: null,
        teamRepository: groupTeams,
        eventRepository: FakeEventRepository(),
        tournamentRepository: groups,
        authRepository: as('owner'),
        postRepository: FakeTeamPostRepository(),
        filePicker: FakeFilePickerService(),
        clock: () => DateTime(2026, 11, 1),
        random: Random(1),
      );
      await tester.runAsync(pumpEventQueue);
      await pump(tester, TournamentEditorScreen(viewModel: vm), dark: dark);
      await capture(tester, 'hat-08-editor', dark);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      await capture(tester, 'hat-09-editor-scrolled', dark);
    });

    testWidgets('signups, host ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      final id = (await tester.runAsync(hostHat))!;
      final vm = hostedPage(id, 'director');
      final sign = signupsVm(id, 'director', m: true);
      await tester.runAsync(pumpEventQueue);
      await pump(
        tester,
        HostedTournamentScreen(viewModel: vm, signups: sign),
        dark: dark,
      );
      await tab(tester, 'Players');
      await capture(tester, 'hat-10-signups-host', dark);
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      await capture(tester, 'hat-11-signups-host-scrolled', dark);
    });

    testWidgets('signups, player ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      final id = (await tester.runAsync(hostHat))!;
      final vm = hostedPage(id, 'p1');
      final sign = signupsVm(id, 'p1');
      await tester.runAsync(pumpEventQueue);
      await pump(
        tester,
        HostedTournamentScreen(viewModel: vm, signups: sign),
        dark: dark,
      );
      await capture(tester, 'hat-12-signup-player', dark);
    });

    testWidgets('team draft ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      final id = (await tester.runAsync(() => hostHat(signups: 15)))!;
      final vm = TeamDraftViewModel(
        tournamentId: id,
        divisionId: hosted.divisions[id]!.keys.single,
        tournamentRepository: hosted,
        seed: 1,
      );
      await tester.runAsync(pumpEventQueue);
      vm.setTeamCount(3);
      await tester.runAsync(vm.draft.execute);
      await pump(tester, TeamDraftScreen(viewModel: vm), dark: dark);
      await capture(tester, 'hat-13-team-draft', dark);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      await capture(tester, 'hat-14-team-draft-scrolled', dark);
    });

    testWidgets('live draft ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      final id = (await tester.runAsync(
        () => hostHat(signups: 11, captains: true),
      ))!;
      final d = hosted.divisions[id]!.keys.single;
      final host = board('director', id, d);
      await tester.runAsync(pumpEventQueue);
      await pump(tester, LiveDraftScreen(viewModel: host), dark: dark);
      await capture(tester, 'hat-15-live-draft-setup', dark);
      host.toggleCaptain('p0');
      host.toggleCaptain('p1');
      host.toggleCaptain('p2');
      await tester.runAsync(() async {
        await host.start.execute();
        await pumpEventQueue();
      });
      final cap = board('p0', id, d);
      await tester.runAsync(pumpEventQueue);
      await pump(tester, LiveDraftScreen(viewModel: cap), dark: dark);
      await capture(tester, 'hat-16-live-draft-my-turn', dark);
      await tester.runAsync(() async {
        await cap.pick.execute('p4');
        await pumpEventQueue();
      });
      await tester.pump();
      await capture(tester, 'hat-17-live-draft-their-turn', dark);
      await tester.pumpWidget(const SizedBox());
      cap.dispose();
      host.dispose();
    });

    testWidgets('stats tab ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      seedStats();
      final vm = StatsViewModel(
        teamId: 't1',
        statsRepository: stats,
        eventRepository: FakeEventRepository(),
        teamRepository: statTeams,
        authRepository: FakeAuthRepository(user: testUser),
      );
      await pump(
        tester,
        Scaffold(body: StatsTab(viewModel: vm)),
        dark: dark,
      );
      await capture(tester, 'stat-01-tab', dark);
    });

    testWidgets('tracker ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      seedStats();
      final games = await stats.watchGames('t1').first;
      final live = games.firstWhere((g) => !g.finished);
      final vm = tracker(live.id);
      await pump(tester, GameScreen(viewModel: vm), dark: dark);
      vm.setSide(Side.offense);
      await tester.pumpAndSettle();
      await capture(tester, 'stat-02-lineup', dark);
      await tester.ensureVisible(find.text('Last O line'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last O line'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start point'));
      await tester.pumpAndSettle();
      final line = vm.currentPoint!.line;
      await tester.tap(find.text(vm.nameOf(line[0])).first);
      await tester.pumpAndSettle();
      await capture(tester, 'stat-03-offense', dark);
      await tester.tap(find.text('Throwaway'));
      await tester.pumpAndSettle();
      await capture(tester, 'stat-04-defense', dark);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('finished game ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      seedStats();
      final games = await stats.watchGames('t1').first;
      final done = games.firstWhere((g) => g.over);
      await pump(tester, GameScreen(viewModel: tracker(done.id)), dark: dark);
      await capture(tester, 'stat-05-game-over', dark);
      await tab(tester, 'Points');
      await capture(tester, 'stat-06-points', dark);
      await tab(tester, 'Stats');
      await capture(tester, 'stat-07-game-stats', dark);
    });

    testWidgets('tournament stats ($theme)', skip: skip != null, (
      tester,
    ) async {
      await setUpView(tester);
      seedStats();
      final ts = await stats.watchTournaments('t1').first;
      final vm = TournamentViewModel(
        teamId: 't1',
        tournamentId: ts.first.id,
        statsRepository: stats,
        teamRepository: statTeams,
        authRepository: FakeAuthRepository(user: testUser),
      );
      await pump(tester, TournamentScreen(viewModel: vm), dark: dark);
      await capture(tester, 'stat-08-tournament', dark);
      await tab(tester, 'Stats');
      await capture(tester, 'stat-09-tournament-stats', dark);
    });
  }
}
