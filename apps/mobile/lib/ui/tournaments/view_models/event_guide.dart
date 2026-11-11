import 'package:intl/intl.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/live_draft.dart';
import 'hosted_tournament_viewmodel.dart';
import 'player_signups_viewmodel.dart';

/// Something the event page can do for the user from its guide: open a
/// dialog, change the status, jump to a tab or open a screen.
enum GuideAction {
  addDivision,
  openRegistration,
  closeRegistration,

  /// The Players tab (signups to review).
  reviewPlayers,

  /// The Teams tab (applications to review, seeds).
  reviewTeams,

  /// The balanced team draft for a division.
  draftTeams,

  /// The captains' live draft for a division.
  captainsDraft,
  createTeams,

  /// The Schedule tab, on a division, to publish it.
  publishSchedule,
  signUp,
  apply,

  /// Start a team and reserve it a spot (events taking players and teams).
  reserveTeam,
  acceptInvite,

  /// The captains' draft the user is in.
  watchDraft,

  /// The Schedule tab.
  schedule,

  /// The Results (Standings) tab.
  results,
}

/// A button in the guide. [divisionId] says which division it's for.
typedef GuideButton = ({String label, GuideAction action, String? divisionId});

GuideButton _button(String label, GuideAction action, [String? divisionId]) =>
    (label: label, action: action, divisionId: divisionId);

enum GuideStepState { done, current, todo }

/// One step of the host's setup checklist.
class GuideStep {
  const GuideStep({
    required this.title,
    required this.detail,
    required this.state,
    this.button,
    this.secondary,
  });

  final String title;
  final String detail;
  final GuideStepState state;
  final GuideButton? button;
  final GuideButton? secondary;
}

/// What the event page tells this user up top: where things stand for
/// them and the one thing to do next. Hosts also get the [steps] from
/// setup to final.
class EventGuide {
  const EventGuide({
    required this.eyebrow,
    required this.title,
    required this.body,
    this.button,
    this.secondary,
    this.steps = const [],
    this.needsYou = false,
  });

  final String eyebrow;
  final String title;
  final String body;
  final GuideButton? button;
  final GuideButton? secondary;
  final List<GuideStep> steps;

  /// The user has something to do now (highlighted).
  final bool needsYou;

  /// The guide for whoever is looking: the host's checklist, a player's or
  /// team's own status, or what a visitor can follow.
  static EventGuide of(
    HostedTournamentViewModel vm,
    PlayerSignupsViewModel? signups,
  ) {
    final t = vm.tournament!;
    if (vm.isManager) return _host(vm, signups, t);
    final mine = _mine(vm, signups, t);
    return mine ?? _visitor(vm, t);
  }

  // ---- Host ---------------------------------------------------------------

