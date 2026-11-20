// Phone screenshots of the tournament and league screens, light and dark,
// for design review. Skipped unless asked for:
//   flutter test test/screenshots/tournaments_test.dart \
//     --dart-define=SCREENSHOTS=<out dir>
// writes <out dir>/{light,dark}/<name>.png at 390x844.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/hosted_tournament/tournament_days.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/tournaments/view_models/host_event_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_form_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournaments_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/widgets/host_event_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournament_form_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournament_screen.dart';
import 'package:frisbee_app/ui/tournaments/widgets/hosted_tournaments_list.dart';
import 'package:frisbee_app/ui/tournaments/widgets/tournament_day_card.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';

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

void main() {
  final skip = _out.isEmpty ? 'pass --dart-define=SCREENSHOTS=<dir>' : null;
  final clock = DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  // Late morning, so the live tournament has games on and up next.
  final now = today.add(const Duration(hours: 11));
  final shot = GlobalKey();

  late FakeHostedTournamentRepository repo;
  late FakeTeamRepository teams;

  Team team(
    String id,
    String name,
    Map<String, TeamRole> members, {
    TeamKind kind = TeamKind.team,
  }) => Team(
    id: id,
    name: name,
    division: Division.mixed,
    level: CompetitionLevel.club,
    city: 'Denver',
    ownerId: members.keys.first,
    members: members,
    memberNames: {
      'cap': 'Ava Brooks',
      'pat': 'Sam Ortiz',
      'director': 'Jo Director',
    },
    kind: kind,
  );

  FakeAuthRepository as(String uid) => FakeAuthRepository(
    user: AppUser(uid: uid, email: '$uid@x.com', displayName: 'Player $uid'),
  );

  void seedTeams() {
    teams = FakeTeamRepository();
    teams.teams['t1'] = team('t1', 'Northside Flyers', {
      'cap': TeamRole.owner,
      'pat': TeamRole.player,
    });
    teams.teams['t2'] = team('t2', 'State Ultimate', {'cap': TeamRole.owner});
    teams.teams['host'] = team('host', 'Front Range Ultimate', {
      'director': TeamRole.owner,
    }, kind: TeamKind.organization);
  }

  const divisionSummary = DivisionSummary(
    id: 'd1',
    division: Division.mixed,
    level: CompetitionLevel.club,
  );

  /// A live tournament: the user captains Northside Flyers.
  void seedLive() {
    repo = FakeHostedTournamentRepository();
    seedLiveTournament(repo, now: now, captains: ['cap']);
    repo.tournaments['x9'] = repo.tournaments['x9']!.copyWith(
      divisions: [divisionSummary],
    );
  }

  /// Registration open, with a fee and some applications.
  void seedRegistration() {
    repo = FakeHostedTournamentRepository();
    final start = today.add(const Duration(days: 30));
    repo.tournaments['r1'] = HostedTournament(
      id: 'r1',
      hostId: 'host',
      hostName: 'Front Range Ultimate',
      hostKind: TeamKind.organization,
      name: 'Spring Thaw Open',
      startsOn: start,
      endsOn: start.add(const Duration(days: 1)),
      location: 'Aurora Sports Park, Aurora, CO',
      description:
          'Two days of club ultimate on fields 1-4. Parking on the '
          'north lot; food trucks both days.',
      status: HostedStatus.registration,
      bidFee: BidFee(
        amountCents: 25000,
        currency: 'USD',
        instructions: 'Venmo @fru-treasurer',
        dueAt: start.subtract(const Duration(days: 14)),
      ),
      divisions: const [
        divisionSummary,
        DivisionSummary(
          id: 'd2',
          division: Division.women,
          level: CompetitionLevel.club,
        ),
      ],
    );
    repo.divisions['r1'] = {
      'd1': TournamentDivision(
        id: 'd1',
        division: Division.mixed,
        level: CompetitionLevel.club,
        settings: TournamentSettings(startsAt: start, fields: 4),
        seeds: const ['a1', 'a2', 'a3'],
      ),
      'd2': TournamentDivision(
        id: 'd2',
        division: Division.women,
        level: CompetitionLevel.club,
        settings: TournamentSettings(startsAt: start, fields: 4),
      ),
    };
    repo.entries['r1'] = {
      for (final (id, name, status) in [
        ('a1', 'Rocky Mountain Rage', EntryStatus.accepted),
        ('a2', 'Boulder Gold', EntryStatus.accepted),
        ('a3', 'Front Range Freight', EntryStatus.accepted),
        ('p1', 'Mesa', EntryStatus.applied),
        ('p2', 'Pikes Peak', EntryStatus.applied),
      ])
        id: TournamentEntry(
          teamId: id,
          teamName: name,
          divisionId: 'd1',
          status: status,
        ),
    };
  }

  /// A league on its third week, tonight.
  void seedLeague() {
    repo = FakeHostedTournamentRepository();
    final first = today.subtract(const Duration(days: 14));
    repo.tournaments['l1'] = HostedTournament(
      id: 'l1',
      hostId: 'host',
      hostName: 'Front Range Ultimate',
      name: 'Winter League',
      startsOn: first,
      endsOn: first.add(const Duration(days: 49)),
      location: 'Dome at City Park',
      status: HostedStatus.live,
      kind: HostedKind.league,
      season: const LeagueSeason(weeks: 8, playoffTeams: 4),
      divisions: const [divisionSummary],
    );
    final names = {
      't1': 'Northside Flyers',
      'me': 'Mesa',
      'bg': 'Boulder Gold',
      'pp': 'Pikes Peak',
    };
    repo.entries['l1'] = {
      for (final e in names.entries)
        e.key: TournamentEntry(
          teamId: e.key,
          teamName: e.value,
          divisionId: 'd1',
          status: EntryStatus.accepted,
          captainIds: e.key == 't1' ? const ['cap'] : const [],
        ),
    };
    repo.divisions['l1'] = {
      'd1': TournamentDivision(
        id: 'd1',
        division: Division.mixed,
        level: CompetitionLevel.league,
        settings: TournamentSettings(
          startsAt: DateTime(first.year, first.month, first.day, 18, 30),
          fields: 2,
        ),
        seeds: names.keys.toList(),
        captains: const {
          't1': ['cap'],
        },
      ),
    };
    var order = 0;
    GroupGame g(int week, String a, String b, int field, {int? sa, int? sb}) {
      final day = first.add(Duration(days: 7 * (week - 1)));
      return GroupGame(
        id: 'g${order + 1}',
        order: order++,
        stage: GameStage.pool,
        round: week,
        label: 'Week $week',
        field: field,
        startsAt: DateTime(day.year, day.month, day.day, 18, 30),
        teamA: a,
        teamB: b,
        status: sa == null ? GameStatus.scheduled : GameStatus.done,
        scoreA: sa,
        scoreB: sb,
      );
    }

    repo.games['l1/d1'] = [
      g(1, 't1', 'me', 1, sa: 13, sb: 9),
      g(1, 'bg', 'pp', 2, sa: 11, sb: 13),
      g(2, 't1', 'bg', 1, sa: 13, sb: 12),
      g(2, 'me', 'pp', 2, sa: 8, sb: 13),
      g(3, 't1', 'pp', 1),
      g(3, 'me', 'bg', 2),
    ];
  }

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
    await tester.pumpAndSettle();
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

  HostedTournamentViewModel page(String id, String uid) =>
      HostedTournamentViewModel(
        tournamentId: id,
        tournamentRepository: repo,
        teamRepository: teams,
        authRepository: as(uid),
        postRepository: FakeTeamPostRepository(),
        now: () => now,
      );

  Future<void> tabs(
    WidgetTester tester,
    String prefix,
    bool dark,
    List<String> labels,
  ) async {
    for (final label in labels) {
      final tab = find.descendant(
        of: find.byType(TabBar),
        matching: find.text(label),
      );
      if (tab.evaluate().isEmpty) continue;
      await tester.tap(tab);
      await tester.pumpAndSettle();
      await capture(tester, '$prefix-${label.toLowerCase()}', dark);
    }
  }

  const allTabs = [
    'Overview',
    'Teams',
    'Schedule',
    'Results',
    'Standings',
    'News',
  ];

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('live tournament ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      seedTeams();
      seedLive();
      final vm = page('x9', 'cap');
      await pump(tester, HostedTournamentScreen(viewModel: vm), dark: dark);
      await capture(tester, '01-live-landing', dark);
      await tabs(tester, '02-live', dark, allTabs);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    });

    testWidgets('score sheet ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      seedTeams();
      seedLive();
      final vm = page('x9', 'cap');
      await pump(
        tester,
        HostedTournamentScreen(
          viewModel: vm,
          openGameId: 'g3',
          openDivisionId: 'd1',
        ),
        dark: dark,
      );
      await capture(tester, '03-score-sheet', dark);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    });

    testWidgets('registration, as a team admin ($theme)', skip: skip != null, (
      tester,
    ) async {
      await setUpView(tester);
      seedTeams();
      seedRegistration();
      final vm = page('r1', 'cap');
      await pump(tester, HostedTournamentScreen(viewModel: vm), dark: dark);
      await capture(tester, '04-registration', dark);
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await capture(tester, '04-registration-scrolled', dark);
      final apply = find.text('Apply with a team').last;
      if (apply.evaluate().isNotEmpty) {
        await tester.ensureVisible(apply);
        await tester.tap(apply);
        await capture(tester, '05-enter-team', dark);
      }
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    });

    testWidgets('host view ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      seedTeams();
      seedRegistration();
      final vm = page('r1', 'director');
      await pump(tester, HostedTournamentScreen(viewModel: vm), dark: dark);
      await capture(tester, '06-host-overview', dark);
      await tabs(tester, '07-host', dark, ['Teams', 'Schedule']);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    });

    testWidgets('league ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      seedTeams();
      seedLeague();
      final vm = page('l1', 'cap');
      await pump(tester, HostedTournamentScreen(viewModel: vm), dark: dark);
      await capture(tester, '08-league-landing', dark);
      await tabs(tester, '09-league', dark, [
        'Overview',
        'Schedule',
        'Standings',
      ]);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    });

    testWidgets('form ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      seedTeams();
      repo = FakeHostedTournamentRepository();
      final form = HostedTournamentFormViewModel(
        hostId: 'host',
        tournamentRepository: repo,
        teamRepository: teams,
        authRepository: as('director'),
        type: HostedType.tournament,
      );
      await pump(
        tester,
        HostedTournamentFormScreen(viewModel: form),
        dark: dark,
      );
      await capture(tester, '10-form', dark);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await capture(tester, '10-form-scrolled', dark);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await capture(tester, '10-form-scrolled2', dark);
      await tester.pumpWidget(const SizedBox());
      form.dispose();
    });

    testWidgets('host chooser ($theme)', skip: skip != null, (tester) async {
      await setUpView(tester);
      seedTeams();
      teams.teams['g1'] = team('g1', 'Denver Thursday Pickup', {
        'director': TeamRole.owner,
      }, kind: TeamKind.community);
      final vm = HostEventViewModel(
        teamRepository: teams,
        authRepository: as('director'),
      );
      await pump(tester, HostEventScreen(viewModel: vm), dark: dark);
      await capture(tester, '11-host-chooser', dark);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    });

    testWidgets('team tournaments ($theme)', skip: skip != null, (
      tester,
    ) async {
      await setUpView(tester);
      seedTeams();
      seedLive();
      final start = today.add(const Duration(days: 30));
      repo.entered['t1'] = [
        ...repo.entered['t1']!,
        EnteredTournament(
          tournamentId: 'r1',
          name: 'Spring Thaw Open',
          status: EntryStatus.applied,
          startsOn: start,
          endsOn: start.add(const Duration(days: 1)),
          location: 'Aurora',
          hostName: 'Front Range Ultimate',
        ),
      ];
      repo.tournaments['h1'] = HostedTournament(
        id: 'h1',
        hostId: 't1',
        hostName: 'Northside Flyers',
        name: 'Flyers Summer Hat',
        startsOn: start.add(const Duration(days: 60)),
        entryType: TournamentEntryType.players,
      );
      final vm = HostedTournamentsViewModel(
        hostId: 't1',
        tournamentRepository: repo,
        teamRepository: teams,
        authRepository: as('cap'),
      );
      final days = TournamentDays(
        repository: repo,
        teams: Stream.value([teams.teams['t1']!]),
        uid: 'cap',
        clock: () => now,
      );
      await pump(
        tester,
        Scaffold(
          appBar: AppBar(title: const Text('Northside Flyers')),
          body: Column(
            children: [
              ListenableBuilder(
                listenable: days,
                builder: (context, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: days.days.isEmpty
                      ? const SizedBox()
                      : TournamentDayCard(
                          day: days.days.first,
                          showTeam: false,
                        ),
                ),
              ),
              Expanded(child: HostedTournamentsSection(viewModel: vm)),
            ],
          ),
        ),
        dark: dark,
      );
      await capture(tester, '12-team-tournaments', dark);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      days.dispose();
    });
  }
}
