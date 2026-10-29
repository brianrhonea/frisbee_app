import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_detail_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_editor_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/view_models/my_event_detail_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeEventRepository events;
  final auth = FakeAuthRepository(user: testUser);

  const poll = EventPoll(
    question: 'Jerseys?',
    options: [
      PollOption(id: 'a', text: 'Dark'),
      PollOption(id: 'b', text: 'Light'),
    ],
  );

  setUp(() {
    teams = FakeTeamRepository();
    events = FakeEventRepository();
    teams.teams['t1'] = teamWith({
      'owner': TeamRole.owner,
      'u1': TeamRole.player,
      'u2': TeamRole.player,
    });
    events.events['e1'] = TeamEvent(
      id: 'e1',
      title: 'Practice',
      startsAt: DateTime(2026, 11, 2, 18),
      poll: poll,
      rsvps: const {'owner': RsvpStatus.going},
    );
  });

  EventDetailViewModel detail() => EventDetailViewModel(
    teamId: 't1',
    eventId: 'e1',
    eventRepository: events,
    teamRepository: teams,
    authRepository: auth,
  );

  group('EventDetailViewModel', () {
    test('RSVP updates my status and the no-reply list', () async {
      final vm = detail();
      await pumpEventQueue();
      expect(vm.canEdit, isFalse);
      expect(vm.myRsvp, isNull);
      expect(vm.noResponse, hasLength(2));

      await vm.setRsvp.execute(RsvpStatus.maybe);
      await pumpEventQueue();
      expect(vm.myRsvp, RsvpStatus.maybe);
      expect(vm.noResponse, hasLength(1));

      await vm.setRsvp.execute(null);
      await pumpEventQueue();
      expect(vm.myRsvp, isNull);
    });

    test('only attendees can react or vote', () async {
      final vm = detail();
      await pumpEventQueue();
      await vm.toggleReaction.execute(Reaction.fire);
      expect(vm.toggleReaction.error, isTrue);
      await vm.vote.execute('a');
      expect(vm.vote.error, isTrue);
      expect(events.events['e1']!.reactions, isEmpty);
    });

    test('leaving "going" drops my reactions and votes', () async {
      final vm = detail();
      await pumpEventQueue();
      await vm.setRsvp.execute(RsvpStatus.going);
      await pumpEventQueue();
      await vm.toggleReaction.execute(Reaction.fire);
      await vm.vote.execute('a');
      await pumpEventQueue();
      await vm.setRsvp.execute(RsvpStatus.maybe);
      await pumpEventQueue();
      expect(vm.myReactions, isEmpty);
      expect(events.events['e1']!.votes.containsKey('u1'), isFalse);
    });

    test('reactions toggle', () async {
      final vm = detail();
      await pumpEventQueue();
      await vm.setRsvp.execute(RsvpStatus.going);
      await pumpEventQueue();
      await vm.toggleReaction.execute(Reaction.fire);
      await pumpEventQueue();
      expect(vm.myReactions, {Reaction.fire});
      expect(vm.reactions[Reaction.fire], hasLength(1));

      await vm.toggleReaction.execute(Reaction.fire);
      await pumpEventQueue();
      expect(vm.myReactions, isEmpty);
      expect(vm.reactions, isEmpty);
    });

    test(
      'single-choice polls replace the vote; tapping again clears it',
      () async {
        final vm = detail();
        await pumpEventQueue();
        await vm.setRsvp.execute(RsvpStatus.going);
        await pumpEventQueue();
        await vm.vote.execute('a');
        await pumpEventQueue();
        await vm.vote.execute('b');
        await pumpEventQueue();
        expect(events.events['e1']!.votes['u1'], ['b']);
        expect(vm.pollTally.map((t) => t.mine), [false, true]);

        await vm.vote.execute('b');
        await pumpEventQueue();
        expect(events.events['e1']!.votes.containsKey('u1'), isFalse);
      },
    );

    test('multi-choice polls accumulate votes', () async {
      events.events['e1'] = events.events['e1']!.copyWith(
        poll: () => const EventPoll(
          question: 'Which days?',
          options: [
            PollOption(id: 'a', text: 'Sat'),
            PollOption(id: 'b', text: 'Sun'),
          ],
          multiple: true,
        ),
      );
      final vm = detail();
      await pumpEventQueue();
      await vm.setRsvp.execute(RsvpStatus.going);
      await pumpEventQueue();
      await vm.vote.execute('a');
      await pumpEventQueue();
      await vm.vote.execute('b');
      await pumpEventQueue();
      expect(events.events['e1']!.votes['u1'], ['a', 'b']);
    });
  });

  group('EventEditorViewModel', () {
    EventEditorViewModel editor(
      String? id, {
      DateTime? day,
      String? teamId = 't1',
    }) => EventEditorViewModel(
      teamId: teamId,
      eventId: id,
      eventRepository: events,
      teamRepository: teams,
      authRepository: auth,
      initialDay: day,
    );

    test('players can only add events to their own schedule', () async {
      final vm = editor(null);
      await pumpEventQueue();
      expect(vm.editableTeams, isEmpty);
      expect(vm.canChooseSchedule, isFalse);
      expect(vm.isPersonal, isTrue);
      await vm.save.execute(
        vm.initial.copyWith(title: 'Pickup', type: EventType.other),
      );
      expect(events.mine['u1']!.values.single.title, 'Pickup');
      expect(events.events.keys, ['e1']);
    });

    test('editors choose between personal and team schedules', () async {
      teams.teams['t2'] = teamWith({
        'owner': TeamRole.owner,
        'u1': TeamRole.coach,
      }, id: 't2');
      final vm = editor(null, teamId: 't2');
      await pumpEventQueue();
      expect(vm.canChooseSchedule, isTrue);
      expect(vm.editableTeams.map((t) => t.id), ['t2']);
      expect(vm.teamId, 't2');

      vm.setSchedule('t1'); // Not an editor there.
      expect(vm.teamId, 't2');
      await vm.save.execute(vm.initial.copyWith(title: 'Scrimmage'));
      expect(events.mine, isEmpty);
      expect(events.events.values.map((e) => e.title), contains('Scrimmage'));

      vm.setSchedule(null);
      expect(vm.isPersonal, isTrue);
      await vm.save.execute(
        vm.initial.copyWith(
          title: 'Lift',
          type: EventType.workout,
          poll: () => poll,
        ),
      );
      final lift = events.mine['u1']!.values.single;
      expect(lift.type, EventType.workout);
      expect(lift.poll, isNull);
    });

    test('edits a personal event in place', () async {
      events.mine['u1'] = {
        'm1': TeamEvent(
          id: 'm1',
          title: 'Run',
          startsAt: DateTime(2026, 11, 3, 7),
        ),
      };
      final vm = editor('m1', teamId: null);
      await pumpEventQueue();
      expect(vm.initial.title, 'Run');
      expect(vm.canChooseSchedule, isFalse);
      await vm.save.execute(vm.initial.copyWith(title: 'Long run'));
      expect(events.mine['u1']!['m1']!.title, 'Long run');
    });

    test('new events default to 6 PM on the chosen day', () async {
      final vm = editor(null, day: DateTime(2026, 12, 5));
      await pumpEventQueue();
      expect(vm.initial.startsAt, DateTime(2026, 12, 5, 18));
    });

    test('changing poll options clears votes; other edits keep them', () async {
      final vm = editor('e1');
      await pumpEventQueue();
      expect(vm.initial.title, 'Practice');

      await vm.save.execute(vm.initial.copyWith(title: 'Track'));
      expect(events.lastClearVotes, isFalse);

      await vm.save.execute(
        vm.initial.copyWith(
          poll: () => const EventPoll(
            question: 'Jerseys?',
            options: [PollOption(id: 'a', text: 'Dark')],
          ),
        ),
      );
      expect(events.lastClearVotes, isTrue);
    });
  });

  test(
    'TeamDetailViewModel splits upcoming events and events by day',
    () async {
      events.events['old'] = TeamEvent(
        id: 'old',
        title: 'Last week',
        startsAt: DateTime(2026, 10, 20, 18),
      );
      final vm = TeamDetailViewModel(
        teamId: 't1',
        teamRepository: teams,
        playRepository: FakePlayRepository(),
        eventRepository: events,
        authRepository: auth,
        clock: () => DateTime(2026, 10, 28),
      );
      await pumpEventQueue();
      expect(vm.events.map((e) => e.id), ['old', 'e1']);
      expect(vm.upcomingEvents.map((e) => e.id), ['e1']);
      expect(vm.eventsOn(DateTime(2026, 11, 2)).map((e) => e.id), ['e1']);
    },
  );

  test('MyEventDetailViewModel shows and deletes a personal event', () async {
    events.mine['u1'] = {
      'm1': TeamEvent(
        id: 'm1',
        title: 'Run',
        startsAt: DateTime(2026, 11, 3, 7),
      ),
    };
    final vm = MyEventDetailViewModel(
      eventId: 'm1',
      eventRepository: events,
      authRepository: auth,
    );
    await pumpEventQueue();
    expect(vm.loaded, isTrue);
    expect(vm.event?.title, 'Run');
    await vm.deleteEvent.execute();
    await pumpEventQueue();
    expect(vm.deleteEvent.completed, isTrue);
    expect(vm.event, isNull);
    vm.dispose();
  });
}