  static EventGuide _host(
    HostedTournamentViewModel vm,
    PlayerSignupsViewModel? signups,
    HostedTournament t,
  ) {
    final players = t.takesPlayers;
    final divisions = vm.divisions;
    final status = t.status;
    final after = status.index >= HostedStatus.seeding.index;
    final noun = players ? 'players' : 'teams';

    final all = signups?.signups ?? const <PlayerSignup>[];
    final pendingPlayers = players
        ? all.where((s) => s.status == SignupStatus.applied).length
        : 0;
    final pendingTeams = t.takesTeams
        ? vm.entriesWith(EntryStatus.applied).length
        : 0;
    final pending = pendingPlayers + pendingTeams;
    final accepted = players
        ? all.where((s) => s.status == SignupStatus.accepted).length
        : vm.entriesWith(EntryStatus.accepted).length;
    final review = players && (pendingPlayers > 0 || pendingTeams == 0)
        ? GuideAction.reviewPlayers
        : GuideAction.reviewTeams;

    // 1. Divisions.
    final hasDivisions = divisions.isNotEmpty;
    final divisionsStep = GuideStep(
      title: hasDivisions ? 'Divisions' : 'Add a division',
      detail: hasDivisions
          ? divisions.map((d) => d.label).join(', ')
          : 'Each division has its own ${players ? 'players' : 'teams'}, '
                'teams and schedule, e.g. Club Mixed.',
      state: hasDivisions ? GuideStepState.done : GuideStepState.current,
      button: hasDivisions
          ? null
          : _button('Add a division', GuideAction.addDivision),
    );

    // 2. Registration.
    final GuideStep registration;
    switch (status) {
      case HostedStatus.draft:
        registration = GuideStep(
          title: 'Open registration',
          detail:
              'Only your organizers can see this event. Publishing it lets '
              '${players
                  ? 'players sign up'
                  : t.visibility == TournamentVisibility.inviteOnly
                  ? 'you invite teams'
                  : 'teams apply'}.',
          state: hasDivisions ? GuideStepState.current : GuideStepState.todo,
          button: hasDivisions
              ? _button(
                  'Publish and open registration',
                  GuideAction.openRegistration,
                )
              : null,
        );
      case HostedStatus.registration:
        registration = GuideStep(
          title: 'Registration is open',
          detail: [
            if (pending > 0) '$pending waiting for you',
            '$accepted ${accepted == 1 ? noun.substring(0, noun.length - 1) : noun} accepted',
          ].join(' · '),
          state: GuideStepState.current,
          button: pending > 0
              ? _button('Review $pending', review)
              : _button('Close registration', GuideAction.closeRegistration),
          secondary: pending > 0
              ? _button('Close registration', GuideAction.closeRegistration)
              : _button(players ? 'See players' : 'See teams', review),
        );
      default:
        registration = GuideStep(
          title: 'Registration closed',
          detail:
              '$accepted ${accepted == 1 ? noun.substring(0, noun.length - 1) : noun} accepted',
          state: GuideStepState.done,
          secondary: status == HostedStatus.seeding
              ? _button('Reopen', GuideAction.openRegistration)
              : null,
        );
    }

    // 3. Teams.
    final GuideStep teams;
    if (players) {
      // Where teams also reserve spots, only divisions with players who
      // signed up on their own need a draft.
      final undrafted = [
        for (final d in divisions)
          if (d.teams.isEmpty &&
              (!t.mixedEntry ||
                  all.any(
                    (s) =>
                        s.divisionId == d.id &&
                        s.status == SignupStatus.accepted,
                  )))
            d,
      ];
      final uncreated = t.isLeague
          ? [
              for (final d in divisions)
                if (d.teams.isNotEmpty && !d.teamsCreated) d,
            ]
          : const <TournamentDivision>[];
      final done = hasDivisions && undrafted.isEmpty && uncreated.isEmpty;
      final captains = t.draftMode == DraftMode.captains;
      final next = undrafted.firstOrNull;
      final create = uncreated.firstOrNull;
      final many = divisions.length > 1;
      teams = GuideStep(
        title: captains ? "Run the captains' draft" : 'Draft the teams',
        detail: done
            ? '${divisions.fold(0, (n, d) => n + d.teams.length)} teams'
                  '${t.isLeague ? ', each a real team with chat' : ''}'
            : next != null
            ? captains
                  ? 'Pick captains from your accepted players; they take '
                        'turns choosing their teams.'
                  : 'The app deals even teams from skill and gender; you '
                        'can move players after.'
            : 'Turn the drafted teams into real teams, each with chat, '
                  'a roster and its games on its schedule.',
        state: done
            ? GuideStepState.done
            : after
            ? GuideStepState.current
            : GuideStepState.todo,
        button: !after || done
            ? null
            : next != null
            ? _button(
                captains
                    ? "Start the captains' draft${many ? ' · ${next.label}' : ''}"
                    : 'Draft teams${many ? ' · ${next.label}' : ''}',
                captains ? GuideAction.captainsDraft : GuideAction.draftTeams,
                next.id,
              )
            : _button(
                "Create the league's teams${many ? ' · ${create!.label}' : ''}",
                GuideAction.createTeams,
                create!.id,
              ),
      );
    } else {
      final unseeded = [
        for (final d in divisions)
          if (d.seeds.isEmpty) d,
      ];
      final done = hasDivisions && unseeded.isEmpty;
      teams = GuideStep(
        title: 'Seed the teams',
        detail: done
            ? 'Every division is seeded.'
            : 'Put each division\'s accepted teams in order, strongest first.',
        state: done
            ? GuideStepState.done
            : after
            ? GuideStepState.current
            : GuideStepState.todo,
        button: after && !done
            ? _button('Seed teams', GuideAction.reviewTeams)
            : null,
      );
    }

