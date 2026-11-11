import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/live_draft.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/tournaments/view_models/event_guide.dart';
import 'package:frisbee_app/ui/tournaments/view_models/hosted_tournament_viewmodel.dart';
import 'package:frisbee_app/ui/tournaments/view_models/player_signups_viewmodel.dart';

import '../testing/fakes.dart';
import '../testing/hosted_tournament_fakes.dart';

/// What the top of an event page tells each kind of user at each stage.
void main() {
  late FakeTeamRepository teams;
  late FakeHostedTournamentRepository repo;
  const id = 'e1';
  const div = 'd1';

  Team team(String id, String owner, {TeamKind kind = TeamKind.team}) => Team(
    id: id,
    name: 'Team $id',
    division: Division.mixed,
    level: CompetitionLevel.club,
    ownerId: owner,
    members: {owner: TeamRole.owner},
    memberNames: {owner: 'Name $owner'},
    kind: kind,
  );

  setUp(() {
    teams = FakeTeamRepository();
    repo = FakeHostedTournamentRepository();
    teams.teams['host'] = team('host', 'director', kind: TeamKind.organization);
  });

  /// An event with one Club Mixed division (unless [noDivision]).
  void event({
    HostedStatus status = HostedStatus.registration,
    TournamentEntryType entry = TournamentEntryType.players,
    HostedKind kind = HostedKind.tournament,
    DraftMode draft = DraftMode.balanced,
    bool noDivision = false,
    List<TournamentTeam> drafted = const [],
    List<String> seeds = const [],
  }) {
    final d = TournamentDivision(
      id: div,
      division: Division.mixed,
      level: CompetitionLevel.club,
      settings: TournamentSettings(startsAt: DateTime(2027, 6, 3, 19)),
      teams: drafted,
      seeds: seeds,
    );
    repo.tournaments[id] = HostedTournament(
      id: id,
      hostId: 'host',
      hostName: 'Stall 10',
      name: 'Thursday Night',
      startsOn: DateTime(2027, 6, 3),
      status: status,
      entryType: entry,
      kind: kind,
      draftMode: draft,
      bidFee: const BidFee(amountCents: 2000),
      divisions: noDivision ? const [] : [d.summary],
    );
    if (!noDivision) repo.divisions[id] = {div: d};
  }

  void signUp(String uid, SignupStatus status) =>
      repo.signups.putIfAbsent(id, () => {})[uid] = PlayerSignup(
        uid: uid,
        name: 'Player $uid',
        divisionId: div,
        status: status,
      );

  Future<EventGuide> guideFor(String uid) async {
    final auth = FakeAuthRepository(
      user: AppUser(uid: uid, email: '$uid@x.com', displayName: uid),
    );
    final vm = HostedTournamentViewModel(
      tournamentId: id,
      tournamentRepository: repo,
      teamRepository: teams,
      authRepository: auth,
    );
    final signups = PlayerSignupsViewModel(
      tournamentId: id,
      tournamentRepository: repo,
      authRepository: auth,
    );
    await pumpEventQueue();
    signups.setManager(vm.isManager);
    await pumpEventQueue();
    final guide = EventGuide.of(vm, signups);
    addTearDown(vm.dispose);
    addTearDown(signups.dispose);
    return guide;
  }

  GuideStepState stateOf(EventGuide g, String title) =>
      g.steps.firstWhere((s) => s.title == title).state;

  group('the host', () {
    test('adds a division first', () async {
      event(status: HostedStatus.draft, noDivision: true);
      final g = await guideFor('director');
      expect(g.title, 'Add a division');
      expect(g.button?.action, GuideAction.addDivision);
      expect(g.steps, hasLength(5));
      expect(stateOf(g, 'Open registration'), GuideStepState.todo);
    });

    test('then publishes to open registration', () async {
      event(status: HostedStatus.draft);
      final g = await guideFor('director');
      expect(g.title, 'Open registration');
      expect(g.button?.action, GuideAction.openRegistration);
      expect(stateOf(g, 'Divisions'), GuideStepState.done);
    });

    test('reviews waiting signups, or closes registration', () async {
      event();
      signUp('p1', SignupStatus.applied);
      signUp('p2', SignupStatus.applied);
      signUp('p3', SignupStatus.accepted);
      var g = await guideFor('director');
      expect(g.title, 'Registration is open');
      expect(g.body, '2 waiting for you · 1 player accepted');
      expect(g.button?.label, 'Review 2');
      expect(g.button?.action, GuideAction.reviewPlayers);
      expect(g.secondary?.action, GuideAction.closeRegistration);

      repo.signups[id]!.clear();
      g = await guideFor('director');
      expect(g.button?.action, GuideAction.closeRegistration);
    });

    test('drafts teams once registration closes', () async {
      event(status: HostedStatus.seeding);
      var g = await guideFor('director');
      expect(g.title, 'Draft the teams');
      expect(g.button?.action, GuideAction.draftTeams);
      expect(g.button?.divisionId, div);
      expect(stateOf(g, 'Registration closed'), GuideStepState.done);

      event(status: HostedStatus.seeding, draft: DraftMode.captains);
      g = await guideFor('director');
      expect(g.title, "Run the captains' draft");
      expect(g.button?.action, GuideAction.captainsDraft);
    });

    test("a league creates its real teams, then publishes", () async {
      const drafted = [
        TournamentTeam(
          id: 'team1',
          name: 'Reds',
          captainId: 'p1',
          playerIds: ['p1'],
        ),
        TournamentTeam(
          id: 'team2',
          name: 'Blues',
          captainId: 'p2',
          playerIds: ['p2'],
        ),
      ];
      event(
        status: HostedStatus.seeding,
        kind: HostedKind.league,
        drafted: drafted,
        seeds: ['team1', 'team2'],
      );
      var g = await guideFor('director');
      expect(g.button?.action, GuideAction.createTeams);

      final made = [
        for (final t in drafted)
          TournamentTeam(
            id: 'league_${id}_${t.id}',
            name: t.name,
            captainId: t.captainId,
            playerIds: t.playerIds,
          ),
      ];
      event(
        status: HostedStatus.seeding,
        kind: HostedKind.league,
        drafted: made,
        seeds: [for (final t in made) t.id],
      );
      g = await guideFor('director');
      expect(g.title, 'Publish the schedule');
      expect(g.button?.action, GuideAction.publishSchedule);
      expect(g.button?.divisionId, div);
    });

    test('teams that applied are seeded', () async {
      event(status: HostedStatus.seeding, entry: TournamentEntryType.teams);
      final g = await guideFor('director');
      expect(g.title, 'Seed the teams');
      expect(g.button?.action, GuideAction.reviewTeams);
    });

    test('opens the schedule while games are on', () async {
      event(
        status: HostedStatus.live,
        entry: TournamentEntryType.teams,
        seeds: ['a', 'b'],
      );
      repo.games['$id/$div'] = [
        const GroupGame(
          id: 'g1',
          order: 0,
          stage: GameStage.pool,
          round: 1,
          label: 'Round 1',
          teamA: 'a',
          teamB: 'b',
        ),
      ];
      final g = await guideFor('director');
      expect(g.title, 'Play the games');
      expect(g.button?.action, GuideAction.schedule);
      expect(stateOf(g, 'Publish the schedule'), GuideStepState.done);
    });
  });

  group('a player', () {
    test('is asked to sign up while registration is open', () async {
      event();
      final g = await guideFor('pat');
      expect(g.title, 'Sign up to play');
      expect(g.button?.label, r'Sign up · $20');
      expect(g.needsYou, isTrue);
    });

    test('sees where their signup stands', () async {
      event();
      signUp('pat', SignupStatus.applied);
      expect((await guideFor('pat')).title, "You're signed up");
      signUp('pat', SignupStatus.waitlisted);
      expect((await guideFor('pat')).title, "You're on the waitlist");
      signUp('pat', SignupStatus.accepted);
      final g = await guideFor('pat');
      expect(g.title, "You're in");
      expect(g.body, contains(r'Pay the $20 entry fee'));
    });

    test('is sent to the draft while it runs', () async {
      event(status: HostedStatus.seeding, draft: DraftMode.captains);
      signUp('pat', SignupStatus.accepted);
      signUp('cap', SignupStatus.accepted);
      repo.drafts['$id/$div'] = const LiveDraft(
        divisionId: div,
        status: DraftStatus.live,
        captains: [
          DraftCaptain(uid: 'cap', name: 'Cap'),
          DraftCaptain(uid: 'other', name: 'Other'),
        ],
        pool: {'pat': 'Pat', 'x': 'X'},
      );
      var g = await guideFor('pat');
      expect(g.title, 'The draft is live');
      expect(g.body, 'Cap is picking.');
      expect(g.button?.action, GuideAction.watchDraft);
      g = await guideFor('cap');
      expect(g.title, "It's your pick");
      expect(g.needsYou, isTrue);
    });

    test('on a team sees their next game and reports it', () async {
      event(
        status: HostedStatus.scheduled,
        drafted: const [
          TournamentTeam(
            id: 'reds',
            name: 'Reds',
            captainId: 'pat',
            playerIds: ['pat'],
          ),
          TournamentTeam(
            id: 'blues',
            name: 'Blues',
            captainId: 'bo',
            playerIds: ['bo'],
          ),
        ],
        seeds: ['reds', 'blues'],
      );
      repo.divisions[id] = {
        div: repo.divisions[id]![div]!.copyWith(
          captains: {
            'reds': ['pat'],
            'blues': ['bo'],
          },
        ),
      };
      signUp('pat', SignupStatus.accepted);
      repo.games['$id/$div'] = [
        GroupGame(
          id: 'g1',
          order: 0,
          stage: GameStage.pool,
          round: 1,
          label: 'Week 1',
          field: 2,
          startsAt: DateTime(2027, 6, 3, 19),
          teamA: 'reds',
          teamB: 'blues',
        ),
      ];
      final g = await guideFor('pat');
      expect(g.eyebrow, 'Your team · Reds');
      expect(g.title, 'Next: vs Blues');
      expect(g.body, contains('Field 2'));
      expect(g.button?.label, 'Report the score');
      expect(g.needsYou, isTrue);
    });
  });

  group('a team admin', () {
    test('is asked to apply with a team', () async {
      event(entry: TournamentEntryType.teams);
      teams.teams['mine'] = team('mine', 'cap');
      final g = await guideFor('cap');
      expect(g.title, 'Bring your team');
      expect(g.button?.action, GuideAction.apply);
    });
  });

  group('a visitor', () {
    test('follows along, then sees the results', () async {
      event(status: HostedStatus.live, entry: TournamentEntryType.teams);
      var g = await guideFor('fan');
      expect(g.title, 'Games are on');
      expect(g.button?.action, GuideAction.schedule);
      expect(g.steps, isEmpty);
      event(status: HostedStatus.finished, entry: TournamentEntryType.teams);
      g = await guideFor('fan');
      expect(g.button?.action, GuideAction.results);
    });
  });
}