    // 4. Schedule.
    final unpublished = [
      for (final d in divisions)
        if (!vm.publishedIn(d.id)) d,
    ];
    final scheduleDone = hasDivisions && unpublished.isEmpty;
    final ready = teams.state == GuideStepState.done;
    final many = divisions.length > 1;
    final schedule = GuideStep(
      title: 'Publish the schedule',
      detail: scheduleDone
          ? 'Every division\'s games are out.'
          : t.isLeague
          ? 'Weekly games for the season, then the playoffs.'
          : 'Games, fields and times, generated for you.',
      state: scheduleDone
          ? GuideStepState.done
          : ready
          ? GuideStepState.current
          : GuideStepState.todo,
      button: ready && !scheduleDone
          ? _button(
              'Publish the schedule${many ? ' · ${unpublished.first.label}' : ''}',
              GuideAction.publishSchedule,
              unpublished.first.id,
            )
          : null,
    );

    // 5. Play.
    final finished = status == HostedStatus.finished;
    final playing =
        status == HostedStatus.scheduled || status == HostedStatus.live;
    final play = GuideStep(
      title: finished ? 'Final' : 'Play the games',
      detail: finished
          ? 'Results stay up for everyone.'
          : 'Captains report scores and standings update as they do. '
                'It turns final when every division has its results.',
      state: finished
          ? GuideStepState.done
          : playing && scheduleDone
          ? GuideStepState.current
          : GuideStepState.todo,
      button: finished
          ? _button('See results', GuideAction.results)
          : playing
          ? _button('Open the schedule', GuideAction.schedule)
          : null,
    );

    final steps = [divisionsStep, registration, teams, schedule, play];
    final current =
        steps.where((s) => s.state == GuideStepState.current).firstOrNull ??
        (finished ? play : null);
    return EventGuide(
      eyebrow: finished ? 'All done' : 'Next step',
      title: current?.title ?? 'Waiting on your teams',
      body: current?.detail ?? 'Close registration when you\'re ready.',
      button: current?.button,
      secondary: current?.secondary,
      steps: steps,
      needsYou: current != null && !finished,
    );
  }

  // ---- A player or a team in it -------------------------------------------

  static EventGuide? _mine(
    HostedTournamentViewModel vm,
    PlayerSignupsViewModel? signups,
    HostedTournament t,
  ) {
    final fee = t.entryFee;
    final owes = fee != null && fee.amountCents > 0;

    // On a team (drafted, or an accepted team): their next game.
    final teamId = vm.myTeamIds.firstOrNull;
    if (teamId != null) {
      final name = vm.teamName(teamId);
      final draft = signups?.myDraft;
      if (draft != null && draft.status != DraftStatus.finished) {
        return _draft(vm, draft, signups!);
      }
      final next = vm.myNextGame;
      if (next != null) {
        final mine = vm.myTeamIn(next);
        final other = mine == next.teamA ? next.teamB : next.teamA;
        final action = vm.actionFor(next);
        final when = next.startsAt == null
            ? null
            : DateFormat('EEE MMM d · h:mm a').format(next.startsAt!);
        return EventGuide(
          eyebrow: 'Your team · $name',
          title: 'Next: vs ${vm.teamName(other)}',
          body: [?when, 'Field ${next.field}'].join(' · '),
          button: switch (action) {
            HostedGameAction.report => _button(
              'Report the score',
              GuideAction.schedule,
            ),
            HostedGameAction.confirm => _button(
              'Confirm the score',
              GuideAction.schedule,
            ),
            _ => _button('See the schedule', GuideAction.schedule),
          },
          needsYou:
              action == HostedGameAction.report ||
              action == HostedGameAction.confirm,
        );
      }
      if (t.status == HostedStatus.finished) {
        return EventGuide(
          eyebrow: 'Your team · $name',
          title: "That's a wrap",
          body: 'See how everyone finished.',
          button: _button('See results', GuideAction.results),
        );
      }
      return EventGuide(
        eyebrow: 'Your team',
        title: "You're on $name",
        body: vm.publishedIn(vm.myDivisionId ?? '')
            ? 'No more games to play.'
            : 'Your games show here once the host publishes the schedule.',
      );
    }

    // Someone on a registered team follows their team, not a signup.
    if (t.takesPlayers &&
        signups != null &&
        !(t.mixedEntry && vm.myActiveEntry != null)) {
      final s = signups.mine;
      final open =
          t.status.acceptsEntries &&
          t.visibility == TournamentVisibility.public &&
          vm.divisions.isNotEmpty;
      final paid = signups.isPaid(signups.uid);
      final payNote = owes && !paid
          ? ' Pay the ${fee.label} entry fee to the host'
                '${fee.instructions.isEmpty ? '' : ': ${fee.instructions}'}.'
          : '';
      switch (s?.status) {
        case null || SignupStatus.withdrawn:
          if (!open) return null;
          return EventGuide(
            eyebrow: t.isLeague ? 'Join the league' : 'Play in it',
            title: 'Sign up to play',
            body: t.draftMode == DraftMode.captains
                ? 'Sign up on your own; captains chosen by the host draft '
                      'the teams.'
                : 'Sign up on your own; the host builds balanced teams from '
                      'everyone who signs up.',
            button: _button(
              owes ? 'Sign up · ${fee.label}' : 'Sign up',
              GuideAction.signUp,
            ),
            secondary: vm.canReserve
                ? _button(
                    t.spotFee == null
                        ? 'Or reserve a spot for your team'
                        : 'Or reserve a spot for your team · '
                              '${t.spotFee!.label}',
                    GuideAction.reserveTeam,
                  )
                : null,
            needsYou: true,
          );
        case SignupStatus.applied:
          return EventGuide(
            eyebrow: 'Your signup',
            title: "You're signed up",
            body: 'The host reviews signups and accepts players.$payNote',
          );
        case SignupStatus.waitlisted:
          return const EventGuide(
            eyebrow: 'Your signup',
            title: "You're on the waitlist",
            body: "The host will accept you if a spot opens.",
          );
        case SignupStatus.declined:
          return const EventGuide(
            eyebrow: 'Your signup',
            title: "Your signup wasn't accepted",
            body: 'Follow the event for its schedule and results.',
          );
        case SignupStatus.accepted:
          final draft = signups.myDraft;
          if (draft != null && draft.status != DraftStatus.finished) {
            return _draft(vm, draft, signups);
          }
          return EventGuide(
            eyebrow: 'Your signup',
            title: "You're in",
            body:
                '${t.draftMode == DraftMode.captains ? 'Captains draft the teams' : 'The host drafts the teams'} '
                'after registration closes.$payNote',
            needsYou: payNote.isNotEmpty,
          );
      }
    }

    if (t.takesTeams) {
      final entries = vm.myEntries;
      final invite = entries
          .where((e) => e.status == EntryStatus.invited)
          .firstOrNull;
      if (invite != null && t.status.acceptsEntries) {
        return EventGuide(
          eyebrow: invite.teamName,
          title: "You're invited",
          body: 'Accept to enter ${invite.teamName} and pick its captains.',
          button: _button('Accept invite', GuideAction.acceptInvite),
          needsYou: true,
        );
      }
      final applied = entries
          .where(
            (e) =>
                e.status == EntryStatus.applied ||
                e.status == EntryStatus.waitlisted,
          )
          .firstOrNull;
      if (applied != null) {
        final short = vm.playersShort(applied.teamId) ?? 0;
        return EventGuide(
          eyebrow: applied.teamName,
          title: applied.status == EntryStatus.waitlisted
              ? 'On the waitlist'
              : t.mixedEntry
              ? 'Spot reserved'
              : 'Applied',
          body:
              'The host reviews applications and accepts teams.'
              '${short > 0 ? ' Invite $short more ${short == 1 ? 'player' : 'players'} to reach the roster minimum.' : ''}',
          needsYou: short > 0,
        );
      }
      if (vm.canApply) {
        final min = vm.divisions
            .map((d) => d.effectiveMinRoster)
            .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
        return EventGuide(
          eyebrow: t.isLeague ? 'Join the league' : 'Enter a team',
          title: 'Bring your team',
          body:
              'Apply with a team you manage'
              '${min == null ? '' : '; it needs at least $min players on its roster'}.',
          button: _button('Apply with a team', GuideAction.apply),
          needsYou: true,
        );
      }
    }
    return null;
  }

  static EventGuide _draft(
    HostedTournamentViewModel vm,
    LiveDraft draft,
    PlayerSignupsViewModel signups,
  ) {
    final uid = signups.uid;
    final captain = draft.captains.any((c) => c.uid == uid);
    final myTurn = draft.running && draft.onTheClock == uid;
    return EventGuide(
      eyebrow: "Captains' draft",
      title: myTurn
          ? "It's your pick"
          : captain
          ? "You're a captain"
          : 'The draft is live',
      body: switch (draft.status) {
        DraftStatus.paused => 'The host paused the draft.',
        DraftStatus.done => 'Every player is picked; the host finishes it.',
        _ when myTurn => 'Choose a player for your team.',
        _ => '${draft.nameOf(draft.onTheClock ?? '')} is picking.',
      },
      button: _button(
        myTurn ? 'Make your pick' : 'Open the draft',
        GuideAction.watchDraft,
        draft.divisionId,
      ),
      needsYou: myTurn,
    );
  }

  // ---- Everyone else ------------------------------------------------------

  static EventGuide _visitor(HostedTournamentViewModel vm, HostedTournament t) {
    return switch (t.status) {
      HostedStatus.draft || HostedStatus.registration => EventGuide(
        eyebrow: t.status.label,
        title: t.visibility == TournamentVisibility.inviteOnly
            ? 'Invite only'
            : t.takesPlayers
            ? 'Signups open soon'
            : 'Teams are registering',
        body: t.visibility == TournamentVisibility.inviteOnly
            ? 'Teams the host invites play. Follow along for the schedule '
                  'and results.'
            : t.takesPlayers
            ? 'Follow to hear when signups open.'
            : 'Team admins apply here. Follow to hear when the schedule '
                  'is out.',
      ),
      HostedStatus.seeding => const EventGuide(
        eyebrow: 'Registration closed',
        title: 'The schedule is coming',
        body: 'Follow to hear when it\'s out.',
      ),
      HostedStatus.scheduled || HostedStatus.live => EventGuide(
        eyebrow: t.status == HostedStatus.live ? 'Live' : 'Scheduled',
        title: t.status == HostedStatus.live
            ? 'Games are on'
            : 'Schedule is out',
        body: 'Scores and standings update as captains report them.',
        button: _button('See the schedule', GuideAction.schedule),
      ),
      HostedStatus.finished => EventGuide(
        eyebrow: 'Final',
        title: vm.championId == null
            ? 'Results are in'
            : '${vm.teamName(vm.championId)} won',
        body: 'See how every team finished.',
        button: _button('See results', GuideAction.results),
      ),
    };
  }
}
